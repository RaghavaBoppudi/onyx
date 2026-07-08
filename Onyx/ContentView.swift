import SwiftUI
import AVFoundation

// MARK: - Global UI Theme
struct Theme {
    static let accent = Color(red: 105/255, green: 123/255, blue: 125/255)
}

struct ShutterButton: View {
    let action: () -> Void
    let isDisabled: Bool
    
    @State private var isPressed: Bool = false
    
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: isPressed ? 80 : 88, height: isPressed ? 80 : 88)
            Circle()
                .fill(Theme.accent)
                .frame(width: 72, height: 72)
        }
        .frame(width: 88, height: 88)
        .animation(.spring(response: 0.15, dampingFraction: 0.65), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in guard !isDisabled else { return }; if !isPressed { isPressed = true } }
                .onEnded { _ in
                    guard !isDisabled else { return }
                    action()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isPressed = false }
                }
        )
    }
}

struct DynamicControlIcon: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(isActive ? Theme.accent : Color.white)
                .frame(maxWidth: .infinity)
        }
    }
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var isManualMode = false
    @State private var activeControl: ManualControl = .none
    @State private var isAELocked = false
    @State private var touchTimer: Timer?
    @State private var timerValue = 0
    @State private var countdownDisplay = 0
    @State private var showFloatingReadout = false
    @State private var isFlashing = false
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    
    @State private var dragLastY: CGFloat = 0
    @State private var dragAccumulator: CGFloat = 0
    @State private var startIndex: Int = 0
    private let swipeSensitivity: CGFloat = 20.0
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // This Spacer absorbs all available top space, pushing everything down
                Spacer()
                
                // Fixed Edge-to-Edge Viewfinder
                ZStack(alignment: .bottom) {
                    MetalPreview(camera: camera)
                        .blur(radius: camera.isSwitchingLens ? 30 : 0)
                        .animation(.easeInOut(duration: 0.15), value: camera.isSwitchingLens)
                    
                    GeometryReader { geo in
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if isManualMode && activeControl != .none && activeControl != .timer {
                                            showFloatingReadout = true
                                            
                                            if activeControl == .focus {
                                                if dragLastY == 0 { dragLastY = value.location.y }
                                                let delta = Float(dragLastY - value.location.y)
                                                dragLastY = value.location.y
                                                camera.setFocus(camera.currentFocus + delta * 0.005)
                                                return
                                            }
                                            
                                            if dragAccumulator == 0 {
                                                if activeControl == .iso {
                                                    startIndex = findClosestIndex(for: camera.currentISO, in: camera.standardISOs)
                                                } else if activeControl == .shutter {
                                                    startIndex = findClosestIndex(for: Float(camera.currentShutter), in: camera.standardShutterSpeeds.map { Float($0) })
                                                }
                                            }
                                            
                                            dragAccumulator = -value.translation.height
                                            let steps = Int(dragAccumulator / swipeSensitivity)
                                            
                                            if activeControl == .iso {
                                                var targetIndex = startIndex + steps
                                                targetIndex = max(0, min(targetIndex, camera.standardISOs.count - 1))
                                                let newISO = camera.standardISOs[targetIndex]
                                                if newISO != camera.currentISO { camera.setISO(newISO) }
                                            } else if activeControl == .shutter {
                                                var targetIndex = startIndex + steps
                                                targetIndex = max(0, min(targetIndex, camera.standardShutterSpeeds.count - 1))
                                                let newShutter = camera.standardShutterSpeeds[targetIndex]
                                                if newShutter != camera.currentShutter { camera.setShutter(newShutter) }
                                            }
                                            return
                                        }
                                        
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
                                        dragAccumulator = 0
                                        showFloatingReadout = false
                                        
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
                            .font(.system(size: 72, weight: .regular))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 4)
                            .position(x: UIScreen.main.bounds.width / 2, y: (UIScreen.main.bounds.width * 4/3) / 2)
                    } else if isManualMode && activeControl != .none && activeControl != .timer && showFloatingReadout {
                        Text(currentReadoutText())
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                            .position(x: UIScreen.main.bounds.width / 2, y: (UIScreen.main.bounds.width * 4/3) / 2)
                    }
                    
                    if isAELocked {
                        Text("AE/AF LOCK")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 255/255, green: 204/255, blue: 0/255))
                            .cornerRadius(4)
                            .position(x: UIScreen.main.bounds.width / 2, y: 40)
                    }
                    
                    Color.black.opacity(isFlashing ? 1.0 : 0)
                        .animation(.easeInOut(duration: 0.1), value: isFlashing)
                    
                    if isManualMode {
                        HStack(spacing: 0) {
                            DynamicControlIcon(title: "F", isActive: activeControl == .focus) { toggleControl(.focus) }
                            DynamicControlIcon(title: shutterLabel(), isActive: activeControl == .shutter) { toggleControl(.shutter) }
                            DynamicControlIcon(title: isoLabel(), isActive: activeControl == .iso) { toggleControl(.iso) }
                            
                            Button(action: cycleTimer) {
                                Image(systemName: timerValue == 0 ? "timer" : (timerValue == 3 ? "3.circle" : "10.circle"))
                                    .font(.system(size: 18))
                                    .foregroundColor(activeControl == .timer || timerValue > 0 ? Theme.accent : Color.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.black.opacity(0.4))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 4 / 3)
                .clipped()
                
                // Bottom Control Cluster: Fixed Height for Absolute Alignment
                VStack(spacing: 0) {
                    
                    // Fixed height container for lens selectors
                    HStack(spacing: 24) {
                        ForEach(camera.availableLenses, id: \.type) { lens in
                            Button(action: { camera.selectLens(lens) }) {
                                Text(lens.label)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(camera.currentLens == lens ? Theme.accent : Color.white)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: 100)
                    
                    // Shutter Row: Anchored to bottom
                    HStack(spacing: 0) {
                        // Auto/Manual Toggle
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) { isManualMode.toggle() }
                            activeControl = .none
                            if !isManualMode {
                                camera.resetToAuto(control: .focus)
                                camera.resetToAuto(control: .iso)
                            }
                            hapticGenerator.impactOccurred()
                        }) {
                            Text(isManualMode ? "manual" : "auto")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Shutter Button
                        ShutterButton(action: initiateCapture, isDisabled: countdownDisplay > 0)
                        
                        // Format Toggle
                        Button(action: {
                            hapticGenerator.impactOccurred()
                            camera.isColorMode.toggle()
                        }) {
                            Text(camera.isColorMode ? "color" : "mono")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 100)
                }
            }
        }
        .onDisappear {
            if camera.session.isRunning {
                DispatchQueue.global(qos: .background).async {
                    camera.session.stopRunning()
                }
            }
        }
    }
    
    private func findClosestIndex(for value: Float, in array: [Float]) -> Int {
        var closestIndex = 0
        var minDifference = Float.infinity
        for (index, stop) in array.enumerated() {
            let diff = abs(value - stop)
            if diff < minDifference {
                minDifference = diff
                closestIndex = index
            }
        }
        return closestIndex
    }
    
    private func shutterLabel() -> String {
        if camera.isShutterAuto { return "S" }
        let s = camera.currentShutter
        return s >= 1.0 ? String(format: "%.1fs", s) : "1/\(Int(1.0 / s))"
    }
    
    private func isoLabel() -> String { camera.isISOAuto ? "ISO" : "ISO \(Int(camera.currentISO))" }
    
    private func currentReadoutText() -> String {
        switch activeControl {
        case .focus: return String(format: "F: %.2f", camera.currentFocus)
        case .iso: return "ISO \(Int(camera.currentISO))"
        case .shutter: return shutterLabel()
        default: return ""
        }
    }
    
    private func toggleControl(_ target: ManualControl) {
        if activeControl == target { activeControl = .none; camera.resetToAuto(control: target) } else { activeControl = target }
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
