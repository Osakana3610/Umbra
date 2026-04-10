// Defines player-wide persisted values shared across gameplay systems.

import Foundation

nonisolated enum EconomyPricing {
    // Shared hard cap for gold-facing prices so buy, sell, and unlock flows all agree on the same
    // economic ceiling.
    static let maximumEconomicPrice = 99_999_999
}

nonisolated struct PlayerState: Equatable, Sendable {
    var gold: Int
    var catTicketCount: Int
    var nextCharacterId: Int
    var autoReviveDefeatedCharacters: Bool
    var shopInventoryInitialized: Bool
    var autoSellItemIDs: Set<CompositeItemID>
    var lastBackgroundedAt: Date? = nil

    static let initial = PlayerState(
        // Start with enough gold to exercise early guild actions without turning the opening state
        // into a pure debug sandbox.
        gold: 10000,
        catTicketCount: 10,
        nextCharacterId: 1,
        autoReviveDefeatedCharacters: false,
        shopInventoryInitialized: false,
        autoSellItemIDs: [],
        lastBackgroundedAt: nil
    )
}
