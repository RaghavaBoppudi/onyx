import AVFoundation
import SwiftUI

@MainActor
@Observable
final class AppSettings {

    var isGridVisible: Bool {
        didSet { defaults.set(isGridVisible, forKey: Keys.grid) }
    }

    var geotagsPhotos: Bool {
        didSet { defaults.set(geotagsPhotos, forKey: Keys.geotag) }
    }

    var flashMode: AVCaptureDevice.FlashMode {
        didSet { defaults.set(flashMode.rawValue, forKey: Keys.flash) }
    }

    private enum Keys {
        static let grid = "onyx.grid"
        static let flash = "onyx.flash"
        static let geotag = "onyx.geotag"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isGridVisible = defaults.bool(forKey: Keys.grid)
        self.geotagsPhotos = defaults.bool(forKey: Keys.geotag)
        self.flashMode = AVCaptureDevice.FlashMode(
            rawValue: defaults.integer(forKey: Keys.flash)
        ) ?? .off
    }
}
