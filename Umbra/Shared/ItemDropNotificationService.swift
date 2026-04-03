// Tracks adventure item-drop notifications for the shared tab-shell overlay.

import Foundation
import Observation

@MainActor
@Observable
final class ItemDropNotificationService {
    struct DroppedItemNotification: Identifiable, Equatable, Sendable {
        let id: UUID
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

    private let masterDataStore: MasterDataStore
    private let userDefaults: UserDefaults
    private let maxNotificationCount = 20

    private(set) var droppedItems: [DroppedItemNotification] = []

    init(
        masterDataStore: MasterDataStore,
        userDefaults: UserDefaults = .standard
    ) {
        self.masterDataStore = masterDataStore
        self.userDefaults = userDefaults
    }

    func publish(batches: [ExplorationDropNotificationBatch]) {
        guard !batches.isEmpty,
              let masterData = masterDataStore.masterData else {
            return
        }

        let displayNameResolver = EquipmentDisplayNameResolver(masterData: masterData)
        let itemsById = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        var notifications: [DroppedItemNotification] = []

        for batch in batches {
            for reward in batch.dropRewards
            where reward.itemID.isValidEquipmentIdentity
                && itemsById[reward.itemID.baseItemId] != nil
                && ItemDropNotificationSettings.allowsNotification(
                    for: reward.itemID,
                    rarity: itemsById[reward.itemID.baseItemId]?.rarity ?? .normal,
                    userDefaults: userDefaults
                ) {
                notifications.append(
                    DroppedItemNotification(
                        id: UUID(),
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
}
