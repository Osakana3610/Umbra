// Verifies item-drop and equipment-status notification publication, formatting, and persistence.
// Notification behavior is isolated here because these services translate gameplay events into UI
// state and local settings, which are easy to break without affecting core gameplay tests.

import CoreData
import Foundation
import Testing
@testable import Umbra

@Suite(.serialized)
@MainActor
struct UmbraNotificationTests {
    @Test
    func publishFormatsPartyPrefixedDisplayText() {
        let masterData = itemDropNotificationTestMasterData()
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let service = ItemDropNotificationService(
            masterData: masterData,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 3,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: CompositeItemID(
                                baseSuperRareId: 1,
                                baseTitleId: 1,
                                baseItemId: 1,
                                jewelSuperRareId: 0,
                                jewelTitleId: 0,
                                jewelItemId: 0
                            ),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        ),
                        ExplorationDropReward(
                            itemID: CompositeItemID.baseItem(itemId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 2
                        )
                    ]
                )
            ]
        )

        #expect(service.droppedItems.count == 2)
        #expect(service.droppedItems[0].displayText == "PT3：極光剣")
        #expect(service.droppedItems[0].isSuperRare)
        #expect(service.droppedItems[1].displayText == "PT3：剣")
    }

    @Test
    func clearRemovesPublishedNotifications() {
        let masterData = itemDropNotificationTestMasterData()
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let service = ItemDropNotificationService(
            masterData: masterData,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )
        service.clear()

        #expect(service.droppedItems.isEmpty)
    }

    @Test
    func publishSkipsNotificationsForDisabledTitle() {
        let masterData = itemDropNotificationTestMasterData()
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        ItemDropNotificationSettingsRepository.setTitleEnabled(false, titleId: 1, userDefaults: userDefaults)
        let service = ItemDropNotificationService(
            masterData: masterData,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1, titleId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )

        #expect(!ItemDropNotificationSettingsRepository.allowsNotification(
            for: .baseItem(itemId: 1, titleId: 1),
            rarity: .normal,
            userDefaults: userDefaults
        ))
        #expect(service.droppedItems.isEmpty)
    }

    @Test
    func publishSkipsNotificationsForDisabledSuperRare() {
        let masterData = itemDropNotificationTestMasterData()
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        ItemDropNotificationSettingsRepository.setSuperRareEnabled(false, superRareId: 1, userDefaults: userDefaults)
        let service = ItemDropNotificationService(
            masterData: masterData,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1, superRareId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )

        #expect(!ItemDropNotificationSettingsRepository.allowsNotification(
            for: .baseItem(itemId: 1, superRareId: 1),
            rarity: .normal,
            userDefaults: userDefaults
        ))
        #expect(service.droppedItems.isEmpty)
    }

    @Test
    func publishSkipsNotificationsForIgnoredNormalRarityItems() {
        let masterData = itemDropNotificationTestMasterData()
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        ItemDropNotificationSettingsRepository.setShowsNormalRarityItems(false, userDefaults: userDefaults)
        let service = ItemDropNotificationService(
            masterData: masterData,
            userDefaults: userDefaults
        )

        service.publish(
            batches: [
                ExplorationDropNotificationBatch(
                    partyId: 1,
                    dropRewards: [
                        ExplorationDropReward(
                            itemID: .baseItem(itemId: 1),
                            sourceFloorNumber: 1,
                            sourceBattleNumber: 1
                        )
                    ]
                )
            ]
        )

        #expect(!ItemDropNotificationSettingsRepository.allowsNotification(
            for: .baseItem(itemId: 1),
            rarity: .normal,
            userDefaults: userDefaults
        ))
        #expect(service.droppedItems.isEmpty)
    }

    @Test
    func equipmentStatusNotificationsPublishOnlyChangedStats() {
        let service = EquipmentStatusNotificationService()
        let beforeStatus = equipmentStatusNotificationTestStatus(
            baseStats: CharacterBaseStats(
                vitality: 10,
                strength: 12,
                mind: 8,
                intelligence: 7,
                agility: 9,
                luck: 6
            ),
            battleStats: CharacterBattleStats(
                maxHP: 25,
                physicalAttack: 14,
                physicalDefense: 11,
                magic: 10,
                magicDefense: 13,
                healing: 4,
                accuracy: 6,
                evasion: 5,
                attackCount: 2,
                criticalRate: 3,
                breathPower: 0
            ),
            battleDerivedStats: CharacterBattleDerivedStats(
                physicalDamageMultiplier: 1.0,
                attackMagicMultiplier: 1.0,
                spellDamageMultiplier: 1.0,
                criticalDamageMultiplier: 1.0,
                meleeDamageMultiplier: 1.1,
                rangedDamageMultiplier: 1.0,
                actionSpeedMultiplier: 1.0,
                physicalResistanceMultiplier: 1.0,
                magicResistanceMultiplier: 1.0,
                breathResistanceMultiplier: 1.0
            )
        )
        let afterStatus = equipmentStatusNotificationTestStatus(
            baseStats: CharacterBaseStats(
                vitality: 10,
                strength: 14,
                mind: 8,
                intelligence: 7,
                agility: 9,
                luck: 6
            ),
            battleStats: CharacterBattleStats(
                maxHP: 29,
                physicalAttack: 14,
                physicalDefense: 11,
                magic: 10,
                magicDefense: 12,
                healing: 4,
                accuracy: 6,
                evasion: 5,
                attackCount: 2,
                criticalRate: 3,
                breathPower: 0
            ),
            battleDerivedStats: CharacterBattleDerivedStats(
                physicalDamageMultiplier: 1.0,
                attackMagicMultiplier: 1.0,
                spellDamageMultiplier: 1.0,
                criticalDamageMultiplier: 1.0,
                meleeDamageMultiplier: 1.15,
                rangedDamageMultiplier: 1.0,
                actionSpeedMultiplier: 1.0,
                physicalResistanceMultiplier: 1.0,
                magicResistanceMultiplier: 1.0,
                breathResistanceMultiplier: 1.0
            )
        )

        service.publish(before: beforeStatus, after: afterStatus)

        #expect(service.notifications.map(\.displayText) == [
            "腕力 14（+2）",
            "最大HP 29（+4）",
            "魔法防御 12（-1）",
            "近接威力倍率 115%（+5%）"
        ])
    }

    @Test
    func clearRemovesPublishedEquipmentStatusNotifications() {
        let service = EquipmentStatusNotificationService()

        service.publish(
            before: equipmentStatusNotificationTestStatus(),
            after: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 12,
                    physicalAttack: 5,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )
        service.clear()

        #expect(service.notifications.isEmpty)
    }

    @Test
    func equipmentStatusNotificationsReplacePreviousOperation() {
        let service = EquipmentStatusNotificationService()

        service.publish(
            before: equipmentStatusNotificationTestStatus(),
            after: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 20,
                    physicalAttack: 3,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )
        service.publish(
            before: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 20,
                    physicalAttack: 3,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                )
            ),
            after: equipmentStatusNotificationTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 8,
                    physicalAttack: 3,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 0,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )

        #expect(service.notifications.map(\.displayText) == [
            "最大HP 8（-12）"
        ])
    }

}
