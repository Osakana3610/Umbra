// Presents one character's equipment editor backed by the shared inventory cache.

import SwiftUI

struct CharacterEquipmentView: View {
    let characterId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    @State private var itemFilter = ItemBrowserFilter()
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var presentedItemDetail: ItemDetailSheetPresentation?
    @State private var filterCatalog = ItemBrowserFilterOptions(
        itemIDs: [CompositeItemID](),
        masterData: MasterData.current
    )
    @State private var visibleSections: [EquipmentSectionRows] = []
    @State private var headerStatus: CharacterStatus?

    var body: some View {
        Group {
            if let character {
                let maximumEquippedItemCount = maximumEquippedItemCount(for: character)

                List {
                    Section {
                        header(for: character)
                    }

                    Section("装備中 (\(character.equippedItemCount)/\(maximumEquippedItemCount))") {
                        if equippedItems(for: character).isEmpty {
                            Text("装備なし")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(equippedItems(for: character)) { item in
                                EquippedItemRow(
                                    item: item,
                                    characterPortraitAssetName: masterData.portraitAssetName(for: character),
                                    onTap: {
                                        equipmentStore.unequip(
                                            itemID: item.itemID,
                                            from: character,
                                            masterData: masterData,
                                            rosterStore: rosterStore
                                        )
                                    },
                                    onShowDetail: {
                                        presentedItemDetail = ItemDetailSheetPresentation(itemID: item.itemID)
                                    }
                                )
                                .equatable()
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    }

                    if let loadError {
                        Section("装備候補") {
                            Text(loadError)
                                .foregroundStyle(.red)
                        }
                    } else if !equipmentStore.isLoaded {
                        Section("装備候補") {
                            EquipmentInventoryLoadingRow()
                        }
                    } else if visibleSections.isEmpty {
                        Section("装備候補") {
                            Text(hasFilteredInventoryResults(filterCatalog: filterCatalog)
                                ? "検索条件またはフィルター条件に一致する所持アイテムはありません。"
                                : "装備可能な所持アイテムはありません。")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(visibleSections) { section in
                            if #available(iOS 26.0, *) {
                                Section(section.key.title) {
                                    EquipmentSectionRowsView(
                                        rows: section.rows,
                                        masterData: masterData,
                                        characterPortraitAssetName: masterData.portraitAssetName(for: character),
                                        isAtCapacity: character.equippedItemCount >= maximumEquippedItemCount,
                                        onEquip: { itemID in
                                            equipmentStore.equip(
                                                itemID: itemID,
                                                to: character,
                                                masterData: masterData,
                                                rosterStore: rosterStore
                                            )
                                        },
                                        onUnequip: { itemID in
                                            equipmentStore.unequip(
                                                itemID: itemID,
                                                from: character,
                                                masterData: masterData,
                                                rosterStore: rosterStore
                                            )
                                        },
                                        onShowDetail: { itemID in
                                            presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
                                        }
                                    )
                                }
                                .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: visibleSections))
                            } else {
                                Section(section.key.title) {
                                    EquipmentSectionRowsView(
                                        rows: section.rows,
                                        masterData: masterData,
                                        characterPortraitAssetName: masterData.portraitAssetName(for: character),
                                        isAtCapacity: character.equippedItemCount >= maximumEquippedItemCount,
                                        onEquip: { itemID in
                                            equipmentStore.equip(
                                                itemID: itemID,
                                                to: character,
                                                masterData: masterData,
                                                rosterStore: rosterStore
                                            )
                                        },
                                        onUnequip: { itemID in
                                            equipmentStore.unequip(
                                                itemID: itemID,
                                                from: character,
                                                masterData: masterData,
                                                rosterStore: rosterStore
                                            )
                                        },
                                        onShowDetail: { itemID in
                                            presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    if let error = equipmentStore.lastOperationError,
                       !error.isEmpty {
                        Section {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .equipmentSectionIndexVisibility()
                .playerStatusContentInsetAware()
                .searchable(text: $searchText, prompt: "所持アイテムを検索")
                .navigationTitle(character.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if filterCatalog.hasOptions {
                        ToolbarItem(placement: .topBarTrailing) {
                            ItemBrowserFilterButton(
                                catalog: filterCatalog,
                                filter: $itemFilter
                            )
                        }
                    }
                }
                .itemDetailSheet(item: $presentedItemDetail, masterData: masterData)
                .task(id: character.id) {
                    do {
                        try equipmentStore.loadIfNeeded(masterData: masterData)
                        // Preparing merged sections up front avoids rebuilding the inventory/equipped
                        // interleave every time the view body re-evaluates.
                        equipmentStore.prepareMergedSectionsIfNeeded(for: character, masterData: masterData)
                        loadError = nil
                    } catch {
                        loadError = error.localizedDescription
                    }
                }
                .task(
                    id: CharacterEquipmentPresentationInput(
                        character: character,
                        searchText: trimmedSearchText,
                        itemFilter: itemFilter,
                        inventoryRevision: equipmentStore.contentRevision
                    )
                ) {
                    guard equipmentStore.isLoaded else {
                        return
                    }

                    rebuildPresentation(for: character)
                }
            } else {
                ContentUnavailableView(
                    "キャラクターが見つかりません",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
            }
        }
    }

    private var character: CharacterRecord? {
        rosterStore.charactersById[characterId]
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private func hasFilteredInventoryResults(
        filterCatalog: ItemBrowserFilterOptions
    ) -> Bool {
        isSearching || itemFilter.isActive(in: filterCatalog)
    }

    private func equippedItems(for character: CharacterRecord) -> [EquipmentCachedItem] {
        equipmentStore.equippedItems(for: character, masterData: masterData)
    }

    private func rebuildPresentation(for character: CharacterRecord) {
        let mergedSections = equipmentStore.mergedSections(for: character.characterId)
        filterCatalog = ItemBrowserFilterOptions(
            itemIDs: mergedSections.flatMap(\.rows).map { $0.cachedItem.itemID },
            masterData: masterData
        )
        visibleSections = mergedSections.compactMap { section in
            let rows = visibleRows(in: section.rows)
            // Section headers disappear once search or filter conditions remove all rows, while the
            // underlying store still preserves the stable category and rarity ordering.
            guard !rows.isEmpty else {
                return nil
            }
            return EquipmentSectionRows(key: section.key, rows: rows)
        }
        headerStatus = CharacterDerivedStatsCalculator.status(
            for: character,
            masterData: masterData
        )
    }

    private func visibleRows(in rows: [EquipmentDisplayRow]) -> [EquipmentDisplayRow] {
        rows.filter { row in
            let item = row.cachedItem
            guard itemFilter.matches(
                itemID: item.itemID,
                category: item.category
            ) else {
                return false
            }
            guard trimmedSearchText.isEmpty || row.displayName.localizedCaseInsensitiveContains(trimmedSearchText) else {
                return false
            }
            return true
        }
    }

    private func maximumEquippedItemCount(for character: CharacterRecord) -> Int {
        max(character.baseMaximumEquippedItemCount + (headerStatus?.equipmentCapacityModifier ?? 0), 0)
    }

    @ViewBuilder
    private func header(for character: CharacterRecord) -> some View {
        HStack(alignment: .top, spacing: 16) {
            GameAssetImage(assetName: masterData.portraitAssetName(for: character))
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text(character.name)
                    .font(.title3.weight(.semibold))

                Text(masterData.characterSummaryText(for: character))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let headerStatus {
                    Text("HP \(character.currentHP)/\(headerStatus.maxHP)")
                        .font(.subheadline)
                        .monospacedDigit()
                    Text(combatStyleText(for: headerStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func combatStyleText(for status: CharacterStatus) -> String {
        if status.isUnarmed {
            return "格闘"
        }

        // The label is derived from the equipped range mix, not from job identity.
        if status.hasMeleeWeapon && status.hasRangedWeapon {
            return "近距離+遠距離"
        }

        switch status.weaponRangeClass {
        case .none:
            return "補助"
        case .melee:
            return "近距離"
        case .ranged:
            return "遠距離"
        }
    }
}

private struct CharacterEquipmentPresentationInput: Equatable {
    let character: CharacterRecord
    let searchText: String
    let itemFilter: ItemBrowserFilter
    let inventoryRevision: Int
}

private struct EquipmentInventoryLoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("所持アイテムを読み込み中...")
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }
}

private struct EquipmentSectionRowsView: View {
    let rows: [EquipmentDisplayRow]
    let masterData: MasterData
    let characterPortraitAssetName: String
    let isAtCapacity: Bool
    let onEquip: (CompositeItemID) -> Void
    let onUnequip: (CompositeItemID) -> Void
    let onShowDetail: (CompositeItemID) -> Void

    var body: some View {
        ForEach(rows) { row in
            EquipmentDisplayRowView(
                row: row,
                characterPortraitAssetName: characterPortraitAssetName,
                isAtCapacity: isAtCapacity,
                onEquip: onEquip,
                onUnequip: onUnequip,
                onShowDetail: onShowDetail
            )
            .equatable()
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }
}

private struct EquipmentDisplayRowView: View, Equatable {
    let row: EquipmentDisplayRow
    let characterPortraitAssetName: String
    let isAtCapacity: Bool
    let onEquip: (CompositeItemID) -> Void
    let onUnequip: (CompositeItemID) -> Void
    let onShowDetail: (CompositeItemID) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row
            && lhs.characterPortraitAssetName == rhs.characterPortraitAssetName
            && lhs.isAtCapacity == rhs.isAtCapacity
    }

    var body: some View {
        switch row {
        case .inventory(let item):
            HStack(spacing: 12) {
                equipmentLabel(
                    title: item.displayName,
                    detail: "所持 \(item.quantity)",
                    emphasizesTitle: item.isSuperRare
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                detailButton(for: item.itemID)
            }
            .contentShape(Rectangle())
            // Inventory rows become non-interactive once the character is at the equip cap.
            .onTapGesture {
                guard !isAtCapacity else {
                    return
                }
                onEquip(item.itemID)
            }
        case .equipped(let item):
            EquippedItemRow(
                item: item,
                characterPortraitAssetName: characterPortraitAssetName,
                onTap: { onUnequip(item.itemID) },
                onShowDetail: { onShowDetail(item.itemID) }
            )
        }
    }

    @ViewBuilder
    private func equipmentLabel(
        title: String,
        detail: String,
        emphasizesTitle: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(emphasizesTitle ? .body.weight(.semibold) : .body)
                .lineLimit(2)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func detailButton(for itemID: CompositeItemID) -> some View {
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

private struct EquippedItemRow: View, Equatable {
    let item: EquipmentCachedItem
    let characterPortraitAssetName: String
    let onTap: () -> Void
    let onShowDetail: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
            && lhs.characterPortraitAssetName == rhs.characterPortraitAssetName
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(characterPortraitAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(item.isSuperRare ? .body.weight(.semibold) : .body)
                        .lineLimit(2)

                    Text("装備 \(item.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(item.displayName)、装備中")
            .accessibilityHint("タップで装備を外します。")

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("アイテム詳細")
        }
    }
}
