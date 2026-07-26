import Foundation

enum ProcessingMode: String, CaseIterable, Equatable {
    case zero = "ZERO"
    case mono = "MONO"
    case auto = "AUTO"
    
    var description: String {
        switch self {
        case .zero: return "Natural color science.\nZero computational enhancement."
        case .mono: return "True monochrome.\nZero computational enhancement."
        case .auto: return "Standard iOS processing.\n For complex lighting conditions."
        }
    }
}
