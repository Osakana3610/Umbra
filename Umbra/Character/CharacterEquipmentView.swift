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
    @State private var presentedItemDetail: PresentedItemDetail?

    var body: some View {
        Group {
            if let character {
                let filterCatalog = filterCatalog(for: character)
                let visibleSections = visibleSections(for: character)

                List {
                    Section {
                        header(for: character)
                    }

                    Section("装備中 (\(character.equippedItemCount)/\(character.maximumEquippedItemCount))") {
                        if equippedItems(for: character).isEmpty {
                            Text("装備なし")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(equippedItems(for: character)) { item in
                                EquippedItemRow(
                                    item: item,
                                    characterPortraitAssetName: character.portraitAssetName,
                                    onTap: {
                                        equipmentStore.unequip(
                                            itemID: item.itemID,
                                            from: character,
                                            masterData: masterData,
                                            rosterStore: rosterStore
                                        )
                                    },
                                    onShowDetail: {
                                        presentedItemDetail = PresentedItemDetail(itemID: item.itemID)
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
                            Section(section.key.title) {
                                EquipmentSectionRowsView(
                                    rows: section.rows,
                                    characterPortraitAssetName: character.portraitAssetName,
                                    isAtCapacity: character.equippedItemCount >= character.maximumEquippedItemCount,
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
                                        presentedItemDetail = PresentedItemDetail(itemID: itemID)
                                    }
                                )
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
                .sheet(item: $presentedItemDetail) { presentedItemDetail in
                    NavigationStack {
                        ItemDetailView(
                            itemID: presentedItemDetail.itemID,
                            masterData: masterData
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("閉じる") {
                                    self.presentedItemDetail = nil
                                }
                            }
                        }
                    }
                }
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
        filterCatalog: ItemBrowserFilterCatalog
    ) -> Bool {
        isSearching || itemFilter.isActive(in: filterCatalog)
    }

    private func equippedItems(for character: CharacterRecord) -> [EquipmentCachedItem] {
        equipmentStore.equippedItems(for: character, masterData: masterData)
    }

    private func visibleSections(for character: CharacterRecord) -> [EquipmentSectionRows] {
        equipmentStore.mergedSections(for: character.characterId).compactMap { section in
            let rows = visibleRows(in: section.rows)
            // Section headers disappear once search or filter conditions remove all rows, while the
            // underlying store still preserves the stable category and rarity ordering.
            guard !rows.isEmpty else {
                return nil
            }
            return EquipmentSectionRows(key: section.key, rows: rows)
        }
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

    private func filterCatalog(for character: CharacterRecord) -> ItemBrowserFilterCatalog {
        let itemIDs = equipmentStore.mergedSections(for: character.characterId)
            .flatMap(\.rows)
            .map { $0.cachedItem.itemID }
        return ItemBrowserFilterCatalog(
            itemIDs: itemIDs,
            masterData: masterData
        )
    }

    @ViewBuilder
    private func header(for character: CharacterRecord) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(character.portraitAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                Text(character.name)
                    .font(.title3.weight(.semibold))

                Text(masterData.characterSummaryText(for: character))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let status = CharacterDerivedStatsCalculator.status(for: character, masterData: masterData) {
                    Text("HP \(character.currentHP)/\(status.maxHP)")
                        .font(.subheadline)
                        .monospacedDigit()
                    Text(combatStyleText(for: status))
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
                Button {
                    onEquip(item.itemID)
                } label: {
                    HStack(spacing: 12) {
                        Text("x\(item.quantity)")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()

                        Text(item.displayName)
                            .font(item.isSuperRare ? .body.weight(.semibold) : .body)
                            .lineLimit(2)

                        Spacer(minLength: 12)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                // Inventory rows become non-interactive once the character is at the equip cap.
                .disabled(isAtCapacity)

                detailButton(for: item.itemID)
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
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(characterPortraitAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(.rect(cornerRadius: 10))

                    Text("x\(item.quantity)")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()

                    Text(item.displayName)
                        .font(item.isSuperRare ? .body.weight(.semibold) : .body)
                        .lineLimit(2)

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

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

private struct PresentedItemDetail: Identifiable {
    let itemID: CompositeItemID

    var id: String {
        itemID.stableKey
    }
}
