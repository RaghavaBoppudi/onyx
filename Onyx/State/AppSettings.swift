//  AppSettings.swift
//  The complete set of user-facing options: grid, flash, appearance. Nothing about
//  capture or the look is configurable — that is the product.

import AVFoundation
import SwiftUI

@MainActor
@Observable
final class AppSettings {

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var isGridVisible: Bool {
        didSet { defaults.set(isGridVisible, forKey: Keys.grid) }
    }

    var flashMode: AVCaptureDevice.FlashMode {
        didSet { defaults.set(flashMode.rawValue, forKey: Keys.flash) }
    }

    /// off ↔ on. No auto — an app whose whole premise is "no surprises" can't
    /// have the flash making its own call about whether to fire.
    func cycleFlash() {
        flashMode = flashMode == .off ? .on : .off
    }

    private enum Keys {
        static let appearance = "onyx.appearance"
        static let grid  = "onyx.grid"
        static let flash = "onyx.flash"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = AppearanceMode(
            rawValue: defaults.string(forKey: Keys.appearance) ?? ""
        ) ?? .system
        self.isGridVisible = defaults.bool(forKey: Keys.grid)
        self.flashMode = AVCaptureDevice.FlashMode(
            rawValue: defaults.integer(forKey: Keys.flash)
        ) ?? .off
    }
}
