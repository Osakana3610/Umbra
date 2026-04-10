// Defines a party's persisted identity, display name, member order, and sortie settings.

import Foundation

struct PartyRecord: Identifiable, Equatable, Sendable {
    static let maxPartyCount = 8
    static let memberLimit = 6
    static let unlockBaseCost = 2_000_000
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
        // Party names are trimmed and capped before persistence so every caller gets the same
        // validation behavior without duplicating UI-specific checks.
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    static func unlockCost(forExistingPartyCount currentPartyCount: Int) -> Int? {
        // Each extra slot doubles in price from the base amount until it reaches the shared
        // economy cap.
        guard currentPartyCount >= 1, currentPartyCount < maxPartyCount else {
            return nil
        }

        var rawCost = Int64(unlockBaseCost)
        for _ in 1..<currentPartyCount {
            rawCost *= 2
        }

        return min(Int(rawCost), EconomyPricing.maximumEconomicPrice)
    }

    static func unlockRequiresCappedJewel(forExistingPartyCount currentPartyCount: Int) -> Bool {
        // Once the uncapped series would exceed the gold ceiling, the unlock stays gold-capped and
        // requires a capped-price jewel to cover the remaining value.
        guard currentPartyCount >= 1, currentPartyCount < maxPartyCount else {
            return false
        }

        var rawCost = Int64(unlockBaseCost)
        for _ in 1..<currentPartyCount {
            rawCost *= 2
        }

        return rawCost > Int64(EconomyPricing.maximumEconomicPrice)
    }
}
