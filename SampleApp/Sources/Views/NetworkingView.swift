import SwiftUI
import SwiftKit

public struct NetworkingView: View {
    @StateObject private var viewModel = NetworkingViewModel()

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Bearer Token Injection")) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.indigo)
                    Text(viewModel.bearerStatus)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text("NetworkConfiguration.tokenProvider reads the active Session automatically. Start a session in the Session tab to see the Authorization header applied.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Request Builder")) {
                Picker("HTTP Method", selection: $viewModel.selectedMethod) {
                    ForEach(HTTPMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Relative path", text: $viewModel.path)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                TextField("JSON body message", text: $viewModel.bodyText)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Button {
                    Task { await viewModel.send() }
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Send Request")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }

            Section(header: Text("Quick Scenarios")) {
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
                Button("401 → Refresh → Retry (/v1/protected)") {
                    Task { await viewModel.sendRequest(method: .get, path: "/v1/protected") }
                }
                Button("HTTP 500 (/v1/failure)") {
                    Task { await viewModel.sendRequest(method: .get, path: "/v1/failure") }
                }
                Button("Decoding Failure (/v1/bad-json)") {
                    Task { await viewModel.sendRequest(method: .get, path: "/v1/bad-json") }
                }
            }

            if !viewModel.responseText.isEmpty {
                Section(header: Text("Decoded Response")) {
                    Text(viewModel.responseText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !viewModel.statusMessage.isEmpty {
                Section(header: Text("Operation Feedback")) {
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
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(record.method.rawValue) \(record.path)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(record.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(record.detail)
                                .font(.caption)
                                .foregroundColor(record.isError ? .red : .secondary)
                                .lineLimit(2)
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
    }
}
