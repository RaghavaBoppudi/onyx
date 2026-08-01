import UIKit

final class HapticManager {
    static let shared = HapticManager()
    
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private init() {
        // Pre-warm the haptic engine off the critical path
        DispatchQueue.global(qos: .userInitiated).async {
            self.lightGenerator.prepare()
            self.mediumGenerator.prepare()
            self.selectionGenerator.prepare()
        }
    }
    
    func playLight() {
        DispatchQueue.main.async {
            self.lightGenerator.impactOccurred()
        }
    }
    
    func playMedium() {
        DispatchQueue.main.async {
            self.mediumGenerator.impactOccurred()
        }
    }
    
    func playSelection() {
        DispatchQueue.main.async {
            self.selectionGenerator.selectionChanged()
        }
    }
}
