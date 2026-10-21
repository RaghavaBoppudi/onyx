import SwiftUI

struct CaptureAnimation: View {
    enum Device {
        case phone, duo, tablet

        init(_ screen: ScreenClass) {
            switch screen {
            case .standard: self = .phone
            case .statusRail: self = .duo
            case .rail: self = .tablet
            }
        }

        var canvas: CGSize { self == .tablet ? CGSize(width: 840, height: 680) : CGSize(width: 600, height: 750) }
        var cropTop: CGFloat { self == .duo ? 270 : 0 }
        var scale: CGFloat { self == .tablet ? 0.72 : 1 }
        var corner: CGFloat { self == .tablet ? 40 : 54 }
        var bezel: CGFloat { self == .tablet ? 12 : 8 }

        var chassis: CGRect {
            switch self {
            case .phone: CGRect(x: 163.5, y: 85.5, width: 273, height: 579)
            case .duo: CGRect(x: 163.5, y: 300.5, width: 273, height: 364)
            case .tablet: CGRect(x: 200, y: 30, width: 440, height: 330)
            }
        }

        var shutter: CGPoint {
            self == .tablet ? CGPoint(x: chassis.maxX - 50, y: chassis.midY) : CGPoint(x: 293.5, y: 591.5)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let device: Device

    var body: some View {
        let visible = CGSize(width: device.canvas.width, height: device.canvas.height - device.cropTop)

        Group {
            if reduceMotion {
                Stage(device: device, pose: .still)
            } else {
                KeyframeAnimator(initialValue: Pose(), repeating: true) { pose in
                    Stage(device: device, pose: pose)
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
        .frame(width: device.canvas.width, height: device.canvas.height)
        .offset(y: -device.cropTop)
        .frame(width: visible.width, height: visible.height, alignment: .top)
        .scaleEffect(0.3, anchor: .topLeading)
        .frame(width: visible.width * 0.3, height: visible.height * 0.3, alignment: .topLeading)
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

private struct Stage: View {
    let device: CaptureAnimation.Device
    let pose: Pose

    private var isTablet: Bool { device == .tablet }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.2)
            Color.onyxAccent.opacity(pose.flash)

            ZStack(alignment: .topLeading) {
                Image(isTablet ? "CaptureTabletHand" : "CaptureHand")
                if isTablet { Image("CaptureTabletHand").scaleEffect(x: -1) }
                Chassis(device: device, press: pose.press)
                if isTablet { thumb(angle: 0).scaleEffect(x: -1) }
                thumb(angle: -6 * pose.press)
            }
            .offset(y: (1 - pose.rise) * device.canvas.height)
        }
    }

    private func thumb(angle: Double) -> some View {
        Image("CaptureThumb")
            .rotationEffect(.degrees(angle), anchor: UnitPoint(x: 449.5 / 600, y: 697.5 / 750))
            .scaleEffect(device.scale, anchor: UnitPoint(x: 293.5 / 600, y: 591.5 / 750))
            .offset(x: device.shutter.x - 293.5, y: device.shutter.y - 591.5)
            .frame(width: device.canvas.width, height: device.canvas.height, alignment: .topLeading)
    }
}

private struct Chassis: View {
    let device: CaptureAnimation.Device
    let press: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: device.corner, style: .continuous)
                .fill(.black)
                .overlay {
                    RoundedRectangle(cornerRadius: device.corner - device.bezel, style: .continuous)
                        .fill(Color(white: 0.2))
                        .padding(device.bezel)
                }
                .frame(width: device.chassis.width, height: device.chassis.height)
                .offset(x: device.chassis.minX, y: device.chassis.minY)

            ZStack {
                Circle().stroke(.white, lineWidth: 5).frame(width: 63, height: 63)
                Circle().fill(.white).frame(width: 50, height: 50).scaleEffect(1 - 0.18 * press)
            }
            .scaleEffect(device.scale)
            .position(device.shutter)
        }
    }
}
