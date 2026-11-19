import SwiftUI
import SwiftKit

public struct SessionView: View {
    @StateObject private var viewModel = SessionViewModel()

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Current Session State")) {
                HStack {
                    Text(viewModel.stateTitle)
                        .font(.headline)
                    Spacer()
                    Text(viewModel.isAuthenticated ? "Authenticated" : "Inactive")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(viewModel.isAuthenticated ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .foregroundColor(viewModel.isAuthenticated ? .green : .orange)
                        .cornerRadius(8)
                }

                detailRow("User", viewModel.userID)
                detailRow("Access Token", viewModel.maskedAccessToken)
                detailRow("Expires", viewModel.expiryText)
            }

            Section(header: Text("New Session Credentials")) {
                TextField("Access token", text: $viewModel.accessTokenInput)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                TextField("Refresh token", text: $viewModel.refreshTokenInput)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack {
                    Text("Lifetime")
                    Slider(value: $viewModel.lifetimeSeconds, in: 60...86_400, step: 60)
                }
                Text("Expires in \(Int(viewModel.lifetimeSeconds / 60)) minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Lifecycle Controls")) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    actionButton("Start", systemImage: "person.badge.key.fill") {
                        viewModel.startSession()
                    }
                    actionButton("Restore", systemImage: "arrow.clockwise") {
                        viewModel.restoreSession()
                    }
                    actionButton("Validate Expiry", systemImage: "clock.badge.checkmark") {
                        viewModel.validateExpiry()
                    }
                    actionButton("Refresh Sync", systemImage: "arrow.triangle.2.circlepath") {
                        viewModel.refreshSynchronously()
                    }
                    actionButton("Refresh Async", systemImage: "bolt.fill") {
                        Task { await viewModel.refreshAsynchronously() }
                    }
                    actionButton("Simulate 401", systemImage: "exclamationmark.shield.fill") {
                        viewModel.handleUnauthorized()
                    }
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    Label("Logout and Clear Storage", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
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
                }
            }

            Section(header: HStack {
                Text("Observer Events (\(viewModel.events.count))")
                Spacer()
                if !viewModel.events.isEmpty {
                    Button("Clear") { viewModel.clearEvents() }
                        .font(.caption)
                }
            }) {
                if viewModel.events.isEmpty {
                    Text("No session transitions observed yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.events) { record in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.indigo)
                            Text(record.title)
                                .font(.subheadline)
                            Spacer()
                            Text(record.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Session Manager")
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
