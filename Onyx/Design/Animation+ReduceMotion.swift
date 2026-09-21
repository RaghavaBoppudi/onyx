import SwiftUI
import UIKit

extension Animation {
    static func reduceMotionAware(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }
}
