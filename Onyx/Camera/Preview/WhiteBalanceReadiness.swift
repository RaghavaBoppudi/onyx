import AVFoundation
import Observation

@MainActor
@Observable
final class WhiteBalanceReadiness {

    private(set) var hasConverged = false

    @ObservationIgnored private var observation: NSKeyValueObservation?

    func bind(to lens: Lens) {
        observation = nil
        hasConverged = false

        guard let device = lens.resolveDevice() else {
            hasConverged = true
            return
        }

        if !device.isAdjustingWhiteBalance {
            hasConverged = true
            return
        }

        observation = device.observe(\.isAdjustingWhiteBalance, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor [weak self] in
                self?.hasConverged = true
                self?.observation = nil
            }
        }
    }
}
