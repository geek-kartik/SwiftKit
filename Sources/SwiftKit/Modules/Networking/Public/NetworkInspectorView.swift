#if canImport(UIKit)
import Combine
import Foundation
import SwiftUI
import UIKit

/// SDK-provided SwiftUI screen showing every captured network transaction.
///
/// The view lists the full session history newest-first, supports text filtering, and opens a
/// detail screen with headers, bodies, timing, and a copy-as-cURL action.
///
/// Present it from a host `NavigationView`/`NavigationStack`, wrap it in one when presenting
/// modally, or attach ``NetworkInspectorOverlay`` for a draggable global trigger:
///
/// ```swift
/// NavigationView {
///     NetworkInspectorView(inspector: SwiftKit.shared.networkInspector)
/// }
/// ```
///
/// The inspector records nothing unless ``NetworkInspectorConfiguration/isEnabled`` is `true`.
public struct NetworkInspectorView: View {
    @StateObject private var model: NetworkInspectorViewModel
    @State private var query = ""
    @State private var filter: NetworkTransactionFilter = .all

    /// Creates an inspector screen bound to an inspector instance.
    /// - Parameter inspector: The SDK inspector to display, usually `SwiftKit.shared.networkInspector`.
    public init(inspector: NetworkInspectorProtocol) {
        _model = StateObject(wrappedValue: NetworkInspectorViewModel(inspector: inspector))
    }

