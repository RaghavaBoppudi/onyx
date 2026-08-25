//  Haptics.swift
//  One vocabulary for the app. Views call semantic events, never raw generators.

import UIKit

@MainActor
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

    /// Cuts the Taptic Engine's spin-up latency.
    func prepare() {
        light.prepare(); rigid.prepare(); soft.prepare()
        selectionGenerator.prepare(); notification.prepare()
    }

    func fire(_ event: Event) {
        switch event {
        case .shutterArm:    soft.impactOccurred(intensity: 0.55)
        case .shutterFire:   rigid.impactOccurred(intensity: 1.0)
        case .lensSwitch:    light.impactOccurred(intensity: 0.7)
        case .selection:     selectionGenerator.selectionChanged()
        case .toggle:        light.impactOccurred(intensity: 0.5)
        case .success:       notification.notificationOccurred(.success)
        case .failure:       notification.notificationOccurred(.error)
        }
    }
}
