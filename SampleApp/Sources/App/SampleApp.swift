import SwiftUI
import SwiftKit

private struct SampleSessionRefreshHandler: SessionTokenRefreshHandler {
    func refresh(using refreshToken: String) async throws -> SessionTokenRefresh {
        let response = try await SampleBackend.shared.refresh(refreshToken: refreshToken)
        return SessionTokenRefresh(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }
}

/// Entry point for the SwiftKit Sample Application.
/// Demonstrates recommended initialization and integration of the SwiftKit SDK.
@main
public struct SampleApp: App {
    public init() {
        URLProtocol.registerClass(SampleURLProtocol.self)
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

        let network = NetworkConfiguration(
            baseURL: URL(string: "https://sample.swiftkit.test"),
            defaultHeaders: ["X-Sample-App": "SwiftKit-Sample"],
            onError: { transaction in
                NotificationCenter.default.post(
                    name: .sampleNetworkError,
                    object: nil,
                    userInfo: [
                        "status": transaction.statusCode ?? -1,
                        "path": transaction.pathText
                    ]
                )
            },
            onAuthenticationFailure: { transaction in
                NotificationCenter.default.post(
                    name: .sampleNetworkAuthenticationFailure,
                    object: nil,
                    userInfo: [
                        "status": transaction.statusCode ?? -1,
                        "path": transaction.pathText
                    ]
                )
            },
            tokenProvider: {
                SwiftKit.shared.session.currentSession?.accessToken
            }
        )

        let configuration = SwiftKitConfiguration(
            environment: .development,
            subsystem: "com.swiftkit.sampleapp",
            category: "SampleApp",
            minimumLogLevel: .debug,
            isMaskingEnabled: true,
            isLoggingEnabled: true,
            keychainService: "com.swiftkit.sampleapp.storage",
            keychainAccessibility: .afterFirstUnlockThisDeviceOnly,
            network: network,
            sessionTokenRefreshHandler: SampleSessionRefreshHandler()
        )

        do {
            try SwiftKit.initialize(configuration: configuration)
            SwiftKit.shared.connectivity.start()
            SwiftKit.shared.logger.info("SampleApp: SwiftKit initialized successfully.")
        } catch let error as SDKError {
            print("SampleApp: SDK initialization failed with error: \(error.localizedDescription)")
        } catch {
            print("SampleApp: Unexpected initialization error: \(error.localizedDescription)")
        }
    }
}