    public var body: some View {
        List {
            if model.transactions.isEmpty {
                emptyState
            } else {
                summarySection
                filterSection

                if filteredTransactions.isEmpty {
                    noMatchesState
                } else {
                    ForEach(filteredTransactions) { transaction in
                        NavigationLink {
                            NetworkTransactionDetailView(
                                transaction: transaction,
                                sensitiveDataPolicy: model.configuration.sensitiveDataPolicy
                            )
                        } label: {
                            NetworkTransactionRow(transaction: transaction)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                InspectorClipboard.copy(
                                    transaction.curlCommand(
                                        sensitiveDataPolicy: model.configuration.sensitiveDataPolicy
                                    )
                                )
                            } label: {
                                Label("cURL", systemImage: "doc.on.doc")
                            }
                            .tint(.indigo)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Filter by method, URL, status, or error"
        )
        .navigationTitle("Network Log")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Show", selection: $filter) {
                        ForEach(NetworkTransactionFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .disabled(model.transactions.isEmpty)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    model.clear()
                }
                .disabled(model.transactions.isEmpty)
            }
        }
        .task {
            await model.observe()
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack(spacing: 10) {
                NetworkSummaryTile(
                    title: "Total",
                    value: "\(model.transactions.count)",
                    tint: .primary
                )
                NetworkSummaryTile(
                    title: "Succeeded",
                    value: "\(model.successCount)",
                    tint: .green
                )
                NetworkSummaryTile(
                    title: "Failed",
                    value: "\(model.failureCount)",
                    tint: .red
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)

            if model.configuration.sensitiveDataPolicy == .include {
                Label("Credential headers are shown verbatim. Use only with non-production credentials.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var filterSection: some View {
        Section {
            Picker("Filter", selection: $filter) {
                ForEach(NetworkTransactionFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)

                Text("No transactions yet")
                    .font(.headline)

                Text(
                    model.configuration.isEnabled
                        ? "Requests issued through SwiftKit's network client will appear here."
                        : "The inspector is disabled. Enable NetworkInspectorConfiguration in your NetworkConfiguration to capture traffic."
                )
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private var noMatchesState: some View {
        Section {
            Text("No transactions match “\(query)”.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var filteredTransactions: [NetworkTransaction] {
        model.filteredTransactions(query: query, filter: filter)
    }
}

// MARK: - Row

private struct NetworkTransactionRow: View {
    let transaction: NetworkTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NetworkMethodBadge(method: transaction.request.method)

                Text(transaction.pathText)
                    .font(.subheadline.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                NetworkStatusBadge(transaction: transaction)
            }

            HStack(spacing: 8) {
                Text(transaction.durationText)
                Text("•")
                Text(transaction.startedAt, style: .time)
                Spacer()

                if let error = transaction.error {
                    Text(error.logDescription)
                        .lineLimit(1)
                } else {
                    Text(HTTPStatusText.byteCount(transaction.response?.body.totalByteCount ?? 0))
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

private struct NetworkTransactionDetailView: View {
    let transaction: NetworkTransaction
    let sensitiveDataPolicy: NetworkInspectorConfiguration.SensitiveDataPolicy

    @State private var copied = false

    var body: some View {
        List {
            overviewSection

            if let error = transaction.error {
                failureSection(error)
            }

            NetworkHeaderSection(
                title: "Request headers",
                headers: displayedHeaders(transaction.request.headers)
            )

            NetworkBodySection(
                title: "Request body",
                body: transaction.request.body
            )

            if let response = transaction.response {
                NetworkHeaderSection(
                    title: "Response headers",
                    headers: displayedHeaders(response.headers)
                )

                NetworkBodySection(
                    title: "Response body",
                    body: response.body
                )
            }

            exportSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(transaction.request.method.rawValue) \(transaction.statusCode.map(String.init) ?? "Failed")")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    copyCurl()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
            }
        }
    }

    // MARK: Sections

    private var overviewSection: some View {
        Section(header: Text("Overview")) {
            NetworkDetailRow(title: "Method", value: transaction.request.method.rawValue)
            NetworkDetailRow(title: "Status", value: statusText)
            NetworkDetailRow(title: "Duration", value: transaction.durationText)
            NetworkDetailRow(title: "Started", value: Self.timestampFormatter.string(from: transaction.startedAt))

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(transaction.request.url.absoluteString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        }
    }

    private func failureSection(_ error: NetworkError) -> some View {
        Section(header: Text("Failure")) {
            Text(error.errorDescription ?? "Unknown networking failure.")
                .font(.footnote)

            HStack(spacing: 6) {
                if error.isRetryable {
                    NetworkTag(text: "Retryable", tint: .blue)
                }
                if error.isAuthenticationFailure {
                    NetworkTag(text: "Authentication", tint: .orange)
                }
                NetworkTag(text: error.logDescription, tint: .secondary)
            }
        }
    }

    private var exportSection: some View {
        Section(
            header: Text("Export"),
            footer: Text(
                sensitiveDataPolicy == .redact
                    ? "Credential headers are redacted. Enable .include in the inspector configuration to export a replayable command."
                    : "This command includes live credential headers."
            )
        ) {
            Button {
                copyCurl()
            } label: {
                Label(copied ? "Copied to clipboard" : "Copy as cURL", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
            }
            .disabled(transaction.request.url.scheme == nil)
        }
    }

    // MARK: Helpers

    private var statusText: String {
        guard let statusCode = transaction.statusCode else { return "No response" }
        return HTTPStatusText.statusLine(statusCode)
    }

    private func displayedHeaders(_ headers: [String: String]) -> [String: String] {
        sensitiveDataPolicy == .redact ? SensitiveHeaders.redacted(headers) : headers
    }

    private func copyCurl() {
        InspectorClipboard.copy(
            transaction.curlCommand(sensitiveDataPolicy: sensitiveDataPolicy)
        )
        copied = true

        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copied = false
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

// MARK: - Building blocks

private struct NetworkSummaryTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundColor(tint)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

private struct NetworkMethodBadge: View {
    let method: HTTPMethod

    var body: some View {
        Text(method.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .cornerRadius(5)
    }

    private var tint: Color {
        switch method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return .purple
        case .delete: return .red
        }
    }
}

private struct NetworkStatusBadge: View {
    let transaction: NetworkTransaction

    var body: some View {
        Text(transaction.statusCode.map(String.init) ?? "—")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .cornerRadius(5)
    }

    private var tint: Color {
        guard let statusCode = transaction.statusCode else { return .secondary }
        if (200..<300).contains(statusCode) { return .green }
        if statusCode == 401 || statusCode == 403 { return .orange }
        return .red
    }
}

private struct NetworkDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct NetworkTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .cornerRadius(5)
    }
}

private struct NetworkHeaderSection: View {
    let title: String
    let headers: [String: String]

    var body: some View {
        Section(header: Text(title)) {
            if headers.isEmpty {
                Text("No headers")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(headers.keys.sorted { $0.lowercased() < $1.lowercased() }, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.caption.weight(.semibold).monospaced())
                        Text(headers[name] ?? "")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct NetworkBodySection: View {
    let title: String
    let capturedBody: NetworkTransaction.Body?

    init(title: String, body: NetworkTransaction.Body?) {
        self.title = title
        self.capturedBody = body
    }

    var body: some View {
        Section(
            header: Text(title),
            footer: footerText
        ) {
            if let capturedBody, !capturedBody.data.isEmpty {
                Text(Self.formatted(capturedBody))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            } else {
                Text("No body")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var footerText: Text? {
        guard let capturedBody, capturedBody.isTruncated else { return nil }
        return Text(
            "Showing \(HTTPStatusText.byteCount(capturedBody.data.count)) of \(HTTPStatusText.byteCount(capturedBody.totalByteCount))."
        )
    }

    private static func formatted(_ body: NetworkTransaction.Body) -> String {
        guard let text = JSONTextFormatter.displayText(from: body.data) else {
            return "<binary \(body.data.count) bytes>"
        }
        return text
    }
}

// MARK: - Clipboard

private enum InspectorClipboard {
    static func copy(_ value: String) {
        UIPasteboard.general.string = value
    }
}
#endif
