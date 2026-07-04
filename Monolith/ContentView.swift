import SwiftUI
import UIKit
import Combine

// MARK: - Standardized Circular Shutter Button
struct ShutterButton: View {
    let action: () -> Void
    let isDisabled: Bool
    
    @State private var isPressed: Bool = false
    private let uiAccent = Color(red: 105/255, green: 123/255, blue: 125/255)
    
    var body: some View {
        ZStack {
            // White Rim (Shrinks instantly on touch down to touch the inner circle)
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: isPressed ? 64 : 72, height: isPressed ? 64 : 72)
            
            // Inner Body (Static)
            Circle()
                .fill(uiAccent)
                .frame(width: 58, height: 58)
        }
        .frame(width: 72, height: 72) // Prevents layout shifting
        // Uses iOS-native spring physics instead of linear easing for fluidity
        .animation(.spring(response: 0.15, dampingFraction: 0.65), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDisabled else { return }
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    guard !isDisabled else { return }
                    action()
                    // Force the shrunk state to hold for a fraction of a second before expanding
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Dynamic Text Control
struct DynamicControlIcon: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    private let uiAccent = Color(red: 105/255, green: 123/255, blue: 125/255)
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundColor(isActive ? uiAccent : Color.white)
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var isManualMode = false
    @State private var activeControl: ManualControl = .none
    @State private var isAELocked = false
    @State private var touchTimer: Timer?
    @State private var timerValue = 0
    @State private var countdownDisplay = 0
    @State private var dragLastY: CGFloat = 0
    @State private var showFloatingReadout = false
    @State private var isFlashing = false
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let uiAccent = Color(red: 105/255, green: 123/255, blue: 125/255)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                Spacer() // Pushes the viewfinder down
                
                // MARK: - Viewfinder ZStack
                ZStack(alignment: .bottom) {
                    MetalPreview(image: camera.livePreviewImage, context: camera.ciContext)
                        .blur(radius: camera.isSwitchingLens ? 30 : 0)
                        .animation(.easeInOut(duration: 0.15), value: camera.isSwitchingLens)
                    
                    GeometryReader { geo in
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        // If moving finger in manual mode, handle slider adjustments
                                        if isManualMode && activeControl != .none && activeControl != .timer {
                                            if dragLastY == 0 { dragLastY = value.location.y }
                                            let delta = Float(dragLastY - value.location.y)
                                            dragLastY = value.location.y
                                            showFloatingReadout = true
                                            camera.adjust(control: activeControl, delta: delta)
                                            return
                                        }
                                        
                                        // Start timer for Long Press detection (AE/AF Lock)
                                        if touchTimer == nil {
                                            let nx = value.location.x / geo.size.width
                                            let ny = value.location.y / geo.size.height
                                            
                                            touchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                camera.lockFocusAndExposure(at: CGPoint(x: nx, y: ny))
                                                isAELocked = true
                                                focusPoint = value.location
                                                showFocusIndicator = true
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        dragLastY = 0
                                        showFloatingReadout = false
                                        
                                        // If finger lifted before 0.5s, it's a tap. Cancel lock timer and perform standard focus.
                                        if let timer = touchTimer, timer.isValid {
                                            timer.invalidate()
                                            touchTimer = nil
                                            
                                            isAELocked = false
                                            let nx = value.location.x / geo.size.width
                                            let ny = value.location.y / geo.size.height
                                            camera.setFocusAndExposure(at: CGPoint(x: nx, y: ny), isManualMode: isManualMode)
                                            
                                            focusPoint = value.location
                                            showFocusIndicator = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showFocusIndicator = false }
                                        } else {
                                            // Finger lifted after lock achieved. Keep indicator on screen longer.
                                            touchTimer = nil
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showFocusIndicator = false }
                                        }
                                    }
                            )
                    }
                    
                    if showFocusIndicator, let point = focusPoint {
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(width: 50, height: 50)
                            .position(point)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showFocusIndicator)
                    }
                    
                    if countdownDisplay > 0 {
                        Text("\(countdownDisplay)")
                            .font(.custom("Montserrat-Regular", size: 72))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 4)
                            .position(x: UIScreen.main.bounds.width / 2, y: (UIScreen.main.bounds.width * 4/3) / 2)
                    } else if isManualMode && activeControl != .none && activeControl != .timer && showFloatingReadout {
                        Text(currentReadoutText())
                            .font(.custom("Montserrat-Regular", size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                            .position(x: UIScreen.main.bounds.width / 2, y: (UIScreen.main.bounds.width * 4/3) / 2)
                    }
                    
                    if isAELocked {
                        Text("AE/AF LOCK")
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 255/255, green: 204/255, blue: 0/255)) // Standard iOS warning yellow
                            .cornerRadius(4)
                            .position(x: UIScreen.main.bounds.width / 2, y: 40)
                    }
                    
                    Color.black.opacity(isFlashing ? 1.0 : 0)
                        .animation(.easeInOut(duration: 0.1), value: isFlashing)
                    
                    // MARK: - Manual Controls Overlay
                    if isManualMode {
                        HStack {
                            DynamicControlIcon(title: "F", isActive: activeControl == .focus) { toggleControl(.focus) }
                            Spacer()
                            DynamicControlIcon(title: shutterLabel(), isActive: activeControl == .shutter) { toggleControl(.shutter) }
                            Spacer()
                            DynamicControlIcon(title: isoLabel(), isActive: activeControl == .iso) { toggleControl(.iso) }
                            Spacer()
                            Button(action: cycleTimer) {
                                Group {
                                    if timerValue > 0 { Text("\(timerValue)s") } else { Text("timer") }
                                }
                                .font(.custom("Montserrat-Regular", size: 14))
                                .foregroundColor(activeControl == .timer || timerValue > 0 ? uiAccent : Color.white)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                
                Spacer() // Centers the Lens Switcher
                
                // MARK: - Lens Switcher
                HStack(spacing: 24) {
                    ForEach(camera.availableLenses, id: \.type) { lens in
                        Button(action: { camera.selectLens(lens) }) {
                            Text(shortLensLabel(lens.label))
                                .font(.custom("Montserrat-Regular", size: 14))
                                .foregroundColor(camera.currentLens == lens ? uiAccent : Color.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer() // Centers the Lens Switcher
                
                // MARK: - Auto/Manual & Shutter Row
                HStack(spacing: 0) {
                    Button(isManualMode ? "manual" : "auto") {
                        withAnimation(.easeInOut(duration: 0.25)) { isManualMode.toggle() }
                        activeControl = .none
                        if !isManualMode { camera.resetToAuto(control: .focus); camera.resetToAuto(control: .iso) }
                        hapticGenerator.impactOccurred()
                    }
                    .font(.custom("Montserrat-Regular", size: 14))
                    .foregroundColor(isManualMode ? uiAccent : Color.white)
                    .frame(maxWidth: .infinity)
                    
                    // Controlled by custom gesture logic inside ShutterButton
                    ShutterButton(action: initiateCapture, isDisabled: countdownDisplay > 0)
                    
                    Button(camera.isDoubleExposureMode ? "double" : "single") {
                        camera.isDoubleExposureMode.toggle()
                        hapticGenerator.impactOccurred()
                    }
                    .font(.custom("Montserrat-Regular", size: 14))
                    .foregroundColor(camera.isDoubleExposureMode ? uiAccent : Color.white)
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Helpers
    private func shortLensLabel(_ label: String) -> String {
        switch label {
        case "ultra-wide": return "0.5x"
        case "wide": return "1x"
        case "tele": return "4x"
        default: return label
        }
    }
    
    private func shutterLabel() -> String {
        if camera.isShutterAuto { return "S" }
        let s = camera.currentShutter
        return s >= 1.0 ? String(format: "%.1fs", s) : "1/\(Int(1.0 / s))"
    }
    
    private func isoLabel() -> String {
        camera.isISOAuto ? "ISO" : "ISO \(Int(camera.currentISO))"
    }
    
    private func currentReadoutText() -> String {
        switch activeControl {
        case .focus: return String(format: "F: %.2f", camera.currentFocus)
        case .iso: return "ISO \(Int(camera.currentISO))"
        case .shutter: return shutterLabel()
        default: return ""
        }
    }
    
    private func toggleControl(_ target: ManualControl) {
        if activeControl == target { activeControl = .none; camera.resetToAuto(control: target) }
        else { activeControl = target }
    }
    
    private func cycleTimer() {
        timerValue = timerValue == 0 ? 3 : (timerValue == 3 ? 10 : 0)
        activeControl = timerValue > 0 ? .timer : .none
    }
    
    private func initiateCapture() {
        hapticGenerator.impactOccurred()
        if timerValue > 0 {
            countdownDisplay = timerValue
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                countdownDisplay -= 1
                if countdownDisplay <= 0 { timer.invalidate(); executeCapture() }
            }
        } else { executeCapture() }
    }
    
    private func executeCapture() {
        isFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFlashing = false }
        camera.capturePhoto()
    }
}
