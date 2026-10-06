import SwiftUI

nonisolated struct FeedbackEvent: Equatable, Sendable {
    enum Kind: Sendable {
        case shutterFire
        case lensSwitch
        case selection
        case tap
        case success
        case failure
    }

    let serial: Int
    let kind: Kind

    static let none = FeedbackEvent(serial: 0, kind: .selection)
}

extension FeedbackEvent.Kind {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .shutterFire: .impact(flexibility: .rigid, intensity: 1)
        case .lensSwitch: .impact(flexibility: .soft, intensity: 0.7)
        case .selection: .selection
        case .tap: .impact(flexibility: .soft, intensity: 0.5)
        case .success: .success
        case .failure: .error
        }
    }
}
