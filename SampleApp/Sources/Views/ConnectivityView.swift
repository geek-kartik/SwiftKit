import SwiftUI
import SwiftKit

/// UI demonstrating real-time network path monitoring, status transitions, and lifecycle observer handling.
public struct ConnectivityView: View {
    @StateObject private var viewModel = ConnectivityViewModel()

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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                    Button(action: { viewModel.startMonitoring() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .renderingMode(.template)
                                .foregroundStyle(.white)
                            Text("Start")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isMonitoring)

                    Button(action: { viewModel.stopMonitoring() }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!viewModel.isMonitoring)

                    Button(action: { viewModel.toggleObserver() }) {
                        Label(viewModel.hasActiveObserver ? "Remove Obs" : "Add Obs",
                              systemImage: viewModel.hasActiveObserver ? "minus.circle" : "plus.circle")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(viewModel.hasActiveObserver ? .red : .green)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.hasActiveObserver ? .red : .green)
                }
                .padding(.vertical, 4)
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
