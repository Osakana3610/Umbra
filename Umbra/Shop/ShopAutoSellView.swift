// Manages the list of identities configured for auto-sell and the picker used to add new targets.
// The screen combines player inventory, shop stock, and saved auto-sell flags so the player can
// see both current ownership and whether one identity is already routed into automatic selling.

import SwiftUI

struct ShopAutoSellView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore
    let shopStore: ShopInventoryStore

    @State private var loadError: String?
    @State private var itemFilter = ItemBrowserFilter()
    @State private var searchText = ""
    @State private var presentedItemDetail: ItemDetailSheetPresentation?
    @State private var isPresentingInventoryPicker = false

    private let nameResolver: EquipmentDisplayNameResolver

    init(
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore,
        shopStore: ShopInventoryStore
    ) {
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.equipmentStore = equipmentStore
        self.shopStore = shopStore
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        List {
            if let message = currentErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            if !equipmentStore.isLoaded || !shopStore.isLoaded {
                Section("自動売却") {
                    ProgressView()
                }
            } else {
                if visibleSections.isEmpty {
                    Section("対象アイテム") {
                        Text(emptyStateMessage)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(visibleSections) { section in
                        if #available(iOS 26.0, *) {
                            Section(section.key.title) {
                                ForEach(section.rows) { candidate in
                                    autoSellRow(for: candidate)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                            }
                            .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: visibleSections))
                        } else {
                            Section(section.key.title) {
                                ForEach(section.rows) { candidate in
                                    autoSellRow(for: candidate)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .equipmentSectionIndexVisibility()
        .playerStatusContentInsetAware()
        .navigationTitle("自動売却")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "アイテム名で検索")
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.flexible)

                ToolbarItem {
                    Button {
                        isPresentingInventoryPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("自動売却に追加")
                }

                if currentFilterCatalog.hasOptions {
                    ToolbarSpacer(.fixed)

                    ToolbarItem {
                        ItemBrowserFilterButton(
                            catalog: currentFilterCatalog,
                            filter: $itemFilter
                        )
                    }
                }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isPresentingInventoryPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("自動売却に追加")

                    if currentFilterCatalog.hasOptions {
                        ItemBrowserFilterButton(
                            catalog: currentFilterCatalog,
                            filter: $itemFilter
                        )
                    }
                }
            }
        }
        .itemDetailSheet(item: $presentedItemDetail, masterData: masterData)
        .sheet(isPresented: $isPresentingInventoryPicker) {
            NavigationStack {
                ShopAutoSellInventoryPickerView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    equipmentStore: equipmentStore,
                    shopStore: shopStore
                )
            }
        }
        .task {
            do {
                // This screen renders both owned counts and shop counts for the same identity, so it
                // depends on both caches being warm before the list is meaningful.
                try equipmentStore.loadIfNeeded(masterData: masterData)
                try shopStore.loadIfNeeded(masterData: masterData)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var autoSellItemIDs: Set<CompositeItemID> {
        rosterStore.playerState?.autoSellItemIDs ?? []
    }

    private var currentErrorMessage: String? {
        loadError ?? shopStore.lastOperationError ?? rosterStore.lastOperationError
    }

    private var configuredCandidates: [AutoSellCandidate] {
        let inventoryCounts = Dictionary(
            uniqueKeysWithValues: equipmentStore.displayOrderedInventoryItems.map { ($0.itemID, $0.quantity) }
        )
        let shopCounts = Dictionary(
            uniqueKeysWithValues: shopStore.displayOrderedShopItems.map { ($0.itemID, $0.quantity) }
        )
        return autoSellItemIDs
            .sorted { $0.isOrdered(before: $1) }
            .compactMap { itemID in
            // Auto-sell is configured per item identity, not per concrete stack, so the summary pulls
            // together counts from every currently owned location for that one identity.
            guard let item = masterData.items.first(where: { $0.id == itemID.baseItemId }) else {
                return nil
            }

            let cachedItem = EquipmentCachedItem(
                itemID: itemID,
                stackKey: itemID.stableKey,
                equippedRowID: itemID.stableKey + "|auto-sell",
                quantity: inventoryCounts[itemID] ?? 0,
                displayName: nameResolver.displayName(for: itemID),
                category: item.category,
                rarity: item.rarity
            )

            return AutoSellCandidate(
                item: cachedItem,
                itemID: itemID,
                summaryText: [
                    item.category.displayName,
                    item.rarity.displayName,
                    inventoryCounts[itemID].map { "所持 \($0)個" },
                    shopCounts[itemID].map { "店 \($0)個" },
                ]
                .compactMap { $0 }
                .joined(separator: " / "),
                isEnabled: autoSellItemIDs.contains(itemID)
            )
        }
    }

    private var visibleCandidates: [AutoSellCandidate] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return configuredCandidates.filter { candidate in
            guard itemFilter.matches(
                itemID: candidate.itemID,
                category: candidate.item.category
            ) else {
                return false
            }
            guard trimmedSearchText.isEmpty || candidate.displayName.localizedCaseInsensitiveContains(trimmedSearchText) else {
                return false
            }
            return true
        }
    }

    private var visibleSections: [AutoSellSection] {
        // Group after filtering so the section index reflects only currently visible candidates.
        let grouped = Dictionary(grouping: visibleCandidates, by: \.sectionKey)
        return grouped.keys
            .sorted(by: EquipmentSectionKey.isOrderedBefore)
            .map { key in
                AutoSellSection(
                    key: key,
                    rows: grouped[key]?.sorted { lhs, rhs in
                        lhs.item.itemID.isOrdered(before: rhs.item.itemID)
                    } ?? []
                )
            }
    }

    private var currentFilterCatalog: ItemBrowserFilterOptions {
        ItemBrowserFilterOptions(
            itemIDs: configuredCandidates.map(\.itemID),
            masterData: masterData
        )
    }

    private var emptyStateMessage: String {
        if configuredCandidates.isEmpty {
            return "自動売却に設定したアイテムがありません。"
        }
        return "一致するアイテムがありません。"
    }

    private func autoSellRow(
        for candidate: AutoSellCandidate
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ShopItemSummaryContent(
                item: candidate.item,
                detailText: candidate.summaryText
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ShopItemDetailButton(itemID: candidate.itemID) { itemID in
                presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("外す", role: .destructive) {
                rosterStore.setAutoSellEnabled(
                    itemID: candidate.itemID,
                    isEnabled: false,
                    masterData: masterData
                )
            }
            .disabled(rosterStore.isMutating)
        }
    }
}

private struct ShopAutoSellInventoryPickerView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore
    let shopStore: ShopInventoryStore

    @Environment(\.dismiss) private var dismiss
    @State private var itemFilter = ItemBrowserFilter()
    @State private var searchText = ""
    @State private var selectedItemIDs = Set<CompositeItemID>()
    @State private var presentedItemDetail: ItemDetailSheetPresentation?

    var body: some View {
        List {
            if visibleSections.isEmpty {
                Section("所持アイテム") {
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(visibleSections) { section in
                    if #available(iOS 26.0, *) {
                        Section(section.key.title) {
                            ForEach(section.rows) { candidate in
                                pickerRow(for: candidate)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                        .sectionIndexLabel(equipmentSectionIndexLabel(for: section, in: visibleSections))
                    } else {
                        Section(section.key.title) {
                            ForEach(section.rows) { candidate in
                                pickerRow(for: candidate)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .equipmentSectionIndexVisibility()
        .navigationTitle("自動売却に追加")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "所持アイテムを検索")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // The picker only stages identities locally; persistence is updated once when the
                    // player confirms so partial selections never leak into player state.
                    shopStore.configureAutoSell(
                        itemIDs: selectedItemIDs,
                        masterData: masterData,
                        rosterStore: rosterStore,
                        equipmentStore: equipmentStore
                    )
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
                .accessibilityLabel("完了")
                .disabled(selectedItemIDs.isEmpty || shopStore.isMutating)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if filterCatalog.hasOptions {
                    ItemBrowserFilterButton(
                        catalog: filterCatalog,
                        filter: $itemFilter
                    )
                }
            }
        }
        .itemDetailSheet(item: $presentedItemDetail, masterData: masterData)
    }

    private var availableCandidates: [AutoSellCandidate] {
        let configuredItemIDs = rosterStore.playerState?.autoSellItemIDs ?? []
        return equipmentStore.displayOrderedInventoryItems
            // The picker only offers identities that are still in player inventory and not already
            // configured for auto-sell.
            .filter { configuredItemIDs.contains($0.itemID) == false }
            .map { item in
                AutoSellCandidate(
                    item: item,
                    itemID: item.itemID,
                    summaryText: "所持 \(item.quantity)個",
                    isEnabled: selectedItemIDs.contains(item.itemID)
                )
            }
    }

    private var filterCatalog: ItemBrowserFilterOptions {
        ItemBrowserFilterOptions(
            itemIDs: availableCandidates.map(\.itemID),
            masterData: masterData
        )
    }

    private var visibleCandidates: [AutoSellCandidate] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableCandidates.filter { candidate in
            guard itemFilter.matches(
                itemID: candidate.itemID,
                category: candidate.item.category
            ) else {
                return false
            }
            guard trimmedSearchText.isEmpty || candidate.displayName.localizedCaseInsensitiveContains(trimmedSearchText) else {
                return false
            }
            return true
        }
    }

    private var visibleSections: [AutoSellSection] {
        let grouped = Dictionary(grouping: visibleCandidates, by: \.sectionKey)
        return grouped.keys
            .sorted(by: EquipmentSectionKey.isOrderedBefore)
            .map { key in
                AutoSellSection(
                    key: key,
                    rows: grouped[key]?.sorted { lhs, rhs in
                        lhs.item.itemID.isOrdered(before: rhs.item.itemID)
                    } ?? []
                )
            }
    }

    private var emptyStateMessage: String {
        if availableCandidates.isEmpty {
            return "追加できる所持アイテムがありません。"
        }
        return "一致するアイテムがありません。"
    }

    private func pickerRow(
        for candidate: AutoSellCandidate
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                // Selection is identity-based, so tapping any visible row toggles the whole item
                // identity rather than one concrete stack instance.
                if selectedItemIDs.contains(candidate.itemID) {
                    selectedItemIDs.remove(candidate.itemID)
                } else {
                    selectedItemIDs.insert(candidate.itemID)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedItemIDs.contains(candidate.itemID) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            selectedItemIDs.contains(candidate.itemID)
                                ? Color.accentColor
                                : Color.secondary
                        )

                    ShopItemSummaryContent(
                        item: candidate.item,
                        detailText: candidate.summaryText
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ShopItemDetailButton(itemID: candidate.itemID) { itemID in
                presentedItemDetail = ItemDetailSheetPresentation(itemID: itemID)
            }
        }
    }
}

private struct AutoSellCandidate: Identifiable {
    let item: EquipmentCachedItem
    let itemID: CompositeItemID
    let summaryText: String
    let isEnabled: Bool

    var id: String {
        itemID.stableKey
    }

    var displayName: String {
        item.displayName
    }

    var sectionKey: EquipmentSectionKey {
        item.sectionKey
    }
}

private struct AutoSellSection: Identifiable {
    let key: EquipmentSectionKey
    let rows: [AutoSellCandidate]

    var id: EquipmentSectionKey {
        key
    }
}

extension AutoSellSection: EquipmentSectionIndexable {}
