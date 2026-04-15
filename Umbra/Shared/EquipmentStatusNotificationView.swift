// Renders the shared overlay stack for equipment-driven status change notifications.

import SwiftUI

struct EquipmentStatusNotificationView: View {
    private static let rowSpacing: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let equipmentStatusNotificationService: EquipmentStatusNotificationService

    var body: some View {
        if !equipmentStatusNotificationService.notifications.isEmpty {
            rowsStack
                .frame(maxWidth: 320, alignment: .leading)
                .animation(rowAnimation, value: equipmentStatusNotificationService.notifications)
        }
    }

    private var rowsStack: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(equipmentStatusNotificationService.notifications) { notification in
                NotificationBadgeRowView(
                    text: notification.displayText,
                    isHighlighted: false,
                    accessibilityHint: "タップですべての装備ステータス通知を閉じます。",
                    onTap: clearNotifications
                )
                .transition(rowTransition)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: clearNotifications)
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

    private func clearNotifications() {
        equipmentStatusNotificationService.clear()
    }
}
