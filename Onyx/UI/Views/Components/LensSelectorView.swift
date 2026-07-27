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
        let stride = Theme.Layout.Lens.buttonWidth + Theme.Layout.Lens.itemSpacing
        let totalCount = availableLenses.count
        let currentIndex = availableLenses.firstIndex(where: { $0 == currentLens }) ?? 0
        let baseOffset = (CGFloat(currentIndex) - (CGFloat(totalCount - 1) / 2.0)) * stride
        
        ZStack {
            HStack(spacing: Theme.Layout.Lens.itemSpacing) {
                ForEach(0..<totalCount, id: \.self) { index in
                    let lens = availableLenses[index]
                    Text(lens.label)
                        .font(.system(size: Theme.Typography.bodyBold, weight: .bold))
                        .foregroundColor(currentIndex == index ? Theme.Color.text : Theme.Color.text.opacity(1.0))
                        .frame(width: Theme.Layout.Lens.buttonWidth, height: Theme.Layout.Lens.buttonHeight)
                        .contentShape(Rectangle())
                        .rotationEffect(iconOrientation)
                }
            }
            .padding(.horizontal, Theme.Layout.Lens.padding)
            .padding(.vertical, Theme.Layout.Lens.padding)
            .background(
                Capsule()
                    .fill(Theme.Color.glassBackground)
                    .liquidGlass(isBordered: false)
            )
            .scaleEffect(isInteracting ? 0.96 : 1.0)
            
            Capsule()
                .fill(Theme.Color.glassBackground)
                .overlay(Capsule().strokeBorder(Theme.Color.glassBorderStrong, lineWidth: Theme.Layout.borderWidth))
                .frame(width: Theme.Layout.Lens.buttonWidth + Theme.Layout.Lens.hitTestOversize, height: Theme.Layout.Lens.buttonHeight + Theme.Layout.Lens.hitTestOversize)
                .offset(x: baseOffset + dragOffset)
                .scaleEffect(x: 1.0, y: isInteracting ? 1.2 : 1.0)
                .allowsHitTesting(false)
        }
        .fixedSize()
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
                        let minDrag = -CGFloat(currentIndex) * stride
                        let maxDrag = CGFloat(totalCount - 1 - currentIndex) * stride
                        
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
                    
                    withAnimation(Theme.Physics.lensDragEnd) {
                        dragOffset = 0
                        isDragging = false
                        isInteracting = false
                    }
                }
        )
    }
}
