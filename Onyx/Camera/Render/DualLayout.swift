import CoreGraphics

nonisolated enum DualLayoutStyle: Sendable, Equatable {
    case pictureInPicture
    case split

    static func resolve(for size: CGSize) -> DualLayoutStyle {
        min(size.width, size.height) >= Metrics.Dual.splitMinimumShortSide ? .split : .pictureInPicture
    }
}

nonisolated struct DualLayoutGeometry {
    let rear: CGRect
    let front: CGRect
    let frontCornerRadius: CGFloat

    init(size: CGSize, style: DualLayoutStyle) {
        switch style {
        case .pictureInPicture:
            let insetSize = CGSize(
                width: size.width * Metrics.Dual.insetScale,
                height: size.height * Metrics.Dual.insetScale
            )
            let margin = min(size.width, size.height) * Metrics.Dual.insetMarginFraction

            rear = CGRect(origin: .zero, size: size)
            front = CGRect(
                x: size.width - insetSize.width - margin,
                y: margin,
                width: insetSize.width,
                height: insetSize.height
            )
            frontCornerRadius = min(insetSize.width, insetSize.height) * Metrics.Dual.insetCornerFraction

        case .split:
            let isSideBySide = size.width > size.height
            let half = isSideBySide
                ? CGSize(width: size.width / 2, height: size.height)
                : CGSize(width: size.width, height: size.height / 2)

            front = CGRect(origin: .zero, size: half)
            rear = CGRect(
                x: isSideBySide ? half.width : 0,
                y: isSideBySide ? 0 : half.height,
                width: half.width,
                height: half.height
            )
            frontCornerRadius = 0
        }
    }
}

nonisolated extension CGRect {
    func flipped(inCanvasHeight canvasHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: canvasHeight - maxY, width: width, height: height)
    }
}
