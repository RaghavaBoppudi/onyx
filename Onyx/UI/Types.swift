import Foundation

enum ProcessingMode: String, CaseIterable, Equatable {
    case mono = "MONO"
    case zero = "ZERO"
    case auto = "AUTO"
    
    var description: String {
        switch self {
        case .zero: return "Natural color science.\nZero computational enhancement."
        case .mono: return "True monochrome.\nZero computational enhancement."
        case .auto: return "Standard iOS processing.\n For complex lighting conditions."
        }
    }
}

enum GridMode: Int, CaseIterable, Equatable {
    case none = 0
    case thirds = 1
    
    mutating func toggle() {
        switch self {
        case .none: self = .thirds
        case .thirds: self = .none
        }
    }
}
