// Renders the shared overlay stack for equipment-driven status change notifications.
// The view is intentionally dumb about status math and only reflects the notification service's
// current rows, handling layout, motion, and tap-to-clear behavior for the overlay.

import SwiftUI

struct EquipmentStatusNotificationView: View {
    let equipmentStatusNotificationService: EquipmentStatusNotificationService

    var body: some View {
        NotificationOverlayStack(
            items: equipmentStatusNotificationService.notifications,
            clearNotifications: clearNotifications
        ) { notification in
            NotificationBadgeRowView(
                text: notification.displayText,
                isHighlighted: false,
                accessibilityHint: "タップですべての装備ステータス通知を閉じます。",
                onTap: clearNotifications
            )
        }
    }

    private func clearNotifications() {
        equipmentStatusNotificationService.clear()
    }
}
