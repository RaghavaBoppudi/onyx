import UIKit

enum LookPreviewImages {
    static func image(for look: LookKind) -> UIImage? {
        UIImage(named: assetName(for: look))
    }

    private static func assetName(for look: LookKind) -> String {
        switch look {
        case .standard: "LookPreview.Default"
        case .mono: "LookPreview.Mono"
        case .glass: "LookPreview.Glass"
        case .doubleExposure: "LookPreview.Double"
        case .doubleExposureMono: "LookPreview.DoubleMono"
        }
    }
}
