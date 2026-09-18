import SwiftUI

extension Binding where Value: Equatable {
    func hapticFeedback(_ event: Haptics.Event) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                guard newValue != wrappedValue else { return }
                Haptics.shared.fire(event)
                wrappedValue = newValue
            }
        )
    }
}
