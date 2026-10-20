import AVFoundation
import Testing
@testable import Onyx

struct ModelTests {

    @Test func lensLabelsRoundToOneDecimal() {
        #expect(Lens.format(1) == "1x")
        #expect(Lens.format(0.5) == "0.5x")
        #expect(Lens.format(2.04) == "2x")
        #expect(Lens.format(2.96) == "3x")
    }

    @Test func onlyTheFrontUltraWideLensIsCenterStage() {
        func lens(_ type: AVCaptureDevice.DeviceType, _ position: AVCaptureDevice.Position) -> Lens {
            Lens(id: "id", deviceID: "id", deviceType: type, position: position, factor: 1, deviceZoomFactor: 1)
        }
        #expect(FrontCameraPipeline.isCenterStage(lens(.builtInUltraWideCamera, .front)))
        #expect(!FrontCameraPipeline.isCenterStage(lens(.builtInWideAngleCamera, .front)))
        #expect(!FrontCameraPipeline.isCenterStage(lens(.builtInUltraWideCamera, .back)))
    }

    @Test func captureModeFlagsAreConsistent() {
        #expect(CaptureMode.mono.isMono && !CaptureMode.mono.isDoubleExposure)
        #expect(CaptureMode.doubleExposureMono.isMono && CaptureMode.doubleExposureMono.isDoubleExposure)
        #expect(!CaptureMode.standard.isMono && !CaptureMode.standard.isDoubleExposure)
    }

    @Test func everyModeHasUniqueArtworkAndCopy() {
        let assets = Set(CaptureMode.allCases.map(\.previewAssetName))
        let names = Set(CaptureMode.allCases.map(\.displayName))
        #expect(assets.count == CaptureMode.allCases.count)
        #expect(names.count == CaptureMode.allCases.count)
    }

    @Test func interruptionsStayOnScreenUntilTheyEnd() {
        #expect(!Notice.interrupted(.inUseByAnotherApp).dismissesAutomatically)
        #expect(Notice.saveFailed.dismissesAutomatically)
        #expect(Notice.locationDenied.showsSettings)
    }

    @Test func notificationsDecodeIntoEvents() async {
        let monitor = CameraEventMonitor()
        let session = AVCaptureSession()
        monitor.watch(session)

        NotificationCenter.default.post(name: AVCaptureSession.interruptionEndedNotification, object: session)

        var iterator = monitor.events.makeAsyncIterator()
        #expect(await iterator.next() == .interruptionEnded)
    }
}
