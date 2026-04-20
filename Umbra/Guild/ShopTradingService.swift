// Executes persistence-backed shop transactions for buying, selling, and stock-only conversions.
// This service is the single place where gold, player inventory, and shop inventory are updated
// together so the economy rules stay consistent across the app.

import Foundation

@MainActor
final class ShopTradingService {
    private let coreDataRepository: GuildCoreDataRepository

    init(coreDataRepository: GuildCoreDataRepository) {
        self.coreDataRepository = coreDataRepository
    }

    func configureAutoSell(
        itemIDs: Set<CompositeItemID>,
        masterData: MasterData
    ) throws -> PlayerState {
        let orderedItemIDs = itemIDs.sorted { $0.isOrdered(before: $1) }
        guard orderedItemIDs.allSatisfy({ $0.isValid(in: masterData) }) else {
            throw GuildServiceError.invalidItemStack
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        guard !orderedItemIDs.isEmpty else {
            return roster.playerState
        }

        var inventoryStacks = try coreDataRepository.loadInventoryStacks()
        var shopInventoryStacks = try loadShopInventoryStacks()

        for itemID in orderedItemIDs {
            guard let ownedStack = inventoryStacks.first(where: { $0.itemID == itemID }),
                  ownedStack.count > 0 else {
                throw GuildServiceError.inventoryItemUnavailable
            }
        }

        for itemID in orderedItemIDs {
            let ownedCount = inventoryStacks.first(where: { $0.itemID == itemID })!.count
            // Auto-sell is configured by moving the entire currently owned stack into shop stock and
            // paying out immediately; future drops are handled elsewhere through player state flags.
            roster.playerState.autoSellItemIDs.insert(itemID)
            roster.playerState.gold += ShopPricingCalculator.sellPrice(for: itemID, masterData: masterData) * ownedCount
            GuildMutationResolver.decrementStack(itemID: itemID, count: ownedCount, in: &inventoryStacks)
            GuildMutationResolver.incrementStack(itemID: itemID, count: ownedCount, in: &shopInventoryStacks)
        }

        try coreDataRepository.saveTradeState(
            playerState: roster.playerState,
            inventoryStacks: inventoryStacks,
            shopInventoryStacks: shopInventoryStacks
        )
        return roster.playerState
    }

    func loadShopInventoryStacks() throws -> [CompositeItemStack] {
        try coreDataRepository.loadShopInventoryStacks()
    }

    func buyShopItem(
        itemID: CompositeItemID,
        count: Int,
        masterData: MasterData
    ) throws -> PlayerState {
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }
        guard count > 0 else {
            throw GuildServiceError.invalidStackCount
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        var inventoryStacks = try coreDataRepository.loadInventoryStacks()
        var shopInventoryStacks = try loadShopInventoryStacks()

        guard let shopStack = shopInventoryStacks.first(where: { $0.itemID == itemID }),
              shopStack.count >= count else {
            throw GuildServiceError.shopItemUnavailable
        }

        let purchasePrice = ShopPricingCalculator.purchasePrice(for: itemID, masterData: masterData)
        let totalPurchasePrice = purchasePrice * count
        guard roster.playerState.gold >= totalPurchasePrice else {
            throw GuildServiceError.insufficientGold(
                required: totalPurchasePrice,
                available: roster.playerState.gold
            )
        }

        roster.playerState.gold -= totalPurchasePrice
        // Buying always transfers stock out of the shop and into player inventory; no other storage
        // location participates in this transaction.
        GuildMutationResolver.decrementStack(itemID: itemID, count: count, in: &shopInventoryStacks)
        GuildMutationResolver.incrementStack(itemID: itemID, count: count, in: &inventoryStacks)

        try coreDataRepository.saveTradeState(
            playerState: roster.playerState,
            inventoryStacks: inventoryStacks,
            shopInventoryStacks: shopInventoryStacks
        )
        return roster.playerState
    }

    func sellInventoryItem(
        itemID: CompositeItemID,
        count: Int,
        masterData: MasterData
    ) throws -> PlayerState {
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }
        guard count > 0 else {
            throw GuildServiceError.invalidStackCount
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        var inventoryStacks = try coreDataRepository.loadInventoryStacks()
        var shopInventoryStacks = try loadShopInventoryStacks()

        guard let ownedStack = inventoryStacks.first(where: { $0.itemID == itemID }),
              ownedStack.count >= count else {
            throw GuildServiceError.inventoryItemUnavailable
        }

        roster.playerState.gold += ShopPricingCalculator.sellPrice(for: itemID, masterData: masterData) * count
        GuildMutationResolver.decrementStack(itemID: itemID, count: count, in: &inventoryStacks)
        GuildMutationResolver.incrementStack(itemID: itemID, count: count, in: &shopInventoryStacks)

        try coreDataRepository.saveTradeState(
            playerState: roster.playerState,
            inventoryStacks: inventoryStacks,
            shopInventoryStacks: shopInventoryStacks
        )
        return roster.playerState
    }

    func organizeShopInventoryItem(
        itemID: CompositeItemID,
        masterData: MasterData
    ) throws -> PlayerState {
        guard itemID.isValid(in: masterData) else {
            throw GuildServiceError.invalidItemStack
        }

        var roster = try coreDataRepository.loadRosterSnapshot()
        var shopInventoryStacks = try loadShopInventoryStacks()

        guard let baseItem = masterData.items.first(where: { $0.id == itemID.baseItemId }),
              baseItem.rarity != .normal,
              let stack = shopInventoryStacks.first(where: { $0.itemID == itemID }),
              stack.count >= ShopPricingCalculator.stockOrganizationBundleSize else {
            throw GuildServiceError.stockOrganizationUnavailable
        }

        // Stock organization is a sink that destroys a fixed batch of rare-or-better items and turns
        // them into cat tickets; the item never returns to player inventory.
        roster.playerState.catTicketCount += ShopPricingCalculator.stockOrganizationTicketCount(
            for: baseItem.basePrice
        )
        GuildMutationResolver.decrementStack(
            itemID: itemID,
            count: ShopPricingCalculator.stockOrganizationBundleSize,
            in: &shopInventoryStacks
        )

        try coreDataRepository.saveTradeState(
            playerState: roster.playerState,
            inventoryStacks: try coreDataRepository.loadInventoryStacks(),
            shopInventoryStacks: shopInventoryStacks
        )
        return roster.playerState
    }
}
