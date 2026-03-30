// Verifies item-drop notification formatting, highlighting, and lifecycle behavior.

import Testing
@testable import Umbra

@MainActor
struct ItemDropNotificationServiceTests {
    @Test
    func publishFormatsPartyPrefixedDisplayText() {
        let masterData = makeMasterData()
        let masterDataStore = MasterDataStore(phase: .loaded(masterData))
        let service = ItemDropNotificationService(masterDataStore: masterDataStore)

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
        let masterDataStore = MasterDataStore(phase: .loaded(makeMasterData()))
        let service = ItemDropNotificationService(masterDataStore: masterDataStore)

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

    private func makeMasterData() -> MasterData {
        MasterData(
            metadata: MasterData.Metadata(generator: "test"),
            races: [],
            jobs: [],
            aptitudes: [],
            items: [
                MasterData.Item(
                    id: 1,
                    name: "剣",
                    category: .sword,
                    rarity: .normal,
                    basePrice: 10,
                    nativeBaseStats: MasterData.BaseStats(
                        vitality: 0,
                        strength: 0,
                        mind: 0,
                        intelligence: 0,
                        agility: 0,
                        luck: 0
                    ),
                    nativeBattleStats: MasterData.BattleStats(
                        maxHP: 0,
                        physicalAttack: 0,
                        physicalDefense: 0,
                        magic: 0,
                        magicDefense: 0,
                        healing: 0,
                        accuracy: 0,
                        evasion: 0,
                        attackCount: 0,
                        criticalRate: 0,
                        breathPower: 0
                    ),
                    skillIds: [],
                    rangeClass: .melee,
                    normalDropTier: 1
                )
            ],
            titles: [
                MasterData.Title(
                    id: 1,
                    key: "light",
                    name: "光",
                    positiveMultiplier: 1,
                    negativeMultiplier: 1,
                    dropWeight: 1
                )
            ],
            superRares: [
                MasterData.SuperRare(
                    id: 1,
                    name: "極",
                    skillIds: []
                )
            ],
            skills: [],
            spells: [],
            recruitNames: MasterData.RecruitNames(
                male: [],
                female: [],
                unisex: []
            ),
            enemies: [],
            labyrinths: []
        )
    }
}
