// Tracks adventure item-drop notifications for the shared tab-shell overlay.

import Foundation
import Observation

@MainActor
@Observable
final class ItemDropNotificationService {
    struct DroppedItemNotification: Identifiable, Equatable, Sendable {
        let id: Int
        let displayName: String
        let isSuperRare: Bool
        let partyId: Int?

        var displayText: String {
            guard let partyId else {
                return displayName
            }

            return "PT\(partyId)：\(displayName)"
        }
    }

    private let masterData: MasterData
    private let userDefaults: UserDefaults
    private let maxNotificationCount = 20
    private var nextNotificationID = 0

    private(set) var droppedItems: [DroppedItemNotification] = []

    init(
        masterData: MasterData,
        userDefaults: UserDefaults = .standard
    ) {
        self.masterData = masterData
        self.userDefaults = userDefaults
    }

    func publish(batches: [ExplorationDropNotificationBatch]) {
        guard !batches.isEmpty else {
            return
        }

        let displayNameResolver = EquipmentDisplayNameResolver(masterData: masterData)
        let itemsById = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        var notifications: [DroppedItemNotification] = []

        for batch in batches {
            for reward in batch.dropRewards
            where reward.itemID.isValidEquipmentIdentity
                && itemsById[reward.itemID.baseItemId] != nil
                && ItemDropNotificationSettingsRepository.allowsNotification(
                    for: reward.itemID,
                    rarity: itemsById[reward.itemID.baseItemId]?.rarity ?? .normal,
                    userDefaults: userDefaults
                ) {
                notifications.append(
                    DroppedItemNotification(
                        id: makeNotificationID(),
                        displayName: displayNameResolver.displayName(for: reward.itemID),
                        isSuperRare: reward.itemID.baseSuperRareId > 0 || reward.itemID.jewelSuperRareId > 0,
                        partyId: batch.partyId
                    )
                )
            }
        }

        // Notifications are appended in reveal order and then trimmed to a fixed window so the
        // overlay remains bounded during long unattended auto-runs.
        guard !notifications.isEmpty else {
            return
        }

        droppedItems.append(contentsOf: notifications)

        if droppedItems.count > maxNotificationCount {
            droppedItems.removeFirst(droppedItems.count - maxNotificationCount)
        }
    }

    func clear() {
        droppedItems.removeAll()
    }

    private func makeNotificationID() -> Int {
        defer { nextNotificationID &+= 1 }
        return nextNotificationID
    }
}

nonisolated enum ItemDropNotificationSettingsRepository {
    static let showsNormalRarityItemsKey = "itemDropNotification.showsNormalRarityItems"
    private static let titleKeyPrefix = "itemDropNotification.title."
    private static let superRareKeyPrefix = "itemDropNotification.superRare."

    static func showsNormalRarityItems(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: showsNormalRarityItemsKey) as? Bool ?? true
    }

    static func setShowsNormalRarityItems(
        _ isEnabled: Bool,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(isEnabled, forKey: showsNormalRarityItemsKey)
    }

    static func isTitleEnabled(
        _ titleId: Int,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: titleKey(for: titleId)) as? Bool ?? true
    }

    static func setTitleEnabled(
        _ isEnabled: Bool,
        titleId: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(isEnabled, forKey: titleKey(for: titleId))
    }

    static func isSuperRareEnabled(
        _ superRareId: Int,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: superRareKey(for: superRareId)) as? Bool ?? true
    }

    static func setSuperRareEnabled(
        _ isEnabled: Bool,
        superRareId: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(isEnabled, forKey: superRareKey(for: superRareId))
    }

    static func allowsNotification(
        for itemID: CompositeItemID,
        rarity: ItemRarity,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard rarity != .normal || showsNormalRarityItems(userDefaults: userDefaults) else {
            return false
        }

        // Both base and jewel affixes are checked, so disabling any attached title or super-rare
        // suppresses the combined equipment notification.
        let titleIDs = Set([itemID.baseTitleId, itemID.jewelTitleId].filter { $0 > 0 })
        let superRareIDs = Set([itemID.baseSuperRareId, itemID.jewelSuperRareId].filter { $0 > 0 })

        return titleIDs.allSatisfy { isTitleEnabled($0, userDefaults: userDefaults) }
            && superRareIDs.allSatisfy { isSuperRareEnabled($0, userDefaults: userDefaults) }
    }

    private static func titleKey(for titleId: Int) -> String {
        "\(titleKeyPrefix)\(titleId)"
    }

    private static func superRareKey(for superRareId: Int) -> String {
        "\(superRareKeyPrefix)\(superRareId)"
    }
}
