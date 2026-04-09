// Defines player-wide persisted values shared across gameplay systems.

import Foundation

nonisolated struct PlayerState: Equatable, Sendable {
    var gold: Int
    var catTicketCount: Int
    var nextCharacterId: Int
    var autoReviveDefeatedCharacters: Bool
    var shopInventoryInitialized: Bool
    var autoSellItemIDs: Set<CompositeItemID>
    var lastBackgroundedAt: Date? = nil

    static let initial = PlayerState(
        gold: 1000,
        catTicketCount: 10,
        nextCharacterId: 1,
        autoReviveDefeatedCharacters: false,
        shopInventoryInitialized: false,
        autoSellItemIDs: [],
        lastBackgroundedAt: nil
    )
}
