import AVFoundation
import Observation

@Observable
final class WhiteBalanceReadiness {

    private(set) var hasConverged = false

    @ObservationIgnored private var task: Task<Void, Never>?

    func bind(to lens: Lens) {
        task?.cancel()
        hasConverged = false

        guard let device = lens.resolveDevice() else {
            hasConverged = true
            return
        }

        let updates = device.values(of: \.isAdjustingWhiteBalance)
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await updates.waitFor(false, timeout: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hasConverged = true
        }
    }
}
