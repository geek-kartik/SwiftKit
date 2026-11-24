import SwiftUI
import SwiftKit

public struct NetworkingView: View {
    @StateObject private var viewModel = NetworkingViewModel()

    public init() {}

    public var body: some View {
        Form {
            Section(header: HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.indigo)
                Text("Bearer Token Injection")
            }) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.indigo)
                    Text(viewModel.bearerStatus)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if viewModel.bearerStatus == "No active bearer token" {
                    Button {
                        viewModel.startDemoSession()
                    } label: {
                        Label("Start Demo Session", systemImage: "person.badge.key.fill")
                    }
                    Text("Start a session here or in the Session tab. NetworkConfiguration.tokenProvider reads SessionManagerProtocol and adds the Authorization header to every request.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("NetworkConfiguration.tokenProvider applied this token as an Authorization header on outgoing requests.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: HStack {
                Image(systemName: "square.and.pencil")
                Text("Request Builder")
            }) {
                Picker("HTTP Method", selection: $viewModel.selectedMethod) {
                    ForEach(HTTPMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Relative path", text: $viewModel.path)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Text("Headers · one Name: Value pair per line")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $viewModel.headersText)
                    .font(.system(.footnote, design: .monospaced))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .frame(minHeight: 56)

                if viewModel.isBodyVisible {
                    Text("JSON body · sent as raw JSON")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $viewModel.bodyText)
                        .font(.system(.footnote, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .frame(minHeight: 64)
                }

                TextField("Timeout in seconds", text: $viewModel.timeoutText)
                    .keyboardType(.decimalPad)

                Picker("Cache policy", selection: $viewModel.cachePolicy) {
                    ForEach(SampleCachePolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Label("Send Request", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }

            Section(header: HStack {
                Image(systemName: "function")
                Text("Quick Scenarios")
            }) {
                Button("GET /v1/items") {
                    Task { await viewModel.sendRequest(method: .get, path: "/v1/items") }
                }
                Button("POST /v1/items") {
                    Task { await viewModel.sendRequest(method: .post, path: "/v1/items", body: #"{"message":"Created from sample app"}"#) }
                }
                Button("PUT /v1/items/1") {
                    Task { await viewModel.sendRequest(method: .put, path: "/v1/items/1", body: #"{"message":"Replaced resource"}"#) }
                }
                Button("PATCH /v1/items/1") {
                    Task { await viewModel.sendRequest(method: .patch, path: "/v1/items/1", body: #"{"message":"Patched resource"}"#) }
                }
                Button("DELETE /v1/items/1") {
                    Task { await viewModel.sendRequest(method: .delete, path: "/v1/items/1") }
                }
                Button("404 Not Found (/v1/not-found)") {
                    Task { await viewModel.sendRequest(method: .get, path: "/v1/not-found") }
                }
                Button("HTTP 500 (/v1/failure)") {
                    Task { await viewModel.sendRequest(method: .get, path: "/v1/failure") }
                }
                Button("Decoding Failure (/v1/bad-json)") {
                    Task { await viewModel.sendRequest(method: .get, path: "/v1/bad-json") }
                }
                Button("401 → Refresh → Retry (/v1/protected)") {
                    Task { await viewModel.sendProtectedRequest() }
                }

                Text("The 401 flow is app-level: the screen calls SessionManagerProtocol.refreshSession(), then retries once. The SDK does not retry automatically. Repeated taps are suppressed while an identical request is in flight, and no retry happens after logout or expiry.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let response = viewModel.lastResponse {
                Section(header: HStack {
                Image(systemName: "terminal")
                Text("Last Response")
            }) {
                    metadataRow("Status", "HTTP \(response.statusCode)")
                    metadataRow("Content-Type", response.contentType ?? "—")
                    metadataRow("Body", "\(response.byteCount) bytes")
                    metadataRow("Duration", "\(response.elapsedMilliseconds) ms")
                    if let url = response.url {
                        metadataRow("URL", url.path)
                    }
                }
            }

            if !viewModel.responseText.isEmpty {
                Section(header: HStack {
                Image(systemName: "doc.text")
                Text("Response Body")
            }) {
                    Text(viewModel.responseText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !viewModel.statusMessage.isEmpty {
                Section(header: HStack {
                Image(systemName: "exclamationmark.shield.fill")
                Text("Operation Feedback")
            }) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: viewModel.isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(viewModel.isErrorMessage ? .red : .green)
                        Text(viewModel.statusMessage)
                            .font(.footnote)
                            .foregroundColor(viewModel.isErrorMessage ? .red : .primary)
                    }
                    if viewModel.didRetryAfter401 {
                        Label("Retried once after 401 using SessionManagerProtocol.refreshSession().", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundColor(.indigo)
                    }
                }
            }

            Section(header: Text("Developer Diagnostics")) {
                Toggle("Log request results to OSLog", isOn: $viewModel.logsDiagnostics)
                Text("When enabled, each result is written through LoggerProtocol at info or error level with sensitive values masked. Turn it off to keep request details out of device logs.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                metadataRow("In flight", "\(viewModel.inFlightCount)")
                metadataRow("Duplicates blocked", "\(viewModel.suppressedDuplicateCount)")
            }

            Section(header: HStack {
                Text("Call History (\(viewModel.callHistory.count))")
                Spacer()
                if !viewModel.callHistory.isEmpty || !viewModel.callbackEvents.isEmpty {
                    Button("Clear") { viewModel.clearHistory() }
                        .font(.caption)
                }
            }) {
                if viewModel.callHistory.isEmpty {
                    Text("No requests recorded yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.callHistory) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("\(record.method.rawValue) \(record.path)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let statusCode = record.statusCode {
                                    Text("\(statusCode)")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(statusColor(for: statusCode).opacity(0.15))
                                        .foregroundColor(statusColor(for: statusCode))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text(record.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(record.detail)
                                .font(.caption)
                                .foregroundColor(record.isError ? .red : .secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }

            if !viewModel.callbackEvents.isEmpty {
                Section(header: Text("Configuration Callbacks")) {
                    ForEach(viewModel.callbackEvents, id: \.self) { event in
                        Text(event)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Networking Client")
        .onAppear { viewModel.activate() }
        .onDisappear { viewModel.cleanup() }
        .overlay {
            // Full-screen loading modal with a fade (opacity) transition.
            // A 70%-transparent dimming layer keeps the main content visible behind it.
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Request in flight")
                            .font(.headline)
                        Text("\(viewModel.inFlightCount) active request(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(role: .cancel) {
                            viewModel.cancelActiveRequest()
                        } label: {
                            Label("Cancel Request", systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(32)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
    }

    private func statusColor(for statusCode: Int) -> Color {
        if (200..<300).contains(statusCode) { return .green }
        if (300..<400).contains(statusCode) { return .orange }
        return .red
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
    }
}
