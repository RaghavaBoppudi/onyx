import Foundation

enum ProcessingMode: String, CaseIterable, Equatable {
    case zero = "ZERO"
    case mono = "MONO"
    case auto = "AUTO"
    
    var description: String {
        switch self {
        case .zero: return "Natural color science. Zero computational enhancement."
        case .mono: return "True monochrome. Zero computational enhancement."
        case .auto: return "Standard iOS processing for complex lighting conditions."
        }
    }
}
