// Shares the shop's item row presentation so trading and management screens stay visually aligned.

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
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("アイテム詳細")
    }
}
