import Foundation

enum ProcessingMode: String, CaseIterable, Equatable {
    case mono = "MONO"
    case zero = "ZERO"
    case auto = "AUTO"
    
    var description: String {
        switch self {
        case .zero: return "Unprocessed RAW color data."
        case .mono: return "Authentic monochrome. Natural sensor grain."
        case .auto: return "Standard iOS computational pipeline."
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
