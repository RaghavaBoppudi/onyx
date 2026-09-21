enum LookKind: String, CaseIterable, Identifiable, Sendable {
    case standard
    case mono
    case glass
    case doubleExposure
    case doubleExposureMono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Default"
        case .mono: "Mono"
        case .glass: "Glass"
        case .doubleExposure: "Double"
        case .doubleExposureMono: "Double Mono"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Our signature zero processed look"
        case .mono: "Our signature zero processed look \nin black and white"
        case .glass: "Nothing like shooting through glass panes"
        case .doubleExposure: "Two frames blended \nlike a physical double exposure"
        case .doubleExposureMono: "Double exposure, \nin black and white"
        }
    }

    var isDoubleExposure: Bool {
        self == .doubleExposure || self == .doubleExposureMono
    }
}
