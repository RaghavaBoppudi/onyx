import SwiftUI

struct LensPicker: View {
    let model: CameraModel

    var body: some View {
        Picker("Lens", selection: selection) {
            ForEach(model.visibleLenses) { lens in
                Text(lens.label).tag(lens.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var selection: Binding<String> {
        Binding(
            get: { model.pendingLensID ?? model.selectedLens?.id ?? "" },
            set: { id in
                guard let lens = model.visibleLenses.first(where: { $0.id == id }) else { return }
                model.requestLens(lens)
            }
        )
    }
}
