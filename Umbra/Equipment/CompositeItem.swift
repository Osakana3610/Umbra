// Defines the canonical identity for equipment items across inventory, loadout, and reward flows.
// A composite item keeps the base item plus optional title, super-rare, and jewel parts together so
// every persistence layer can refer to one stable value instead of parallel columns.

import Foundation

nonisolated struct CompositeItemID: Codable, Equatable, Hashable, Sendable {
    let baseSuperRareId: Int
    let baseTitleId: Int
    let baseItemId: Int
    let jewelSuperRareId: Int
    let jewelTitleId: Int
    let jewelItemId: Int

    static func baseItem(
        itemId: Int,
        titleId: Int = 0,
        superRareId: Int = 0
    ) -> CompositeItemID {
        CompositeItemID(
            baseSuperRareId: superRareId,
            baseTitleId: titleId,
            baseItemId: itemId,
            jewelSuperRareId: 0,
            jewelTitleId: 0,
            jewelItemId: 0
        )
    }

    init(
        baseSuperRareId: Int,
        baseTitleId: Int,
        baseItemId: Int,
        jewelSuperRareId: Int,
        jewelTitleId: Int,
        jewelItemId: Int
    ) {
        self.baseSuperRareId = baseSuperRareId
        self.baseTitleId = baseTitleId
        self.baseItemId = baseItemId
        self.jewelSuperRareId = jewelSuperRareId
        self.jewelTitleId = jewelTitleId
        self.jewelItemId = jewelItemId
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ":")
        guard components.count == 6 else {
            return nil
        }

        let values = components.compactMap { Int($0) }
        guard values.count == 6 else {
            return nil
        }

        self.init(
            baseSuperRareId: values[0],
            baseTitleId: values[1],
            baseItemId: values[2],
            jewelSuperRareId: values[3],
            jewelTitleId: values[4],
            jewelItemId: values[5]
        )
    }

    var rawValue: String {
        // Persist the full identity in a stable positional format so the same key can be reused for
        // Core Data storage, view identity, and deterministic sorting.
        [
            baseSuperRareId,
            baseTitleId,
            baseItemId,
            jewelSuperRareId,
            jewelTitleId,
            jewelItemId
        ]
        .map(String.init)
        .joined(separator: ":")
    }

    var stableKey: String {
        rawValue
    }

    var isValidEquipmentIdentity: Bool {
        baseItemId > 0
    }

    func isOrdered(before other: CompositeItemID) -> Bool {
        // Base item identity sorts first so derived variants stay grouped under the same equipment
        // family before title and jewel refinements break ties.
        if baseItemId != other.baseItemId {
            return baseItemId < other.baseItemId
        }
        if baseSuperRareId != other.baseSuperRareId {
            return baseSuperRareId < other.baseSuperRareId
        }
        if baseTitleId != other.baseTitleId {
            return baseTitleId < other.baseTitleId
        }
        if jewelItemId != other.jewelItemId {
            return jewelItemId < other.jewelItemId
        }
        if jewelSuperRareId != other.jewelSuperRareId {
            return jewelSuperRareId < other.jewelSuperRareId
        }
        return jewelTitleId < other.jewelTitleId
    }

    func isValid(in masterData: MasterData) -> Bool {
        containsOptionalID(baseItemId, in: masterData.items) &&
            containsOptionalID(baseTitleId, in: masterData.titles) &&
            containsOptionalID(baseSuperRareId, in: masterData.superRares) &&
            containsOptionalID(jewelItemId, in: masterData.items) &&
            containsOptionalID(jewelTitleId, in: masterData.titles) &&
            containsOptionalID(jewelSuperRareId, in: masterData.superRares)
    }

    private func containsOptionalID<T: Identifiable>(
        _ id: Int,
        in values: [T]
    ) -> Bool where T.ID == Int {
        id == 0 || values.contains(where: { $0.id == id })
    }
}

nonisolated struct CompositeItemStack: Codable, Equatable, Sendable, Identifiable {
    let itemID: CompositeItemID
    let count: Int

    var id: String {
        itemID.stableKey
    }
}

extension Array where Element == CompositeItemStack {
    nonisolated func normalizedCompositeItemStacks() -> [CompositeItemStack] {
        var countsByID: [CompositeItemID: Int] = [:]
        var orderedIDs: [CompositeItemID] = []

        for stack in self {
            precondition(stack.count > 0, "Composite item stack counts must be positive.")
            precondition(
                stack.itemID.isValidEquipmentIdentity,
                "Composite item stack identities must be valid."
            )

            if countsByID[stack.itemID] == nil {
                // Preserve first-seen order for equivalent stacks so callers can merge duplicates
                // without unexpectedly reshuffling already ordered collections.
                orderedIDs.append(stack.itemID)
            }
            countsByID[stack.itemID, default: 0] += stack.count
        }

        return orderedIDs.map { itemID in
            CompositeItemStack(itemID: itemID, count: countsByID[itemID] ?? 0)
        }
    }
}
