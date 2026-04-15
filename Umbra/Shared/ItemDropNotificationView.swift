// Renders the shared tab-level overlay of recent item drops with glass styling.

import SwiftUI

struct ItemDropNotificationView: View {
    private static let rowSpacing: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let itemDropNotificationService: ItemDropNotificationService

    var body: some View {
        if !itemDropNotificationService.droppedItems.isEmpty {
            rowsStack
                .frame(maxWidth: 320, alignment: .leading)
                .animation(rowAnimation, value: itemDropNotificationService.droppedItems)
        }
    }

    private var rowsStack: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(itemDropNotificationService.droppedItems) { item in
                ItemDropNotificationRowView(
                    item: item,
                    clearNotifications: clearNotifications
                )
                .transition(rowTransition)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: clearNotifications)
    }

    private var rowTransition: AnyTransition {
        if accessibilityReduceMotion {
            // Reduced motion falls back to opacity-only changes to avoid directional movement.
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

    private func clearNotifications() {
        itemDropNotificationService.clear()
    }
}

private struct ItemDropNotificationRowView: View {
    let item: ItemDropNotificationService.DroppedItemNotification
    let clearNotifications: () -> Void

    var body: some View {
        NotificationBadgeRowView(
            text: item.displayText,
            isHighlighted: item.isSuperRare,
            accessibilityHint: "タップですべてのドロップ通知を閉じます。",
            onTap: clearNotifications
        )
    }
}
