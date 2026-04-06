// Defines a party's persisted identity, display name, member order, and sortie settings.

import Foundation

struct PartyRecord: Identifiable, Equatable, Sendable {
    static let maxPartyCount = 8
    static let memberLimit = 6
    static let unlockCost = 1
    static let defaultNamePrefix = "パーティ"
    static let maxNameLength = 50
    static let maxPendingAutomaticRunCount = 20

    let partyId: Int
    var name: String
    var memberCharacterIds: [Int]
    var selectedLabyrinthId: Int?
    var selectedDifficultyTitleId: Int?
    var automaticallyUsesCatTicket: Bool = false
    var pendingAutomaticRunCount: Int = 0
    var pendingAutomaticRunStartedAt: Date? = nil

    var id: Int { partyId }

    var isFull: Bool {
        memberCharacterIds.count >= Self.memberLimit
    }

    static func defaultName(for partyId: Int) -> String {
        "\(defaultNamePrefix)\(partyId)"
    }

    static func normalizedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }
}
