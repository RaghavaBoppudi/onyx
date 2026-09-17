enum LookKind: String, CaseIterable, Identifiable, Sendable {
    case standard
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Default"
        case .mono: "Mono"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Onyx's signature warm color look"
        case .mono: "Black and white, baked into the RAW decode"
        }
    }
}
