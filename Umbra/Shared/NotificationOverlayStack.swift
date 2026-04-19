// Shares the compact overlay stack behavior used by transient in-app notifications.

import SwiftUI

struct NotificationOverlayStack<Items: RandomAccessCollection, RowContent: View>: View where Items.Element: Identifiable {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let items: Items
    let clearNotifications: () -> Void
    @ViewBuilder let rowContent: (Items.Element) -> RowContent

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    rowContent(item)
                        .transition(rowTransition)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: 320, alignment: .leading)
            .onTapGesture(perform: clearNotifications)
            .animation(rowAnimation, value: Array(items.map(\.id)))
        }
    }

    private var rowTransition: AnyTransition {
        if accessibilityReduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var rowAnimation: Animation {
        accessibilityReduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.25)
    }
}
