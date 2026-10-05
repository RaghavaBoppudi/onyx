import SwiftUI
import UIKit

final class Haptics {
    static let shared = Haptics()

    enum Event {
        case shutterArm, shutterFire
        case lensSwitch, selection, toggle
        case success, failure
    }

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft  = UIImpactFeedbackGenerator(style: .soft)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    func prepare() {
        light.prepare(); rigid.prepare(); soft.prepare()
        selectionGenerator.prepare(); notification.prepare()
    }

    func fire(_ event: Event) {
        switch event {
        case .shutterArm:  impact(soft, intensity: 0.55)
        case .shutterFire: impact(rigid, intensity: 1.0)
        case .lensSwitch:  impact(light, intensity: 0.7)
        case .toggle:      impact(light, intensity: 0.5)
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .success: notify(.success)
        case .failure: notify(.error)
        }
    }

    private func impact(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
        notification.prepare()
    }
}

extension Binding where Value: Equatable {
    func hapticFeedback(_ event: Haptics.Event) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                guard newValue != wrappedValue else { return }
                Haptics.shared.fire(event)
                wrappedValue = newValue
            }
        )
    }
}
