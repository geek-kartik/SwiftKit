import SwiftUI
import SwiftKit

/// Home / Dashboard view providing a high-level overview of active SDK modules and navigation.
public struct DashboardView: View {
    @StateObject private var connectivityVM = ConnectivityViewModel()
    @StateObject private var deviceInfoVM = DeviceInfoViewModel()

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                // Header Status Card
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SwiftKit SDK")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                            Text(SwiftKit.isInitialized ? "Initialized" : "Not Ready")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(SwiftKit.isInitialized ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                .foregroundColor(SwiftKit.isInitialized ? .green : .red)
                                .cornerRadius(8)
                        }

                        Text("Production-grade iOS foundations with zero third-party dependencies.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Divider()

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                            StatusPill(
                                title: "Network",
                                value: connectivityVM.currentStatus.rawValue.capitalized,
                                color: connectivityVM.currentStatus == .connected ? .green : .orange
                            )
                            StatusPill(
                                title: "Device",
                                value: deviceInfoVM.deviceModel,
                                color: .blue
                            )
                            StatusPill(
                                title: "Build",
                                value: deviceInfoVM.isDebugBuild ? "DEBUG" : "RELEASE",
                                color: .purple
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }

                // Module Navigation Sections
                Section("SDK Modules") {
                    NavigationLink(destination: SecureStorageView()) {
                        ModuleRow(
                            icon: "lock.shield.fill",
                            title: "Secure Storage",
                            description: "Keychain CRUD, Codables, and error handling",
                            color: .indigo
                        )
                    }

                    NavigationLink(destination: DeviceInfoView()) {
                        ModuleRow(
                            icon: "iphone.gen3",
                            title: "Device Information",
                            description: "Hardware, OS, app metadata, and version gating",
                            color: .blue
                        )
                    }

                    NavigationLink(destination: ConnectivityView()) {
                        ModuleRow(
                            icon: "network",
                            title: "Connectivity Monitor",
                            description: "Real-time network path monitoring and observers",
                            color: .teal
                        )
                    }

                    NavigationLink(destination: SessionView()) {
                        ModuleRow(
                            icon: "person.badge.key.fill",
                            title: "Session Manager",
                            description: "Token lifecycle, observers, expiry, and 401 handling",
                            color: .pink
                        )
                    }

                    NavigationLink(destination: NetworkingView()) {
                        ModuleRow(
                            icon: "network.circle.fill",
                            title: "Networking Client",
                            description: "HTTP verbs, JSON mapping, bearer injection, and app-level 401 refresh",
                            color: .green
                        )
                    }

                    NavigationLink(destination: LoggingView()) {
                        ModuleRow(
                            icon: "terminal.fill",
                            title: "Structured Logging",
                            description: "OSLog levels and automatic data masking",
                            color: .orange
                        )
                    }
                }

                // SDK Configuration Information
                Section("SDK Environment Settings") {
                    HStack {
                        Text("Environment")
                        Spacer()
                        Text(SwiftKit.shared.configuration.environment.displayName)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Keychain Service")
                        Spacer()
                        Text(SwiftKit.shared.configuration.keychainService)
                            .foregroundColor(.secondary)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    HStack {
                        Text("Log Masking")
                        Spacer()
                        Text(SwiftKit.shared.configuration.isMaskingEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("SwiftKit Sample")
        }
        .navigationViewStyle(.stack)
        .onAppear {
            connectivityVM.startMonitoring()
            deviceInfoVM.loadDeviceInfo()
        }
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

private struct ModuleRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
