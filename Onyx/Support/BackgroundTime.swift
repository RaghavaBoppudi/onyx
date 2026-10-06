import UIKit
import Synchronization
import os

nonisolated private final class BackgroundTaskToken: Sendable {
    private let storage = Mutex(UIBackgroundTaskIdentifier.invalid)

    func set(_ identifier: UIBackgroundTaskIdentifier) {
        storage.withLock { $0 = identifier }
    }

    func take() -> UIBackgroundTaskIdentifier {
        storage.withLock { identifier in
            let taken = identifier
            identifier = .invalid
            return taken
        }
    }
}

@MainActor
enum BackgroundTime {

    static func run(_ name: String, _ body: () async -> Void) async {
        let token = BackgroundTaskToken()
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            Log.capture.warning("Background time expired for \(name, privacy: .public)")
            MainActor.assumeIsolated { BackgroundTime.end(token) }
        }
        token.set(identifier)
        defer { end(token) }
        await body()
    }

    private static func end(_ token: BackgroundTaskToken) {
        let identifier = token.take()
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
