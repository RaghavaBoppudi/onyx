//  Metrics.swift
//  Every layout constant and motion curve. No view declares its own.

import CoreGraphics
import SwiftUI

enum Metrics {

    enum Viewfinder {
        static let cornerRadius: CGFloat = 22
        static let inset: CGFloat = 14
        /// 4:3 is sensor-native on every iPhone rear camera.
        static let aspect: CGFloat = 3.0 / 4.0
    }

    /// One icon size, one tap target, one bar height, for every glyph in the app.
    ///
    /// Both bars are three equal-width columns with the glyph **centred** in its
    /// column. That puts the outer controls at one sixth and five sixths of the
    /// width — visually halfway between the screen edge and the shutter — rather
    /// than shoved against the margins. It also lines the top row up with the
    /// bottom row for free.
    enum Chrome {
        static let barHeight: CGFloat = 52
        static let iconPointSize: CGFloat = 21
        static let iconWeight: Font.Weight = .regular
        static let tapTarget: CGFloat = 48
        /// Safety margin only; the column layout does the real spacing.
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
        static let dotSize: CGFloat = 5
        static let dotSpacing: CGFloat = 9
        static let itemSpacing: CGFloat = 36
        /// Every lens occupies the same width regardless of label length. Without
        /// this, "0.5x" is visibly wider than "2x" or "4x", and SwiftUI centers the
        /// whole HStack rather than any particular glyph — so the widest label on
        /// one side drags the apparent centre away from whatever sits in the middle.
        /// A fixed slot makes the layout symmetric by construction: the true middle
        /// lens lands exactly at centre with three lenses, two lenses split evenly
        /// around it, and one lens is trivially centred — no count-based branching
        /// anywhere in the view.
        static let itemWidth: CGFloat = 48
        static let verticalHitSlop: CGFloat = 12
    }

    enum Panel {
        static let cornerRadius: CGFloat = 20
        static let segmentHeight: CGFloat = 44
        static let padding: CGFloat = 12
    }

    enum Thumbnail {
        static let size: CGFloat = 46
        static let borderWidth: CGFloat = 1
        /// Scale the new thumbnail springs up from.
        static let popScale: CGFloat = 0.55
    }

    /// A camera blinks; it does not flash the room white. The overlay darkens
    /// briefly, the way a real shutter closing does — legible as confirmation,
    /// invisible as an interruption.
    enum Blink {
        static let opacity: Double = 0.42
        static let inDuration: Double = 0.055
        static let outDuration: Double = 0.13
    }

    enum Motion {
        static let lensSwitch   = Animation.snappy(duration: 0.26, extraBounce: 0.06)
        /// Quick cross-fade. The panel appears where it is, it does not travel.
        static let panelReveal  = Animation.easeInOut(duration: 0.16)
        static let gridFade     = Animation.easeInOut(duration: 0.18)
        static let blinkIn      = Animation.easeOut(duration: Blink.inDuration)
        static let blinkOut     = Animation.easeIn(duration: Blink.outDuration)
        static let shutterPress = Animation.spring(response: 0.18, dampingFraction: 0.62)
        static let thumbnailPop = Animation.spring(response: 0.34, dampingFraction: 0.62)
        static let glyphRotation = Animation.snappy(duration: 0.30, extraBounce: 0.08)
    }
}
