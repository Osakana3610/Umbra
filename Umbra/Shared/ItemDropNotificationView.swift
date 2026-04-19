// Renders the shared tab-level overlay of recent item drops with glass styling.

import SwiftUI

struct ItemDropNotificationView: View {
    let itemDropNotificationService: ItemDropNotificationService

    var body: some View {
        NotificationOverlayStack(
            items: itemDropNotificationService.droppedItems,
            clearNotifications: clearNotifications
        ) { item in
            ItemDropNotificationRowView(
                item: item,
                clearNotifications: clearNotifications
            )
        }
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
