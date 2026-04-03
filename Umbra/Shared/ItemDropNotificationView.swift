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
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding = 10
    @ScaledMetric(relativeTo: .subheadline) private var verticalPadding = 6

    let item: ItemDropNotificationService.DroppedItemNotification
    let clearNotifications: () -> Void

    var body: some View {
        Button(action: clearNotifications) {
            Text(item.displayText)
                .font(.subheadline)
                .foregroundStyle(item.isSuperRare ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .modifier(ItemDropNotificationChrome(isSuperRare: item.isSuperRare))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayText)
        .accessibilityHint("タップですべてのドロップ通知を閉じます。")
    }
}

private struct ItemDropNotificationChrome: ViewModifier {
    let isSuperRare: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive())
        } else {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

            // Earlier systems approximate the same badge treatment with material plus a light tint.
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape
                        .fill(isSuperRare ? Color.red.opacity(0.18) : Color.black.opacity(0.05))
                }
        }
    }
}
