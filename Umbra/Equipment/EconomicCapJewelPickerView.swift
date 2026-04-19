// Presents a reusable picker for jewels whose economic price is capped at the shared maximum.

import SwiftUI

struct EconomicCapJewelPickerView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore
    let navigationTitle: String
    let descriptionText: String
    let confirmButtonTitle: String
    let emptyStateText: String
    let onConfirm: (EconomicCapJewelSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var selectedJewel: EconomicCapJewelSelection?
    @State private var presentedItemDetail: ItemDetailSheetPresentation?

    var body: some View {
        List {
            Section {
                Text(descriptionText)
                    .foregroundStyle(.secondary)
            }

            if let message = currentErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            if !equipmentStore.isLoaded {
                Section("宝石") {
                    ProgressView()
                }
            } else if cappedJewelSections.isEmpty {
                Section("宝石") {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(cappedJewelSections) { section in
                    Section(section.key.title) {
                        ForEach(section.rows) { row in
                            cappedJewelRow(for: row)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "宝石名で検索")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(confirmButtonTitle) {
                    guard let selectedJewel else {
                        return
                    }
                    onConfirm(selectedJewel)
                }
                .disabled(selectedJewel == nil || equipmentStore.isMutating)
            }
        }
        .itemDetailSheet(item: $presentedItemDetail, masterData: masterData)
        .task {
            do {
                try equipmentStore.loadIfNeeded(masterData: masterData)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var currentErrorMessage: String? {
        loadError ?? equipmentStore.lastOperationError
    }

    private var inventoryItems: [EquipmentCachedItem] {
        equipmentStore.displayOrderedInventoryItems
    }

    private var cappedJewelSections: [ShopEnhancementSection] {
        // Reuse the enhancement grouping so shared inventory and equipped jewels appear with the
        // same sections and labels as the existing jewel-management UI.
        ShopEnhancementRow.buildSections(
            inventoryItems: inventoryItems,
            characters: rosterStore.characters,
            masterData: masterData
        ) { item in
            item.category == .jewel
                && ShopPricingCalculator.purchasePrice(
                    for: item.itemID,
                    masterData: masterData
                ) == EconomyPricing.maximumEconomicPrice
                && (searchText.isEmpty || item.displayName.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var emptyStateMessage: String {
        if searchText.isEmpty {
            return emptyStateText
        }

        return "検索条件に一致する宝石がありません。"
    }

    @ViewBuilder
    private func cappedJewelRow(
        for row: ShopEnhancementRow
    ) -> some View {
        Button {
            selectedJewel = EconomicCapJewelSelection(
                itemID: row.itemID,
                characterId: row.characterId
            )
        } label: {
            HStack(alignment: .center, spacing: 12) {
                switch row {
                case .inventory(let item):
                    ShopEnhancementInventorySummaryContent(item: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .equipped(let item, _, let characterName, let portraitAssetName):
                    ShopEnhancementEquippedRowContent(
                        item: item,
                        characterName: characterName,
                        portraitAssetName: portraitAssetName
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("\(EconomyPricing.maximumEconomicPrice.formatted())G")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if selectedJewel == EconomicCapJewelSelection(
                    itemID: row.itemID,
                    characterId: row.characterId
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }

                ShopItemDetailButton(itemID: row.itemID) { itemID in
                    presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension ShopEnhancementRow {
    var characterId: Int? {
        switch self {
        case .inventory:
            nil
        case .equipped(_, let characterId, _, _):
            characterId
        }
    }
}
