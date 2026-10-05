import AVFoundation
import SwiftUI

@Observable
final class AppSettings {

    var isGridVisible: Bool {
        didSet { defaults.set(isGridVisible, forKey: Keys.grid) }
    }

    var flashMode: AVCaptureDevice.FlashMode {
        didSet { defaults.set(flashMode.rawValue, forKey: Keys.flash) }
    }

    func cycleFlash() {
        flashMode = flashMode == .off ? .on : .off
    }

    private enum Keys {
        static let grid = "onyx.grid"
        static let flash = "onyx.flash"
        static let legacyAppearance = "onyx.appearance"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isGridVisible = defaults.bool(forKey: Keys.grid)
        self.flashMode = AVCaptureDevice.FlashMode(
            rawValue: defaults.integer(forKey: Keys.flash)
        ) ?? .off
        defaults.removeObject(forKey: Keys.legacyAppearance)
    }
}
