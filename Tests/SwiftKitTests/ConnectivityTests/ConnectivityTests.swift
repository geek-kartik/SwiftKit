import Foundation
import Network
import XCTest
@testable import SwiftKit

final class ConnectivityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftKit.resetForTesting()
    }

    override func tearDown() {
        SwiftKit.resetForTesting()
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStatusIsUnknownAndNotMonitoring() {
        let (monitor, _, _) = makeMonitor()

        XCTAssertEqual(monitor.currentStatus, .unknown)
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testObserverReceivesUnknownSnapshotOnRegistration() {
        let (monitor, _, _) = makeMonitor()
        let observed = ThreadSafeBox<[ConnectivityStatus]>([])

        monitor.addObserver { status in
            observed.mutate { $0.append(status) }
        }

        XCTAssertEqual(observed.current, [.unknown])
    }

    func testObserverReceivesCurrentKnownSnapshotOnRegistration() {
        let (monitor, _, factory) = makeMonitor()
        monitor.start()
        factory.latestEngine?.simulate(.connected)

        let observed = ThreadSafeBox<[ConnectivityStatus]>([])
        monitor.addObserver { status in
            observed.mutate { $0.append(status) }
        }

        XCTAssertEqual(observed.current, [.connected])
    }

    func testFirstDisconnectedPathUpdateTransitionsFromUnknown() {
        let (monitor, _, factory) = makeMonitor()
        let observed = ThreadSafeBox<[ConnectivityStatus]>([])

        monitor.addObserver { status in
            observed.mutate { $0.append(status) }
        }

        monitor.start()
        factory.latestEngine?.simulate(.disconnected)

        XCTAssertEqual(monitor.currentStatus, .disconnected)
        XCTAssertEqual(observed.current, [.unknown, .disconnected])
    }

    // MARK: - Lifecycle

    func testStartBeginsMonitoringAndStartsEngine() {
        let (monitor, _, factory) = makeMonitor()

        monitor.start()

        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertEqual(factory.createdEngines.count, 1)
        XCTAssertEqual(factory.latestEngine?.startCount, 1)
    }

    func testRepeatedStartDoesNotCreateAdditionalEngines() {
        let (monitor, _, factory) = makeMonitor()

        monitor.start()
        monitor.start()
        monitor.start()

        XCTAssertEqual(factory.createdEngines.count, 1)
        XCTAssertEqual(factory.latestEngine?.startCount, 1)
    }

    func testStopCancelsEngineAndStopsMonitoring() {
        let (monitor, _, factory) = makeMonitor()
        monitor.start()

        monitor.stop()

        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertTrue(factory.latestEngine?.isCancelled == true)
    }

    func testRepeatedStopIsSafe() {
        let (monitor, _, factory) = makeMonitor()
        monitor.start()

        monitor.stop()
        monitor.stop()

        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(factory.createdEngines.count, 1)
    }

    func testRestartCreatesNewSessionAndIgnoresPreviousSessionUpdates() {
        let (monitor, _, factory) = makeMonitor()
        let observed = ThreadSafeBox<[ConnectivityStatus]>([])

        monitor.addObserver { status in
            observed.mutate { $0.append(status) }
        }

        monitor.start()
        let firstEngine = factory.latestEngine
        firstEngine?.simulate(.connected)

        monitor.stop()
        monitor.start()

        let secondEngine = factory.latestEngine
        XCTAssertEqual(factory.createdEngines.count, 2)
        XCTAssertFalse(firstEngine === secondEngine)

        firstEngine?.simulate(.disconnected)
        secondEngine?.simulate(.disconnected)

        XCTAssertEqual(observed.current, [.unknown, .connected, .disconnected])
        XCTAssertEqual(monitor.currentStatus, .disconnected)
    }

    // MARK: - Status Transitions

    func testStatusTransitionFromInitialStateToConnected() {
        let (monitor, _, factory) = makeMonitor()
        monitor.start()

        factory.latestEngine?.simulate(.connected)

        XCTAssertEqual(monitor.currentStatus, .connected)
    }

    func testStatusTransitionFromConnectedToDisconnected() {
        let (monitor, _, factory) = makeMonitor()
        monitor.start()
        factory.latestEngine?.simulate(.connected)

        factory.latestEngine?.simulate(.disconnected)

        XCTAssertEqual(monitor.currentStatus, .disconnected)
    }

    // MARK: - Observer Notifications

    func testObserversReceiveEveryStatusChange() {
        let (monitor, _, factory) = makeMonitor()
        let observed = ThreadSafeBox<[ConnectivityStatus]>([])

        monitor.addObserver { status in
            observed.mutate { $0.append(status) }
        }

        monitor.start()
        factory.latestEngine?.simulate(.connected)
        factory.latestEngine?.simulate(.disconnected)
        factory.latestEngine?.simulate(.connected)

        XCTAssertEqual(observed.current, [.unknown, .connected, .disconnected, .connected])
    }

    func testUnchangedStatusDoesNotNotifyObservers() {
        let (monitor, _, factory) = makeMonitor()
        let notifications = ThreadSafeBox<Int>(0)

        monitor.addObserver { status in
            guard status != .unknown else {
                return
            }
            notifications.mutate { $0 += 1 }
        }

        monitor.start()
        factory.latestEngine?.simulate(.connected)
        factory.latestEngine?.simulate(.connected)
        factory.latestEngine?.simulate(.connected)

        XCTAssertEqual(notifications.current, 1)
    }

    func testMultipleObserversReceiveUpdates() {
        let (monitor, _, factory) = makeMonitor()
        let first = ThreadSafeBox<[ConnectivityStatus]>([])
        let second = ThreadSafeBox<[ConnectivityStatus]>([])

        monitor.addObserver { status in first.mutate { $0.append(status) } }
        monitor.addObserver { status in second.mutate { $0.append(status) } }

        monitor.start()
        factory.latestEngine?.simulate(.connected)

        XCTAssertEqual(first.current, [.unknown, .connected])
        XCTAssertEqual(second.current, [.unknown, .connected])
    }

    func testRemovedObserverStopsReceivingUpdates() {
        let (monitor, _, factory) = makeMonitor()
        let observed = ThreadSafeBox<[ConnectivityStatus]>([])

        let token = monitor.addObserver { status in
            observed.mutate { $0.append(status) }
        }

        monitor.start()
        factory.latestEngine?.simulate(.connected)
        monitor.removeObserver(token)
        factory.latestEngine?.simulate(.disconnected)

        XCTAssertEqual(observed.current, [.unknown, .connected])
    }

    func testObserverCanRemoveAnotherObserverDuringCallback() {
        let (monitor, _, factory) = makeMonitor()
        let removedObserverCalls = ThreadSafeBox<Int>(0)
        let remainingObserverCalls = ThreadSafeBox<Int>(0)

        let removedToken = monitor.addObserver { _ in
            removedObserverCalls.mutate { $0 += 1 }
        }

        monitor.addObserver { status in
            guard status != .unknown else {
                return
            }
            remainingObserverCalls.mutate { $0 += 1 }
            monitor.removeObserver(removedToken)
        }

        monitor.start()
        factory.latestEngine?.simulate(.connected)
        factory.latestEngine?.simulate(.disconnected)

        let removedCount = removedObserverCalls.current
        let remainingCount = remainingObserverCalls.current
        XCTAssertLessThanOrEqual(removedCount, 2)
        XCTAssertEqual(remainingCount, 2)
    }

    func testNoCallbacksAfterStop() {
        let (monitor, _, factory) = makeMonitor()
        let notifications = ThreadSafeBox<Int>(0)

        monitor.addObserver { _ in
            notifications.mutate { $0 += 1 }
        }

        monitor.start()
        let engine = factory.latestEngine
        monitor.stop()
        let notificationsAfterStop = notifications.current
        engine?.simulate(.connected)

        XCTAssertEqual(notificationsAfterStop, 1)
        XCTAssertEqual(notifications.current, notificationsAfterStop)
    }

    // MARK: - Threading

    func testObserverCallbacksAreDeliveredOnMonitorQueue() {
        let queueKey = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: "com.swiftkit.tests.connectivity")
        queue.setSpecific(key: queueKey, value: "monitor")

        let (monitor, _, factory) = makeMonitor(queue: queue)
        let callbackExpectation = expectation(description: "Observer callback delivered")
        let deliveredOnQueue = ThreadSafeBox<Bool>(false)

        monitor.addObserver { status in
            guard status != .unknown else {
                return
            }
            deliveredOnQueue.write(DispatchQueue.getSpecific(key: queueKey) == "monitor")
            callbackExpectation.fulfill()
        }

        monitor.start()
        factory.latestEngine?.simulateOnMonitorQueue(.connected)

        wait(for: [callbackExpectation], timeout: 2.0)
        XCTAssertTrue(deliveredOnQueue.current)
    }

    func testConcurrentStartAndStopCallsAreSafe() {
        let (monitor, _, factory) = makeMonitor()

        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            if iteration.isMultiple(of: 2) {
                monitor.start()
            } else {
                monitor.stop()
            }
        }

        monitor.start()
        XCTAssertTrue(monitor.isMonitoring)

        let notifications = ThreadSafeBox<Int>(0)
        monitor.addObserver { status in
            guard status != .unknown else {
                return
            }
            notifications.mutate { $0 += 1 }
        }
        factory.latestEngine?.simulate(.connected)

        XCTAssertEqual(monitor.currentStatus, .connected)
        XCTAssertEqual(notifications.current, 1)
    }

    func testConcurrentObserverRegistrationAndRemovalAreSafe() {
        let (monitor, _, factory) = makeMonitor()
        let callbackCount = ThreadSafeBox<Int>(0)
        let tokens = ThreadSafeBox<[ConnectivityObservationToken]>([])

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let token = monitor.addObserver { status in
                guard status != .unknown else {
                    return
                }
                callbackCount.mutate { $0 += 1 }
            }
            tokens.mutate { $0.append(token) }
        }

        monitor.start()
        factory.latestEngine?.simulate(.connected)
        XCTAssertEqual(callbackCount.current, 100)

        DispatchQueue.concurrentPerform(iterations: tokens.current.count) { index in
            monitor.removeObserver(tokens.current[index])
        }

        factory.latestEngine?.simulate(.disconnected)
        XCTAssertEqual(callbackCount.current, 100)
    }

    // MARK: - NWPath Mapping

    func testNWPathStatusMapping() {
        XCTAssertEqual(NWPathMonitorEngine.map(.satisfied), .connected)
        XCTAssertEqual(NWPathMonitorEngine.map(.unsatisfied), .disconnected)
        XCTAssertEqual(NWPathMonitorEngine.map(.requiresConnection), .disconnected)
    }

    // MARK: - Integration

    func testFacadeExposesInjectedConnectivityMonitor() {
        let configuration = SwiftKitConfiguration(
            subsystem: "com.swiftkit.tests.connectivity",
            category: "ConnectivityTests"
        )
        let logger = MockLogger()
        let factory = MockNetworkPathMonitorEngineFactory()
        let monitor = NetworkConnectivityMonitor(logger: logger, engineFactory: factory)
        let container = SDKDependencyContainer(
            configuration: configuration,
            logger: logger,
            connectivityMonitor: monitor
        )

        SwiftKit.initializeForTesting(container: container)

        XCTAssertTrue(SwiftKit.shared.connectivity as AnyObject === monitor)
        XCTAssertEqual(SwiftKit.shared.connectivity.currentStatus, .unknown)
    }

    func testDefaultContainerProvidesConnectivityMonitor() {
        let container = SDKDependencyContainer(configuration: SwiftKitConfiguration())

        XCTAssertTrue(container.connectivity is NetworkConnectivityMonitor)
        XCTAssertFalse(container.connectivity.isMonitoring)
    }

    // MARK: - Helpers

    private func makeMonitor(
        queue: DispatchQueue = DispatchQueue(label: "com.swiftkit.tests.connectivity.monitor")
    ) -> (NetworkConnectivityMonitor, MockLogger, MockNetworkPathMonitorEngineFactory) {
        let logger = MockLogger()
        let factory = MockNetworkPathMonitorEngineFactory()
        let monitor = NetworkConnectivityMonitor(
            logger: logger,
            queue: queue,
            engineFactory: factory
        )
        return (monitor, logger, factory)
    }
}

