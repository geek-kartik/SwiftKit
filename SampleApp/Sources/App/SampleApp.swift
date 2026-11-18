import SwiftUI
import SwiftKit

/// Entry point for the SwiftKit Sample Application.
/// Demonstrates recommended initialization and integration of the SwiftKit SDK.
@main
public struct SampleApp: App {
    public init() {
        configureSwiftKit()
    }

    public var body: some Scene {
        WindowGroup {
            DashboardView()
        }
    }

    /// Configures and initializes SwiftKit using the SDK's public configuration API.
    private func configureSwiftKit() {
        guard !SwiftKit.isInitialized else {
            return
        }

        let configuration = SwiftKitConfiguration(
            environment: .development,
            subsystem: "com.swiftkit.sampleapp",
            category: "SampleApp",
            minimumLogLevel: .debug,
            isMaskingEnabled: true,
            isLoggingEnabled: true,
            keychainService: "com.swiftkit.sampleapp.storage",
            keychainAccessibility: .afterFirstUnlockThisDeviceOnly
        )

        do {
            try SwiftKit.initialize(configuration: configuration)
            SwiftKit.shared.logger.info("SampleApp: SwiftKit initialized successfully.")
        } catch let error as SDKError {
            // Gracefully handle specific SDK error conditions
            print("SampleApp: SDK initialization failed with error: \(error.localizedDescription)")
        } catch {
            print("SampleApp: Unexpected initialization error: \(error.localizedDescription)")
        }
    }
}
