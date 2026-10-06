import Foundation

nonisolated enum CaptureProfile: String, CaseIterable, Identifiable, Sendable {
    case standard
    case journalist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .journalist: "Journalist"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "camera"
        case .journalist: "newspaper"
        }
    }
}
