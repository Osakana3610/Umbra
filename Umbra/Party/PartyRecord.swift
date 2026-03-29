// Defines a party's persisted identity, display name, member order, and sortie destination.

import Foundation

struct PartyRecord: Identifiable, Equatable, Sendable {
    static let maxPartyCount = 8
    static let memberLimit = 6
    static let unlockCost = 1
    static let defaultNamePrefix = "パーティ"
    static let maxNameLength = 50

    let partyId: Int
    var name: String
    var memberCharacterIds: [Int]
    var selectedLabyrinthId: Int?

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
