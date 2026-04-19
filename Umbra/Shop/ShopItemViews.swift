// Shares the shop's basic item-row presentation so trading, management, and enhancement screens stay
// visually aligned.
// Keeping the summary and detail affordance here avoids each shop flow reimplementing spacing,
// emphasis rules, and accessibility labels for the same item identity.

import SwiftUI

struct ShopItemSummaryContent: View {
    let item: EquipmentCachedItem
    let detailText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName)
                .font(item.isSuperRare ? .body.weight(.semibold) : .body)
                .lineLimit(2)

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct ShopItemDetailButton: View {
    let itemID: CompositeItemID
    let onShowDetail: (CompositeItemID) -> Void

    var body: some View {
        Button {
            onShowDetail(itemID)
        } label: {
            // A compact trailing affordance is reused across many dense list rows, so keep the tap
            // target explicit even though the visual is icon-only.
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("アイテム詳細")
    }
}
