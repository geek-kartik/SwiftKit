import SwiftUI
import SwiftKit

/// UI demonstrating real-time network path monitoring, status transitions, and lifecycle observer handling.
public struct ConnectivityView: View {
    @StateObject private var viewModel = ConnectivityViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init() {}

    public var body: some View {
        List {
            // Live Status Card
            Section(header: Text("Live Connection Status")) {
                HStack {
                    Circle()
                        .fill(statusColor(viewModel.currentStatus))
                        .frame(width: 14, height: 14)

                    Text(viewModel.currentStatus.rawValue.capitalized)
                        .font(.headline)

                    Spacer()

                    Text(viewModel.isMonitoring ? "Monitoring Active" : "Stopped")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(viewModel.isMonitoring ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                        .cornerRadius(6)
                }

                HStack {
                    Text("Observer Active:")
                    Spacer()
                    Text(viewModel.hasActiveObserver ? "Registered" : "Unregistered")
                        .foregroundColor(viewModel.hasActiveObserver ? .green : .secondary)
                }
            }

            // Controls
            Section(header: Text("Monitor Lifecycle Controls")) {
                if horizontalSizeClass == .regular {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120, maximum: 220), spacing: 10), count: 3), spacing: 10) {
                        startButton
                        stopButton
                        observerButton
                    }
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            startButton
                            stopButton
                        }
                        observerButton
                    }
                    .padding(.vertical, 4)
                }
            }

            // Note on reachability
            Section {
                Text("Note: Apple Network framework reports whether a satisfied network path is present. An active path does not guarantee that a specific remote host is reachable.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Transition History Log
            Section(header: HStack {
                Text("Path Transitions (\(viewModel.eventLog.count))")
                Spacer()
                if !viewModel.eventLog.isEmpty {
                    Button("Clear", action: { viewModel.clearEventLog() })
                        .font(.caption)
                }
            }) {
                if viewModel.eventLog.isEmpty {
                    Text("No transitions recorded yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.eventLog) { event in
                        HStack {
                            Circle()
                                .fill(statusColor(event.status))
                                .frame(width: 8, height: 8)
                            Text(event.status.rawValue.capitalized)
                                .font(.subheadline)
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Connectivity Monitor")
        .onAppear {
            viewModel.startMonitoring()
        }
    }

    private var startButton: some View {
        Button(action: { viewModel.startMonitoring() }) {
            StartButtonLabel()
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isMonitoring)
    }

    private var stopButton: some View {
        Button(action: { viewModel.stopMonitoring() }) {
            Label("Stop", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(!viewModel.isMonitoring)
    }

    private var observerButton: some View {
        Button(action: { viewModel.toggleObserver() }) {
            Label(viewModel.hasActiveObserver ? "Remove Obs" : "Add Obs",
                  systemImage: viewModel.hasActiveObserver ? "minus.circle" : "plus.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private struct StartButtonLabel: View {
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            HStack(spacing: 6) {
                if isEnabled {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text("Start")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statusColor(_ status: ConnectivityStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .disconnected:
            return .red
        case .unknown:
            return .orange
        }
    }
}
