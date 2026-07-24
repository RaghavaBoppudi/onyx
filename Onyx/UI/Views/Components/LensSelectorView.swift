import SwiftUI

struct LensSelectorView: View {
    let availableLenses: [Lens]
    let currentLens: Lens?
    let iconOrientation: Angle
    let onSelectLens: (Lens) -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isInteracting: Bool = false
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        let buttonWidth: CGFloat = 64
        let buttonHeight: CGFloat = 48
        let itemSpacing: CGFloat = 8
        let stride = buttonWidth + itemSpacing
        let totalCount = availableLenses.count
        let currentIndex = availableLenses.firstIndex(where: { $0 == currentLens }) ?? 0
        let baseOffset = (CGFloat(currentIndex) - (CGFloat(totalCount - 1) / 2.0)) * stride
        
        ZStack {
            HStack(spacing: itemSpacing) {
                ForEach(0..<totalCount, id: \.self) { index in
                    let lens = availableLenses[index]
                    Text(lens.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(currentIndex == index ? .white : .white.opacity(0.5))
                        .frame(width: buttonWidth, height: buttonHeight)
                        .contentShape(Rectangle())
                        .rotationEffect(iconOrientation)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.clear)
                    .liquidGlass(isBordered: false)
            )
            .scaleEffect(isInteracting ? 0.96 : 1.0)
            
            Capsule()
                .fill(Color.clear)
                .liquidGlass(isBordered: true)
                .frame(width: buttonWidth + 16, height: buttonHeight + 16)
                .offset(x: baseOffset + dragOffset)
                .scaleEffect(isInteracting ? 1.08 : 1.0)
                .shadow(color: .black.opacity(isInteracting ? 0.3 : 0.15), radius: 8, x: 0, y: 4)
                .allowsHitTesting(false)
        }
        .fixedSize()
        .animation(.spring(response: 0.3, dampingFraction: 0.65, blendDuration: 0.2), value: isDragging)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isInteracting {
                        hapticGenerator.prepare()
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
                            isInteracting = true
                        }
                    }
                    
                    if abs(value.translation.width) > 8 && !isDragging {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                            isDragging = true
                        }
                    }
                    
                    if isDragging {
                        let minDrag = -CGFloat(currentIndex) * stride
                        let maxDrag = CGFloat(totalCount - 1 - currentIndex) * stride
                        
                        let rawTranslation = value.translation.width
                        let clampedTranslation = max(minDrag, min(maxDrag, rawTranslation))
                        
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                            dragOffset = clampedTranslation
                        }
                    }
                }
                .onEnded { value in
                    let targetIndex: Int
                    
                    if value.translation.width == 0 {
                        targetIndex = Int(max(0, min(CGFloat(totalCount - 1), floor(value.startLocation.x / stride))))
                    } else {
                        let indexOffset = round(value.translation.width / stride)
                        targetIndex = Int(max(0, min(CGFloat(totalCount - 1), CGFloat(currentIndex) + indexOffset)))
                    }
                    
                    let targetLens = availableLenses[targetIndex]
                    let targetBaseOffset = (CGFloat(targetIndex) - (CGFloat(totalCount - 1) / 2.0)) * stride
                    
                    if targetLens != currentLens {
                        hapticGenerator.impactOccurred()
                        onSelectLens(targetLens)
                    }
                    
                    let currentVisualPosition = baseOffset + dragOffset
                    dragOffset = currentVisualPosition - targetBaseOffset
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        dragOffset = 0
                        isDragging = false
                        isInteracting = false
                    }
                }
        )
    }
}
