import SwiftUI
import SwiftKit

/// UI for displaying device model, OS version, application metrics, and version comparisons.
public struct DeviceInfoView: View {
    @StateObject private var viewModel = DeviceInfoViewModel()

    public init() {}

    public var body: some View {
        List {
            // Hardware & Platform
            Section(header: Text("Hardware & System")) {
                InfoRow(title: "Device Model", value: viewModel.deviceModel)
                InfoRow(title: "OS Version", value: viewModel.osVersion)
                InfoRow(title: "Simulator", value: viewModel.isSimulator ? "Yes" : "No")
                InfoRow(title: "Debug Build", value: viewModel.isDebugBuild ? "Yes" : "No")
            }

            // Application Metadata
            Section(header: Text("Application Metadata")) {
                InfoRow(title: "App Name", value: viewModel.appName)
                InfoRow(title: "App Version", value: viewModel.appVersion)
                InfoRow(title: "Build Number", value: viewModel.buildNumber)
                InfoRow(title: "Bundle Identifier", value: viewModel.bundleIdentifier)
            }

            // Version Comparison Tool
            Section(header: Text("App Version Gating Checks")) {
                HStack(spacing: 12) {
                    Text("Target Version:")
                        .layoutPriority(1)
                    Spacer(minLength: 12)
                    TextField("Target", text: $viewModel.comparisonTargetVersion)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 100, maxWidth: 160)
                        .onChange(of: viewModel.comparisonTargetVersion) { _ in
                            viewModel.evaluateAppVersion()
                        }
                }

                HStack {
                    Text("At Least Target:")
                    Spacer()
                    Text(viewModel.isAppVersionAtLeastResult ? "TRUE" : "FALSE")
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isAppVersionAtLeastResult ? .green : .orange)
                }

                HStack {
                    Text("Update Required:")
                    Spacer()
                    Text(viewModel.isUpdateRequiredResult ? "REQUIRED" : "UP TO DATE")
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isUpdateRequiredResult ? .red : .green)
                }
            }

            // OS Version Check
            Section(header: Text("OS Version Check")) {
                HStack(spacing: 12) {
                    Text("Minimum OS:")
                        .layoutPriority(1)
                    Spacer(minLength: 12)
                    TextField("Min OS", text: $viewModel.osComparisonTargetVersion)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 100, maxWidth: 160)
                        .onChange(of: viewModel.osComparisonTargetVersion) { _ in
                            viewModel.evaluateOSVersion()
                        }
                }

                HStack {
                    Text("OS Meets Minimum:")
                    Spacer()
                    Text(viewModel.isOSVersionAtLeastResult ? "YES" : "NO")
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isOSVersionAtLeastResult ? .green : .red)
                }
            }
        }
        .navigationTitle("Device Information")
        .refreshable {
            viewModel.loadDeviceInfo()
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .foregroundColor(.primary)
                .layoutPriority(1)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "unavailable" : value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
