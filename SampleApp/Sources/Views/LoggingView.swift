import SwiftUI
import SwiftKit

/// UI demonstrating structured logging via `LoggerProtocol`, log levels, and automatic data redaction.
public struct LoggingView: View {
    @StateObject private var viewModel = LoggingViewModel()

    public init() {}

    public var body: some View {
        List {
            // Standard Log Buttons (2 tiles per row)
            Section(header: Text("Predefined Log Level Triggers")) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    Button(action: { viewModel.logInfo() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.headline)
                            Text("Info")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button(action: { viewModel.logDebug() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "ladybug.fill")
                                .font(.headline)
                            Text("Debug")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)

                    Button(action: { viewModel.logWarning() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.headline)
                            Text("Warning")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button(action: { viewModel.logError() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.headline)
                            Text("Error")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }

            // Custom Message Dispatch
            Section(header: Text("Custom Log Dispatch")) {
                TextField("Custom Message", text: $viewModel.customMessage)

                Picker("Severity Level", selection: $viewModel.selectedLogLevel) {
                    Text("Debug (0)").tag(LogLevel.debug)
                    Text("Info (1)").tag(LogLevel.info)
                    Text("Warning (2)").tag(LogLevel.warning)
                    Text("Error (3)").tag(LogLevel.error)
                    Text("None (99)").tag(LogLevel.none)
                }
                .pickerStyle(.menu)

                Button(action: {
                    viewModel.logCustom()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .renderingMode(.template)
                        Text("Dispatch Log")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, 4)
            }

            // Sensitive Data Redaction Demo
            Section(header: Text("Automatic Data Masking Demonstration")) {
                Text(viewModel.maskingStatusInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Sample Bearer Token", text: $viewModel.sampleBearerInput)
                    .font(.footnote)
                    .disableAutocorrection(true)

                TextField("Sample Email", text: $viewModel.sampleEmailInput)
                    .font(.footnote)
                    .disableAutocorrection(true)

                Button("Test Masked Log Dispatch") {
                    viewModel.demonstrateAutomaticMasking()
                }
                .buttonStyle(.bordered)
            }

            // Dispatched Console Logs
            Section(header: HStack {
                Text("Dispatched In-App Console (\(viewModel.dispatchedLogs.count))")
                Spacer()
                if !viewModel.dispatchedLogs.isEmpty {
                    Button("Clear", action: { viewModel.clearDispatchedLogs() })
                        .font(.caption)
                }
            }) {
                if viewModel.dispatchedLogs.isEmpty {
                    Text("No logs dispatched yet. Tap a button above.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.dispatchedLogs) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.level.label)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(badgeColor(entry.level).opacity(0.2))
                                    .foregroundColor(badgeColor(entry.level))
                                    .cornerRadius(4)

                                Spacer()

                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(entry.message)
                                .font(.system(.footnote, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("SDK Logger")
    }

    private func badgeColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug:
            return .gray
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        case .none:
            return .purple
        }
    }
}
