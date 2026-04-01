// Defines player-wide persisted values shared across gameplay systems.

import Foundation

nonisolated struct PlayerState: Equatable, Sendable {
    var gold: Int
    var nextCharacterId: Int
    var autoReviveDefeatedCharacters: Bool
    var lastProgressedAt: Date?

    static let initial = PlayerState(
        gold: 1000,
        nextCharacterId: 1,
        autoReviveDefeatedCharacters: false,
        lastProgressedAt: nil
    )
}
