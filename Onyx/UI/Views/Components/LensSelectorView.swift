import SwiftUI

struct LensSelectorView: View {
    let availableLenses: [Lens]
    let currentLens: Lens?
    let iconOrientation: Angle
    let onSelectLens: (Lens) -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isInteracting: Bool = false
    
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    var body: some View {
        let stride = Theme.Layout.Lens.buttonWidth + Theme.Layout.Lens.itemSpacing
        let totalCount = availableLenses.count
        let currentIndex = availableLenses.firstIndex(where: { $0 == currentLens }) ?? 0
        
        let centeringOffset = (CGFloat(totalCount - 1) / 2.0 - CGFloat(currentIndex)) * stride
        let currentVisualPosition = centeringOffset + dragOffset
        
        ZStack {
            // Translating Dial Content (Clipped Viewport)
            HStack(spacing: Theme.Layout.Lens.itemSpacing) {
                ForEach(0..<totalCount, id: \.self) { index in
                    let lens = availableLenses[index]
                    let isCenter = currentIndex == index
                    
                    Text(lens.label)
                        .font(.system(size: Theme.Typography.bodyBold, weight: .bold))
                        .foregroundColor(isCenter ? Theme.Color.accent : Color.white)
                        .opacity(isCenter ? 1.0 : 0.4)
                        .shadow(color: Color.black.opacity(0.8), radius: 2, x: 0, y: 1)
                        .frame(width: Theme.Layout.Lens.buttonWidth, height: Theme.Layout.Lens.buttonHeight)
                        .contentShape(Rectangle())
                        .rotationEffect(iconOrientation)
                        .animation(.easeOut(duration: 0.2), value: currentIndex)
                }
            }
            .offset(x: currentVisualPosition)
            .frame(width: stride * 3, height: Theme.Layout.Lens.buttonHeight + Theme.Layout.Lens.hitTestOversize)
            .clipped()
            .zIndex(2)
            
            // Static Active Indicator (Unclipped, free to scale)
            Capsule()
                .fill(Theme.Color.glassBackground)
                .liquidGlass(isBordered: false)
                .overlay(Capsule().strokeBorder(Theme.Color.glassBorderStrong, lineWidth: Theme.Layout.borderWidth))
                .frame(
                    width: Theme.Layout.Lens.buttonWidth + Theme.Layout.Lens.hitTestOversize,
                    height: Theme.Layout.Lens.buttonHeight + Theme.Layout.Lens.hitTestOversize
                )
                .scaleEffect(x: 1.0, y: isInteracting ? 1.2 : 1.0)
                .zIndex(1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .animation(Theme.Physics.menuTransition, value: isDragging)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isInteracting {
                        hapticGenerator.prepare()
                        withAnimation(Theme.Physics.lensTap) {
                            isInteracting = true
                        }
                    }
                    
                    if abs(value.translation.width) > Theme.Layout.Lens.dragThreshold && !isDragging {
                        withAnimation(Theme.Physics.lensDragStart) {
                            isDragging = true
                        }
                    }
                    
                    if isDragging {
                        let minDrag = -CGFloat(totalCount - 1 - currentIndex) * stride
                        let maxDrag = CGFloat(currentIndex) * stride
                        
                        let rawTranslation = value.translation.width
                        let clampedTranslation = max(minDrag, min(maxDrag, rawTranslation))
                        
                        withAnimation(Theme.Physics.lensDragActive) {
                            dragOffset = clampedTranslation
                        }
                    }
                }
                .onEnded { value in
                    let targetIndex: Int
                    
                    if value.translation.width == 0 {
                        let tapOffset = value.startLocation.x - (stride * 1.5)
                        let indexOffset = round(tapOffset / stride)
                        targetIndex = Int(max(0, min(CGFloat(totalCount - 1), CGFloat(currentIndex) + indexOffset)))
                    } else {
                        let indexOffset = round(-value.translation.width / stride)
                        targetIndex = Int(max(0, min(CGFloat(totalCount - 1), CGFloat(currentIndex) + indexOffset)))
                    }
                    
                    let targetLens = availableLenses[targetIndex]
                    
                    if targetLens != currentLens {
                        hapticGenerator.selectionChanged()
                        onSelectLens(targetLens)
                    }
                    
                    let targetCenteringOffset = (CGFloat(totalCount - 1) / 2.0 - CGFloat(targetIndex)) * stride
                    dragOffset = currentVisualPosition - targetCenteringOffset
                    
                    withAnimation(Theme.Physics.lensDragEnd) {
                        dragOffset = 0
                        isDragging = false
                        isInteracting = false
                    }
                }
        )
    }
}
