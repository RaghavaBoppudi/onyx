import SwiftUI

enum Theme {
    enum Color {
        static let accent = SwiftUI.Color(red: 1.0, green: 0.4, blue: 0.0)
        static let background = SwiftUI.Color(UIColor.systemBackground)
        static let text = SwiftUI.Color(UIColor.label)
        
        static let glassBackground = SwiftUI.Color.black.opacity(0.05)
        static let glassBorderSubtle = SwiftUI.Color.black.opacity(0.1)
        static let glassBorderStrong = SwiftUI.Color.black.opacity(0.3)
        
        enum Shutter {
            static let core = accent
            static let ring = Theme.Color.text.opacity(0.2)
            static let pressed = Theme.Color.text
        }
    }
    
    enum Layout {
        static let aspectRatio: CGFloat = 4.0 / 3.0
        
        static let controlWidth: CGFloat = 64
        static let controlHeight: CGFloat = 36
        static let cornerRadius: CGFloat = 24
        static let borderWidth: CGFloat = 0.5
        
        static let paddingSmall: CGFloat = 8
        static let paddingStandard: CGFloat = 16
        static let paddingLarge: CGFloat = 32
        
        static let qrBottomPadding: CGFloat = 80
        static let viewfinderInset: CGFloat = 12
        static let lensSelectorOffset: CGFloat = 24
        static let focusReticleSize: CGFloat = 72

        enum Lens {
            static let buttonWidth: CGFloat = 72
            static let buttonHeight: CGFloat = 36
            static let padding: CGFloat = 6
            static let itemSpacing: CGFloat = 24
            static let dragThreshold: CGFloat = 8
            static let hitTestOversize: CGFloat = 12
        }
        
        enum Shutter {
            static let baseSize: CGFloat = 76
            static let coreSize: CGFloat = 64
            static let ringWidth: CGFloat = 4
        }
    }
    
    enum Typography {
        static let iconStandard: CGFloat = 16
        static let iconLarge: CGFloat = 20
        static let bodySmallBold: CGFloat = 13
        static let bodySemibold: CGFloat = 14
        static let bodyBold: CGFloat = 15
    }
    
    enum Physics {
        static let menuTransition = Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let lensTap = Animation.spring(response: 0.2, dampingFraction: 0.65)
        static let lensDragStart = Animation.spring(response: 0.25, dampingFraction: 0.65)
        static let lensDragActive = Animation.interactiveSpring(response: 0.15, dampingFraction: 0.8)
        static let lensDragEnd = Animation.spring(response: 0.4, dampingFraction: 0.6)
        
        static let shutterPress = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.6)
    }
}
