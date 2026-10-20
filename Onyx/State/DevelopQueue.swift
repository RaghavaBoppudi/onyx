import Observation

@MainActor
@Observable
final class DevelopQueue {
    let limit = 3
    private(set) var count = 0

    var isFull: Bool { count >= limit }
    var isBusy: Bool { count > 0 }

    func enqueue(_ name: String, _ work: @escaping @MainActor () async -> Void) {
        count += 1
        Task {
            await BackgroundTime.run(name) { await work() }
            count -= 1
        }
    }
}
