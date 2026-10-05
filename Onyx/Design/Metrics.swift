import CoreGraphics
import SwiftUI

nonisolated enum Metrics {

    enum Viewfinder {
        static let cornerRadius: CGFloat = 22
        static let inset: CGFloat = 14
        static let portraitAspect: CGFloat = 3.0 / 4.0
        static let landscapeAspect: CGFloat = 4.0 / 3.0

        static func aspect(isLandscape: Bool) -> CGFloat {
            isLandscape ? landscapeAspect : portraitAspect
        }
    }

    enum Chrome {
        static let barHeight: CGFloat = 52
        static let symbolFont = Font.system(size: 21, weight: .regular)
        static let tapTarget: CGFloat = 48
        static let edgeInset: CGFloat = 8
        static let verticalControlsAspectThreshold: CGFloat = 1.8
        static let railVerticalInset: CGFloat = 40
        static let railHorizontalGap: CGFloat = 16
        static let railItemSpacing: CGFloat = 22
        static let statusRailWidth: CGFloat = tapTarget + edgeInset * 2
        static let railWidth: CGFloat = Shutter.outerDiameter + edgeInset * 2
        static let statusGroupHeight: CGFloat = tapTarget * 3 + railItemSpacing * 2
        static let modePillWidth: CGFloat = 104
        static let modePillHeight: CGFloat = 36
        static let modeButtonHeight: CGFloat = 44
        static let captureGroupHeight: CGFloat = tapTarget * 2 + modeButtonHeight + railItemSpacing * 2
    }

    enum Shutter {
        static let diameter: CGFloat = 74
        static let ringWidth: CGFloat = 4
        static let ringGap: CGFloat = 7
        static let pressedScale: CGFloat = 0.90
        static let outerDiameter: CGFloat = diameter + ringGap * 2
    }

    enum LensSelector {
        static let itemWidth: CGFloat = 88
        static let pillHeight: CGFloat = 48
        static let itemSpacing: CGFloat = 36
        static let tapMovementThreshold: CGFloat = 10
        static let swipeHorizontalDominance: CGFloat = 1.5
        static let bottomInset: CGFloat = 16
    }

    enum ModeCarousel {
        static let widthFraction: CGFloat = 0.74
        static let heightFraction: CGFloat = 0.63
        static let cardSpacing: CGFloat = 12
        static let cornerRadius: CGFloat = 20
        static let captionSpacing: CGFloat = 16
        static let dotsHeight: CGFloat = 7
        static let dotsGap: CGFloat = 10
        static let neighborScale: CGFloat = 0.88
        static let neighborOpacity: CGFloat = 0.5
        static let dismissDistance: CGFloat = 110
        static let dismissTravel: CGFloat = 280
    }

    enum Dual {
        static let insetScale: CGFloat = 0.30
        static let insetMarginFraction: CGFloat = 0.04
        static let insetCornerFraction: CGFloat = 0.14
        static let splitMinimumShortSide: CGFloat = 560
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
        static let lensSwitch    = Animation.snappy(duration: 0.26, extraBounce: 0.06)
        static let lensPill      = Animation.smooth(duration: 0.28)
        static let panelReveal   = Animation.smooth(duration: 0.34)
        static let modeSettle    = Animation.smooth(duration: 0.35)
        static let previewDim    = Animation.smooth(duration: 0.2)
        static let gridFade      = Animation.easeInOut(duration: 0.18)
        static let blinkIn       = Animation.easeOut(duration: Blink.inDuration)
        static let blinkOut      = Animation.easeIn(duration: Blink.outDuration)
        static let shutterPress  = Animation.smooth(duration: 0.14)
        static let thumbnailPop  = Animation.spring(response: 0.34, dampingFraction: 0.75)
        static let glyphRotation = Animation.snappy(duration: 0.30, extraBounce: 0.08)
    }
}
