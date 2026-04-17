// Builds and renders enhancement item rows that combine owned stacks with equipped usage across characters.

import SwiftUI

struct ShopEnhancementSection: Identifiable {
    let key: EquipmentSectionKey
    let rows: [ShopEnhancementRow]

    var id: EquipmentSectionKey { key }
}

enum ShopEnhancementRow: Identifiable {
    case inventory(item: EquipmentCachedItem)
    case equipped(
        item: EquipmentCachedItem,
        characterId: Int,
        characterName: String,
        portraitAssetName: String
    )

    var id: String {
        switch self {
        case .inventory(let item):
            item.stackKey
        case .equipped(let item, let characterId, _, _):
            "\(item.equippedRowID)|\(characterId)"
        }
    }

    var item: EquipmentCachedItem {
        switch self {
        case .inventory(let item), .equipped(let item, _, _, _):
            item
        }
    }

    var itemID: CompositeItemID {
        item.itemID
    }

    var sectionKey: EquipmentSectionKey {
        item.sectionKey
    }

    var displayName: String {
        item.displayName
    }

    static func buildSections(
        inventoryItems: [EquipmentCachedItem],
        characters: [CharacterRecord],
        masterData: MasterData,
        matches: (EquipmentCachedItem) -> Bool
    ) -> [ShopEnhancementSection] {
        let itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        let nameResolver = EquipmentDisplayNameResolver(masterData: masterData)

        let filteredInventoryItems = inventoryItems
            .filter(matches)
            .sorted(by: EquipmentCachedItem.isOrderedBefore)
        let equippedRows = characters.flatMap { character in
            character.orderedEquippedItemStacks.compactMap { stack -> ShopEnhancementRow? in
                guard let baseItem = itemsByID[stack.itemID.baseItemId] else {
                    return nil
                }

                let item = EquipmentCachedItem(
                    itemID: stack.itemID,
                    stackKey: stack.itemID.stableKey,
                    equippedRowID: "\(stack.itemID.stableKey)|shop-enhancement|\(character.characterId)",
                    quantity: stack.count,
                    displayName: nameResolver.displayName(for: stack.itemID),
                    category: baseItem.category,
                    rarity: baseItem.rarity
                )
                guard matches(item) else {
                    return nil
                }

                return .equipped(
                    item: item,
                    characterId: character.characterId,
                    characterName: character.name,
                    portraitAssetName: masterData.portraitAssetName(for: character)
                )
            }
        }

        let equippedRowsBySection = Dictionary(grouping: equippedRows, by: \.sectionKey)
        let sectionKeys = Set(filteredInventoryItems.map(\.sectionKey))
            .union(equippedRowsBySection.keys)
            .sorted(by: EquipmentSectionKey.isOrderedBefore)

        return sectionKeys.compactMap { sectionKey in
            let inventorySectionItems = filteredInventoryItems.filter { $0.sectionKey == sectionKey }
            let equippedSectionRows = (equippedRowsBySection[sectionKey] ?? []).sorted { lhs, rhs in
                Self.isOrderedBefore(lhs, rhs)
            }
            let equippedRowsByItemID = Dictionary(grouping: equippedSectionRows, by: \.itemID)
            var matchedItemIDs = Set<CompositeItemID>()
            var rows: [ShopEnhancementRow] = []
            rows.reserveCapacity(inventorySectionItems.count + equippedSectionRows.count)

            for inventoryItem in inventorySectionItems {
                rows.append(.inventory(item: inventoryItem))

                if let matchedRows = equippedRowsByItemID[inventoryItem.itemID] {
                    rows.append(contentsOf: matchedRows)
                    matchedItemIDs.insert(inventoryItem.itemID)
                }
            }

            for equippedRow in equippedSectionRows where !matchedItemIDs.contains(equippedRow.itemID) {
                if let index = rows.firstIndex(where: { Self.isOrderedBefore(equippedRow, than: $0) }) {
                    rows.insert(equippedRow, at: index)
                } else {
                    rows.append(equippedRow)
                }
            }

            return rows.isEmpty ? nil : ShopEnhancementSection(key: sectionKey, rows: rows)
        }
    }

    private static func isOrderedBefore(
        _ lhs: ShopEnhancementRow,
        _ rhs: ShopEnhancementRow
    ) -> Bool {
        isOrderedBefore(lhs, than: rhs)
    }

    private static func isOrderedBefore(
        _ lhs: ShopEnhancementRow,
        than rhs: ShopEnhancementRow
    ) -> Bool {
        let leftItem = lhs.item
        let rightItem = rhs.item

        if EquipmentCachedItem.isOrderedBefore(leftItem, rightItem) {
            return true
        }
        if EquipmentCachedItem.isOrderedBefore(rightItem, leftItem) {
            return false
        }

        return switch (lhs, rhs) {
        case (.inventory, .equipped):
            true
        case (.equipped, .inventory):
            false
        default:
            false
        }
    }
}

struct ShopEnhancementInventorySummaryContent: View {
    let item: EquipmentCachedItem

    var body: some View {
        ShopItemSummaryContent(
            item: item,
            detailText: "所持 \(item.quantity)"
        )
    }
}

struct ShopEnhancementEquippedRowContent: View {
    let item: EquipmentCachedItem
    let characterName: String
    let portraitAssetName: String

    var body: some View {
        HStack(spacing: 12) {
            GameAssetImage(assetName: portraitAssetName)
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(item.isSuperRare ? .body.weight(.semibold) : .body)
                    .lineLimit(2)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 12)
        }
    }

    private var detailText: String {
        item.quantity > 1
            ? "装備中：\(characterName) x\(item.quantity)"
            : "装備中：\(characterName)"
    }
}
