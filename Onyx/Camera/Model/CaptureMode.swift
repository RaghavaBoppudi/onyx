import AVFoundation

nonisolated enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case mono
    case doubleExposure
    case doubleExposureMono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Default"
        case .mono: "Mono"
        case .doubleExposure: "Double"
        case .doubleExposureMono: "Double Mono"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Our signature minimal-process look"
        case .mono: "Our signature minimal-process look\nin black and white"
        case .doubleExposure: "Two frames blended\nlike a physical double exposure"
        case .doubleExposureMono: "Double exposure,\nin black and white"
        }
    }

    func summary(for position: AVCaptureDevice.Position) -> String {
        guard position == .front else { return summary }

        return switch self {
        case .standard: "The front camera's standard iPhone look"
        case .mono: "The front camera's standard look\nin black and white"
        default: summary
        }
    }

    var previewAssetName: String {
        switch self {
        case .standard: "LookPreview.Default"
        case .mono: "LookPreview.Mono"
        case .doubleExposure: "LookPreview.Double"
        case .doubleExposureMono: "LookPreview.DoubleMono"
        }
    }

    var isDoubleExposure: Bool {
        self == .doubleExposure || self == .doubleExposureMono
    }

    var isMono: Bool {
        self == .mono || self == .doubleExposureMono
    }
}