// MARK: - Test Doubles

internal final class MockNetworkPathMonitorEngine: NetworkPathMonitorEngine, @unchecked Sendable {
    private let handlers = ThreadSafeBox<[@Sendable (ConnectivityStatus) -> Void]>([])
    private let startCountBox = ThreadSafeBox<Int>(0)
    private let cancelledBox = ThreadSafeBox<Bool>(false)
    private let queueBox = ThreadSafeBox<DispatchQueue?>(nil)

    internal var startCount: Int {
        startCountBox.current
    }

    internal var isCancelled: Bool {
        cancelledBox.current
    }

    internal func start(
        queue: DispatchQueue,
        onUpdate: @escaping @Sendable (ConnectivityStatus) -> Void
    ) {
        startCountBox.mutate { $0 += 1 }
        queueBox.write(queue)
        handlers.mutate { $0.append(onUpdate) }
    }

    internal func cancel() {
        cancelledBox.write(true)
    }

    internal func simulate(_ status: ConnectivityStatus) {
        for handler in handlers.current {
            handler(status)
        }
    }

    internal func simulateOnMonitorQueue(_ status: ConnectivityStatus) {
        guard let queue = queueBox.current else {
            return
        }

        let handlers = self.handlers
        queue.async {
            for handler in handlers.current {
                handler(status)
            }
        }
    }
}

internal final class MockNetworkPathMonitorEngineFactory: NetworkPathMonitorEngineFactory, @unchecked Sendable {
    private let engines = ThreadSafeBox<[MockNetworkPathMonitorEngine]>([])

    internal var createdEngines: [MockNetworkPathMonitorEngine] {
        engines.current
    }

    internal var latestEngine: MockNetworkPathMonitorEngine? {
        engines.current.last
    }

    internal func makeEngine() -> NetworkPathMonitorEngine {
        let engine = MockNetworkPathMonitorEngine()
        engines.mutate { $0.append(engine) }
        return engine
    }
}
