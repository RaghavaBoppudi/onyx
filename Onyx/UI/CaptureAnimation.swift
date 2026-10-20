import SwiftUI

struct CaptureAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                CaptureScene(pose: .still)
            } else {
                KeyframeAnimator(initialValue: Pose(), repeating: true) { pose in
                    CaptureScene(pose: pose)
                } keyframes: { _ in
                    KeyframeTrack(\.rise) {
                        CubicKeyframe(1, duration: 0.9, startVelocity: 2 / 0.9, endVelocity: 0)
                        LinearKeyframe(1, duration: 2.0)
                        CubicKeyframe(0, duration: 0.9, startVelocity: 0, endVelocity: -2 / 0.9)
                        LinearKeyframe(0, duration: 0.6)
                    }
                    KeyframeTrack(\.press) {
                        LinearKeyframe(0, duration: 1.5)
                        CubicKeyframe(1, duration: 0.12, startVelocity: 2 / 0.12, endVelocity: 0)
                        LinearKeyframe(1, duration: 0.18)
                        CubicKeyframe(0, duration: 0.25, startVelocity: 0, endVelocity: 0)
                        LinearKeyframe(0, duration: 2.35)
                    }
                    KeyframeTrack(\.flash) {
                        LinearKeyframe(0, duration: 1.58)
                        LinearKeyframe(1, duration: 0.03)
                        CubicKeyframe(0, duration: 1.6, startVelocity: -3 / 1.6, endVelocity: 0)
                        LinearKeyframe(0, duration: 1.19)
                    }
                }
            }
        }
        .frame(width: Artboard.size.width, height: Artboard.size.height)
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct Pose {
    var rise = 0.0
    var press = 0.0
    var flash = 0.0

    static let still = Pose(rise: 1)
}

private struct CaptureScene: View {
    let pose: Pose

    var body: some View {
        ZStack {
            Palette.gray
            Color.onyxAccent.opacity(pose.flash)

            ZStack {
                Image("CaptureHand").resizable()
                Phone(press: pose.press)
                Image("CaptureThumb").resizable()
                    .rotationEffect(.degrees(-6 * pose.press), anchor: Artboard.pivot)
            }
            .offset(y: (1 - pose.rise) * Artboard.exitTravel)
        }
    }
}

private struct Phone: View {
    let press: Double

    var body: some View {
        Canvas { [press] context, size in
            context.scaleBy(x: size.width / Artboard.design.width, y: size.height / Artboard.design.height)

            context.fill(
                Path(roundedRect: Artboard.phone, cornerRadius: 54, style: .continuous),
                with: .color(.black)
            )
            context.fill(
                Path(roundedRect: Artboard.phone.insetBy(dx: 8, dy: 8), cornerRadius: 46, style: .continuous),
                with: .color(Palette.gray)
            )
            context.fill(
                Path(roundedRect: Artboard.island, cornerRadius: 11, style: .continuous),
                with: .color(.black)
            )

            let center = Artboard.shutter
            context.stroke(Path(ellipseIn: center.insetBy(dx: -6.5, dy: -6.5)), with: .color(.white), lineWidth: 5)

            let inset = 25 * 0.18 * press
            context.fill(Path(ellipseIn: center.insetBy(dx: inset, dy: inset)), with: .color(.white))
        }
    }
}

private enum Palette {
    static let gray = Color(white: 0.2)
}

private enum Artboard {
    static let size = CGSize(width: 180, height: 225)
    static let design = CGSize(width: 600, height: 750)
    static let exitTravel = size.height * 1.07

    static let phone = CGRect(x: 163.5, y: 85.5, width: 273, height: 579)
    static let island = CGRect(x: 261, y: 107.5, width: 78, height: 22)
    static let shutter = CGRect(x: 268.5, y: 566.5, width: 50, height: 50)
    static let pivot = UnitPoint(x: 449.5 / design.width, y: 697.5 / design.height)
}
