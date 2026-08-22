import UIKit

final class HapticManager {
    static let shared = HapticManager()
    
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private init() {
        self.lightGenerator.prepare()
        self.mediumGenerator.prepare()
        self.heavyGenerator.prepare()
        self.selectionGenerator.prepare()
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
    
    func playHeavy() {
        DispatchQueue.main.async {
            self.heavyGenerator.impactOccurred()
        }
    }
    
    func playSelection() {
        DispatchQueue.main.async {
            self.selectionGenerator.selectionChanged()
        }
    }
}
