// Defines player-wide persisted values shared across gameplay systems.

import Foundation

struct PlayerState: Equatable, Sendable {
    var gold: Int
    var nextCharacterId: Int

    static let initial = PlayerState(gold: 1000, nextCharacterId: 1)
}
