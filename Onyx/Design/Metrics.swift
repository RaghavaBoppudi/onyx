import CoreGraphics
import SwiftUI

enum Metrics {

    enum Viewfinder {
        static let cornerRadius: CGFloat = 22
        static let inset: CGFloat = 14
        static let aspect: CGFloat = 3.0 / 4.0
    }

    enum Chrome {
        static let barHeight: CGFloat = 52
        static let iconPointSize: CGFloat = 21
        static let iconWeight: Font.Weight = .regular
        static let tapTarget: CGFloat = 48
        static let edgeInset: CGFloat = 8
        static let symbolFont = Font.system(size: iconPointSize, weight: iconWeight)
    }

    enum Shutter {
        static let diameter: CGFloat = 74
        static let ringWidth: CGFloat = 4
        static let ringGap: CGFloat = 7
        static let pressedScale: CGFloat = 0.90
    }

    enum LensSelector {
        static let itemWidth: CGFloat = 88
        static let pillHeight: CGFloat = 48
        static let itemSpacing: CGFloat = 36
        static let tapMovementThreshold: CGFloat = 10
        static let swipeHorizontalDominance: CGFloat = 1.5
        static let bottomInset: CGFloat = 16
    }

    enum LookCarousel {
        static let cardSpacing: CGFloat = 36
        static let edgeMargin: CGFloat = 80
        static let verticalInset: CGFloat = 48
        static let textSpacing: CGFloat = 16
        static let captionHeight: CGFloat = 78
    }

    enum Panel {
        static let cornerRadius: CGFloat = 20
        static let padding: CGFloat = 12
    }

    enum Thumbnail {
        static let size: CGFloat = 46
        static let borderWidth: CGFloat = 1
        static let popScale: CGFloat = 0.55
    }

    enum Blink {
        static let opacity: Double = 0.42
        static let inDuration: Double = 0.055
        static let outDuration: Double = 0.13
    }

    enum Motion {
        static let lensSwitch   = Animation.snappy(duration: 0.26, extraBounce: 0.06)
        static let lensPill     = Animation.easeInOut(duration: 0.25)
        static let panelReveal  = Animation.easeInOut(duration: 0.16)
        static let gridFade     = Animation.easeInOut(duration: 0.18)
        static let blinkIn      = Animation.easeOut(duration: Blink.inDuration)
        static let blinkOut     = Animation.easeIn(duration: Blink.outDuration)
        static let shutterPress = Animation.spring(response: 0.18, dampingFraction: 0.62)
        static let thumbnailPop = Animation.spring(response: 0.34, dampingFraction: 0.62)
        static let glyphRotation = Animation.snappy(duration: 0.30, extraBounce: 0.08)
    }
}
