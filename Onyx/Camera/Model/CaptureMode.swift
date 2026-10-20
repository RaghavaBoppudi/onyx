import AVFoundation

nonisolated enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case mono
    case doubleExposure
    case doubleExposureMono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: String(localized: "Default")
        case .mono: String(localized: "Mono")
        case .doubleExposure: String(localized: "Double")
        case .doubleExposureMono: String(localized: "Double Mono")
        }
    }

    var summary: String {
        switch self {
        case .standard: String(localized: "Our signature minimal-process look")
        case .mono: String(localized: "Our signature minimal-process look in black and white")
        case .doubleExposure: String(localized: "Two frames blended like a physical double exposure")
        case .doubleExposureMono: String(localized: "Double exposure, in black and white")
        }
    }

    func summary(for position: AVCaptureDevice.Position) -> String {
        guard position == .front else { return summary }

        return switch self {
        case .standard: String(localized: "The front camera's standard iPhone look")
        case .mono: String(localized: "The front camera's standard look in black and white")
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
