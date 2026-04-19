// Verifies exploration run planning, time-based progress reveal, persistence updates, and reward
// application across the exploration stack.
// The suite covers both service-level mutations and store refresh behavior because exploration state
// is spread across run snapshots, roster state, notifications, and inventory side effects.

import CoreData
import Foundation
import Testing
@testable import Umbra

@Suite(.serialized)
@MainActor
struct UmbraExplorationTests {
    @Test
    func startingBulkRunsKeepsStartedAtAlignedAcrossParties() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: ExplorationCoreDataRepository(container: container)
        )
        let masterData = currentMasterData()
        let itemDropNotificationService = ItemDropNotificationService(masterData: masterData)
        let rosterStore = GuildRosterStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.roster,
            phase: .loaded
        )
        let explorationStore = ExplorationStore(
            coreDataRepository: ExplorationCoreDataRepository(container: container),
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )

        let firstCharacter = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let secondCharacter = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
        snapshot.playerState.gold = 10_000_000
        try guildCoreDataRepository.saveRosterSnapshot(snapshot)

        _ = try guildServices.parties.unlockParty()
        _ = try await guildServices.parties.addCharacter(characterId: firstCharacter.characterId, toParty: 1)
        _ = try await guildServices.parties.addCharacter(characterId: secondCharacter.characterId, toParty: 2)

        let startedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        await explorationStore.startConfiguredRuns(
            [
                ConfiguredRunStart(
                    partyId: 1,
                    labyrinthId: try #require(masterData.labyrinths.first?.id),
                    selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id)
                ),
                ConfiguredRunStart(
                    partyId: 2,
                    labyrinthId: try #require(masterData.labyrinths.first?.id),
                    selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id)
                ),
            ],
            startedAt: startedAt,
            masterData: masterData
        )

        let runs = explorationStore.runs.sorted { $0.partyId < $1.partyId }
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.startedAt == startedAt })
    }

    @Test
    func explorationProgressRefreshesRosterStoreGold() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let masterData = currentMasterData()
        let itemDropNotificationService = ItemDropNotificationService(masterData: masterData)
        let rosterStore = GuildRosterStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.roster
        )
        let explorationStore = ExplorationStore(
            coreDataRepository: explorationCoreDataRepository,
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore
        )

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        rosterStore.reload()
        let startingGold = try #require(rosterStore.playerState?.gold)
        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataRepository,
            masterData: masterData
        )

        await explorationStore.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        let result = await explorationStore.refreshProgress(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completionGold = try #require(explorationStore.runs.first?.completion?.gold)

        #expect(result.didApplyRewards)
        #expect(completionGold > 0)
        #expect(try guildCoreDataRepository.loadRosterSnapshot().playerState.gold == startingGold + completionGold)
        #expect(try guildCoreDataRepository.loadFreshRosterSnapshot().playerState.gold == startingGold + completionGold)
        rosterStore.refreshFromPersistence()
        #expect(rosterStore.playerState?.gold == startingGold + completionGold)
    }

    @Test
    func activeRunBlocksPartyAndEquipmentMutations() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let itemID = CompositeItemID.baseItem(itemId: try #require(masterData.items.first?.id))

        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try guildServices.inventory.addInventoryStacks(
            [CompositeItemStack(itemID: itemID, count: 1)],
            masterData: masterData
        )
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: Date(timeIntervalSinceReferenceDate: 200_000),
            masterData: masterData
        )

        do {
            _ = try await guildServices.parties.removeCharacter(characterId: character.characterId, fromParty: 1)
            Issue.record("探索中パーティからメンバーを外せてはいけません。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("出撃中") == true)
        }

        do {
            _ = try await guildServices.equipment.equip(
                itemID: itemID,
                toCharacter: character.characterId,
                masterData: masterData
            )
            Issue.record("探索中キャラクターの装備変更は失敗する必要があります。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("出撃中") == true)
        }

        do {
            _ = try await guildServices.roster.changeJob(
                characterId: character.characterId,
                to: try jobId(named: "剣士", in: masterData),
                masterData: masterData
            )
            Issue.record("探索中キャラクターの転職は失敗する必要があります。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("出撃中") == true)
        }
    }

    @Test
    func startingRunRestoresLivingPartyMembersToMaxHP() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 10,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 3, in: container)

        let injuredCharacterRecord = try guildCoreDataRepository.loadCharacter(characterId: character.characterId)
        let injuredCharacter = try #require(injuredCharacterRecord)
        let maxHP = try #require(
            CharacterDerivedStatsCalculator.status(for: injuredCharacter, masterData: masterData)?.maxHP
        )

        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: Date(timeIntervalSinceReferenceDate: 260_000),
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)
        let persistedCharacterRecord = try guildCoreDataRepository.loadCharacter(characterId: character.characterId)
        let persistedCharacter = try #require(persistedCharacterRecord)

        #expect(startedRun.memberSnapshots.map(\.currentHP) == [maxHP])
        #expect(startedRun.currentPartyHPs == [maxHP])
        #expect(persistedCharacter.currentHP == maxHP)
    }

    @Test
    func startingRunAppliesExplorationTimeSkillToProgressInterval() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try jobId(named: "忍者", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)

        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: Date(timeIntervalSinceReferenceDate: 265_000),
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)

        #expect(startedRun.progressIntervalMultiplier == 0.8)
    }

    @Test
    func startingRunRejectsPartyContainingDefeatedMember() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try setCurrentHP(characterId: character.characterId, to: 0, in: container)

        do {
            _ = try await explorationService.startRun(
                partyId: 1,
                labyrinthId: try #require(masterData.labyrinths.first?.id),
                selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
                startedAt: Date(timeIntervalSinceReferenceDate: 270_000),
                masterData: masterData
            )
            Issue.record("HP 0 のメンバーを含むパーティは出撃できてはいけません。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("HPが0") == true)
        }
    }

    @Test
    func startingRunPrecomputesPlannedArtifactsWhileKeepingProgressHidden() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataRepository,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 280_000)
        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)
        let storedDetail = try #require(await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1))

        #expect(startedRun.completedBattleCount == 0)
        #expect(startedRun.completion == nil)
        #expect(startedRun.battleLogs.isEmpty)

        #expect(storedDetail.completedBattleCount == 0)
        #expect(storedDetail.completion == nil)
        #expect(storedDetail.battleLogs.count > startedRun.battleLogs.count)
        #expect(storedDetail.goldBuffer > 0)
        #expect(!storedDetail.experienceRewards.isEmpty)

        let refreshedSnapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10_000),
            masterData: masterData
        )
        let completedRun = try #require(refreshedSnapshot.runs.first)
        let completion = try #require(completedRun.completion)

        #expect(storedDetail.battleLogs == completedRun.battleLogs)
        #expect(storedDetail.goldBuffer == completion.gold)
        #expect(storedDetail.experienceRewards == completion.experienceRewards)
    }

    @Test
    func startingRunAutomaticallyUsesCatTicketWhenConfiguredAndAvailable() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 100),
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "キャット・チケット迷宮",
                    progressIntervalSeconds: 10,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )

        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)

        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)
        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: 1,
            startedAt: startedAt,
            catTicketUsage: .automaticIfAvailable,
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)
        let refreshedRoster = try guildCoreDataRepository.loadFreshRosterSnapshot()

        #expect(refreshedRoster.playerState.catTicketCount == 9)
        #expect(startedRun.progressIntervalMultiplier == 0.5)
        #expect(startedRun.goldMultiplier == 2.0)
        #expect(startedRun.rareDropMultiplier == 2.0)
        #expect(startedRun.memberExperienceMultipliers == [2.0])

        let plannedDetail = try #require(await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1))
        #expect(plannedDetail.goldBuffer == 20)
        #expect(plannedDetail.experienceRewards == [
            ExplorationExperienceReward(characterId: character.characterId, experience: 20)
        ])

        let refreshedSnapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(5),
            masterData: masterData
        )
        let completedRun = try #require(refreshedSnapshot.runs.first)
        #expect(completedRun.completedBattleCount == 1)
        #expect(completedRun.completion?.completedAt == startedAt.addingTimeInterval(5))
    }

    @Test
    func startingRunCombinesRewardPctAddsAdditively() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let goldRewardSkill = MasterData.Skill(
            id: 1,
            name: "ゴールド+50%",
            description: "取得ゴールドが50%増加する。",
            effects: [
                MasterData.SkillEffect.rewardMultiplier(target: .goldGainMultiplier, operation: .pctAdd, value: 0.5, condition: nil)
            ]
        )
        let bonusRewardSkill = MasterData.Skill(
            id: 2,
            name: "報酬上乗せ",
            description: "取得ゴールドが30%、レア倍率が10%増加する。",
            effects: [
                MasterData.SkillEffect.rewardMultiplier(target: .goldGainMultiplier, operation: .pctAdd, value: 0.3, condition: nil),
                MasterData.SkillEffect.rewardMultiplier(target: .rareDropMultiplier, operation: .pctAdd, value: 0.1, condition: nil)
            ]
        )
        let masterData = makeExplorationBattleTestMasterData(
            skills: [goldRewardSkill, bonusRewardSkill],
            allyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 100),
            allyRaceSkillIds: [goldRewardSkill.id, bonusRewardSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 1),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "報酬迷宮",
                    progressIntervalSeconds: 10,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )

        let character = try guildServices.roster.hireCharacter(
            raceId: 1,
            jobId: 1,
            aptitudeId: 1,
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)

        let snapshot = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: 1,
            startedAt: Date(timeIntervalSinceReferenceDate: 301_000),
            masterData: masterData
        )
        let startedRun = try #require(snapshot.runs.first)

        #expect(startedRun.goldMultiplier == 1.8)
        #expect(startedRun.rareDropMultiplier == 1.1)
        #expect(startedRun.memberExperienceMultipliers == [1.0])
    }

    @Test
    func startingRunRequiringCatTicketFailsWhenPlayerHasNone() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)

        var rosterSnapshot = try guildCoreDataRepository.loadRosterSnapshot()
        rosterSnapshot.playerState.catTicketCount = 0
        try guildCoreDataRepository.saveRosterSnapshot(rosterSnapshot)

        do {
            _ = try await explorationService.startRun(
                partyId: 1,
                labyrinthId: try #require(masterData.labyrinths.first?.id),
                selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
                startedAt: Date(timeIntervalSinceReferenceDate: 305_000),
                catTicketUsage: .required,
                masterData: masterData
            )
            Issue.record("キャット・チケット必須出撃は所持0枚で失敗する必要があります。")
        } catch {
            let localizedError = error as? LocalizedError
            #expect(localizedError?.errorDescription?.contains("キャット・チケットが不足") == true)
        }
    }

    @Test
    func refreshingRunRevealsProgressFromStoredBattlePlan() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)

        let startedAt = Date(timeIntervalSinceReferenceDate: 290_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        let plannedDetail = try #require(await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1))
        let firstBattlePartyHPs = plannedDetail.battleLogs[0].combatants
            .filter { $0.side == .ally }
            .sorted { $0.formationIndex < $1.formationIndex }
            .map(\.remainingHP)

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(1),
            masterData: masterData
        )
        let activeRun = try #require(snapshot.runs.first)
        let refreshedDetail = try #require(await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1))

        #expect(activeRun.completedBattleCount == 1)
        #expect(activeRun.completion == nil)
        #expect(refreshedDetail.battleLogs.count == plannedDetail.battleLogs.count)
        #expect(refreshedDetail.completedBattleCount == 1)
        #expect(refreshedDetail.currentPartyHPs == firstBattlePartyHPs)
    }

    @Test
    func loadRunDetailPreservesActionTargetIdsIndependentFromResults() async throws {
        let explorationCoreDataRepository = ExplorationCoreDataRepository(
            container: PersistenceController(inMemory: true).container
        )
        let firstTargetId = BattleCombatantID(rawValue: "enemy:1:1")
        let secondTargetId = BattleCombatantID(rawValue: "enemy:1:2")

        try await explorationCoreDataRepository.insertRun(
            RunSessionRecord(
                partyRunId: 1,
                partyId: 1,
                labyrinthId: 1,
                selectedDifficultyTitleId: 1,
                targetFloorNumber: 1,
                startedAt: Date(timeIntervalSinceReferenceDate: 295_000),
                rootSeed: 1,
                memberSnapshots: [],
                memberCharacterIds: [],
                completedBattleCount: 0,
                currentPartyHPs: [],
                memberExperienceMultipliers: [],
                progressIntervalMultiplier: 1,
                goldMultiplier: 1,
                rareDropMultiplier: 1,
                partyAverageLuck: 0,
                latestBattleFloorNumber: nil,
                latestBattleNumber: nil,
                latestBattleOutcome: nil,
                battleLogs: [
                    ExplorationBattleLog(
                        battleRecord: BattleRecord(
                            runId: RunSessionID(partyId: 1, partyRunId: 1),
                            floorNumber: 1,
                            battleNumber: 1,
                            result: .victory,
                            turns: [
                                BattleTurnRecord(
                                    turnNumber: 1,
                                    actions: [
                                        BattleActionRecord(
                                            actorId: BattleCombatantID(rawValue: "character:1"),
                                            actionKind: .attack,
                                            actionRef: nil,
                                            actionFlags: [],
                                            targetIds: [firstTargetId, secondTargetId],
                                            results: [
                                                BattleTargetResult(
                                                    targetId: secondTargetId,
                                                    resultKind: .damage,
                                                    value: 12,
                                                    statusId: nil,
                                                    flags: []
                                                )
                                            ]
                                        )
                                    ]
                                )
                            ]
                        ),
                        combatants: [
                            BattleCombatantSnapshot(
                                id: BattleCombatantID(rawValue: "character:1"),
                                name: "前衛",
                                side: .ally,
                                imageAssetID: nil,
                                level: 1,
                                initialHP: 10,
                                maxHP: 10,
                                remainingHP: 10,
                                formationIndex: 0
                            ),
                            BattleCombatantSnapshot(
                                id: firstTargetId,
                                name: "敵A",
                                side: .enemy,
                                imageAssetID: nil,
                                level: 1,
                                initialHP: 10,
                                maxHP: 10,
                                remainingHP: 10,
                                formationIndex: 0
                            ),
                            BattleCombatantSnapshot(
                                id: secondTargetId,
                                name: "敵B",
                                side: .enemy,
                                imageAssetID: nil,
                                level: 1,
                                initialHP: 10,
                                maxHP: 10,
                                remainingHP: 0,
                                formationIndex: 1
                            )
                        ]
                    )
                ],
                goldBuffer: 0,
                experienceRewards: [],
                dropRewards: [],
                completion: nil
            )
        )

        let storedDetail = try #require(await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1))
        let storedAction = try #require(
            storedDetail.battleLogs.first?.battleRecord.turns.first?.actions.first
        )

        #expect(storedAction.targetIds == [firstTargetId, secondTargetId])
        #expect(storedAction.results.map(\.targetId) == [secondTargetId])
    }

    @Test
    func refreshingCompletedRunAppliesRewardsToPlayerAndCharacterState() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataRepository,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 300_000)
        let startingGold = try guildCoreDataRepository.loadRosterSnapshot().playerState.gold
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )
        let plannedRun = try #require(await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1))

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completedRun = try #require(snapshot.runs.first)
        let completion = try #require(completedRun.completion)

        #expect(snapshot.didApplyRewards)
        #expect(completion.gold == plannedRun.goldBuffer)
        #expect(completion.experienceRewards == plannedRun.experienceRewards)
        #expect(completedRun.battleLogs == plannedRun.battleLogs)

        let rosterSnapshot = try guildCoreDataRepository.loadRosterSnapshot()
        let updatedCharacter = try #require(
            rosterSnapshot.characters.first(where: { $0.characterId == character.characterId })
        )
        let awardedExperience = completion.experienceRewards
            .first(where: { $0.characterId == character.characterId })?
            .experience ?? 0
        let completedRunCurrentHP = try #require(completedRun.currentPartyHPs.first)
        let expectedCurrentHP: Int
        if rosterSnapshot.playerState.autoReviveDefeatedCharacters && completedRunCurrentHP == 0 {
            expectedCurrentHP = try #require(
                CharacterDerivedStatsCalculator.status(for: updatedCharacter, masterData: masterData)?.maxHP
            )
        } else {
            expectedCurrentHP = completedRunCurrentHP
        }
        #expect(rosterSnapshot.playerState.gold == startingGold + completion.gold)
        #expect(updatedCharacter.experience == awardedExperience)
        #expect(updatedCharacter.currentHP == expectedCurrentHP)
    }

    @Test
    func refreshingCompletedRunReportsInventoryAndShopRewardCountsSeparately() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let masterData = currentMasterData()
        let inventoryItemID = CompositeItemID.baseItem(itemId: try itemId(for: .sword, in: masterData))
        let autoSellItemID = CompositeItemID.baseItem(itemId: try itemId(for: .armor, in: masterData))
        var rosterSnapshot = try guildCoreDataRepository.loadRosterSnapshot()
        rosterSnapshot.playerState.autoSellItemIDs = [autoSellItemID]
        try guildCoreDataRepository.saveRosterSnapshot(rosterSnapshot)

        let completion = RunCompletionRecord(
            completedAt: Date(timeIntervalSinceReferenceDate: 305_010),
            reason: .cleared,
            gold: 0,
            experienceRewards: [],
            dropRewards: [
                ExplorationDropReward(itemID: inventoryItemID, sourceFloorNumber: 1, sourceBattleNumber: 1),
                ExplorationDropReward(itemID: inventoryItemID, sourceFloorNumber: 1, sourceBattleNumber: 1),
                ExplorationDropReward(itemID: autoSellItemID, sourceFloorNumber: 1, sourceBattleNumber: 1)
            ]
        )

        try await explorationCoreDataRepository.insertRun(
            RunSessionRecord(
                partyRunId: 1,
                partyId: 1,
                labyrinthId: try #require(masterData.labyrinths.first?.id),
                selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
                targetFloorNumber: 1,
                startedAt: Date(timeIntervalSinceReferenceDate: 305_000),
                rootSeed: 1,
                memberSnapshots: [],
                memberCharacterIds: [],
                completedBattleCount: 1,
                currentPartyHPs: [],
                memberExperienceMultipliers: [],
                progressIntervalMultiplier: 1,
                goldMultiplier: 1,
                rareDropMultiplier: 1,
                partyAverageLuck: 0,
                latestBattleFloorNumber: 1,
                latestBattleNumber: 1,
                latestBattleOutcome: .victory,
                battleLogs: [],
                goldBuffer: 0,
                experienceRewards: [],
                dropRewards: completion.dropRewards,
                completion: completion
            )
        )
        let completedRun = try #require(
            await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1)
        )

        let rewardApplication = try await explorationCoreDataRepository.commitProgressUpdates(
            [(currentSession: completedRun, resolvedSession: completedRun)],
            masterData: masterData
        )

        #expect(rewardApplication.didApplyRewards)
        #expect(rewardApplication.appliedInventoryCounts == [inventoryItemID: 2])
        #expect(rewardApplication.appliedShopInventoryCounts == [autoSellItemID: 1])
        #expect(
            try guildCoreDataRepository.loadInventoryStacks()
                == [CompositeItemStack(itemID: inventoryItemID, count: 2)]
        )
        #expect(
            try guildCoreDataRepository.loadShopInventoryStacks()
                == [CompositeItemStack(itemID: autoSellItemID, count: 1)]
        )
    }

    @Test
    func clearingRunUnlocksNextExplorationDifficulty() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 20, strength: 20, agility: 20),
            enemyBaseStats: battleBaseStats(vitality: 1),
            titles: [
                MasterData.Title(
                    id: 1,
                    key: "default",
                    name: "通常",
                    positiveMultiplier: 1.0,
                    negativeMultiplier: 1.0,
                    dropWeight: 1
                ),
                MasterData.Title(
                    id: 2,
                    key: "next",
                    name: "次段階",
                    positiveMultiplier: 1.2,
                    negativeMultiplier: 1.2,
                    dropWeight: 1
                )
            ],
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "解放確認迷宮",
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let labyrinthId = 1
        let defaultDifficultyTitleId = try #require(masterData.defaultExplorationDifficultyTitle?.id)
        let nextDifficultyTitleId = try #require(
            masterData.nextExplorationDifficultyTitleId(after: defaultDifficultyTitleId)
        )

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try await guildServices.roster.updateAutoBattleSettings(
            characterId: character.characterId,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0,
                priority: [.attack, .breath, .recoverySpell, .attackSpell]
            )
        )

        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: labyrinthId,
            selectedDifficultyTitleId: defaultDifficultyTitleId,
            startedAt: Date(timeIntervalSinceReferenceDate: 310_000),
            masterData: masterData
        )
        _ = try await explorationService.refreshRuns(
            at: Date(timeIntervalSinceReferenceDate: 310_010),
            masterData: masterData
        )

        let progressRecord = try guildCoreDataRepository.loadFreshRosterSnapshot().labyrinthProgressRecords.first {
            $0.labyrinthId == labyrinthId
        }
        #expect(progressRecord?.highestUnlockedDifficultyTitleId == nextDifficultyTitleId)
    }

    @Test
    func refreshProgressUsesStoredRunMemberSnapshotsInsteadOfLiveCharacters() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        try promoteCharacter(
            characterId: character.characterId,
            level: 40,
            in: container
        )
        try setCurrentHP(characterId: character.characterId, to: 999, in: container)
        try unlockLabyrinth(
            named: "森",
            in: guildCoreDataRepository,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 320_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "森" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )
        let plannedRun = try #require(await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1))

        try promoteCharacter(
            characterId: character.characterId,
            level: 1,
            in: container
        )

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completedRun = try #require(snapshot.runs.first)
        let completion = try #require(completedRun.completion)

        #expect(completion.gold == plannedRun.goldBuffer)
        #expect(completion.experienceRewards == plannedRun.experienceRewards)
        #expect(completedRun.battleLogs == plannedRun.battleLogs)
    }

    @Test
    func autoReviveRestoresDefeatedPartyMembersWhenRunReturns() async throws {
        let container = PersistenceController(inMemory: true).container
        let guildCoreDataRepository = GuildCoreDataRepository(container: container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: container)
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        let explorationService = ExplorationSessionService(coreDataRepository: explorationCoreDataRepository)
        let masterData = currentMasterData()

        let character = try guildServices.roster.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        _ = try await guildServices.parties.addCharacter(characterId: character.characterId, toParty: 1)
        _ = try guildServices.roster.setAutoReviveDefeatedCharactersEnabled(true)
        try unlockLabyrinth(
            named: "洞窟",
            in: guildCoreDataRepository,
            masterData: masterData
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 500_000)
        _ = try await explorationService.startRun(
            partyId: 1,
            labyrinthId: try #require(masterData.labyrinths.first(where: { $0.name == "洞窟" })?.id),
            selectedDifficultyTitleId: try #require(masterData.defaultExplorationDifficultyTitle?.id),
            startedAt: startedAt,
            masterData: masterData
        )

        let snapshot = try await explorationService.refreshRuns(
            at: startedAt.addingTimeInterval(10),
            masterData: masterData
        )
        let completedRun = try #require(snapshot.runs.first)
        #expect(completedRun.completion?.reason == .defeated)

        let updatedCharacter = try #require(
            guildCoreDataRepository.loadRosterSnapshot().characters.first(where: { $0.characterId == character.characterId })
        )
        #expect(updatedCharacter.currentHP > 0)
    }

    @Test
    func completedExplorationLogsArePrunedByRetentionCount() async throws {
        let previousValue = UserDefaults.standard.object(forKey: ExplorationLogRetentionRepository.userDefaultsKey)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: ExplorationLogRetentionRepository.userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ExplorationLogRetentionRepository.userDefaultsKey)
            }
        }

        UserDefaults.standard.set(2, forKey: ExplorationLogRetentionRepository.userDefaultsKey)

        let explorationCoreDataRepository = ExplorationCoreDataRepository(
            container: PersistenceController(inMemory: true).container
        )
        for partyRunId in 1...201 {
            try await explorationCoreDataRepository.insertRun(
                makeCompletedRunRecord(
                    partyRunId: partyRunId,
                    startedAt: Date(timeIntervalSinceReferenceDate: Double(partyRunId) * 1_000)
                )
            )
        }

        #expect(try await explorationCoreDataRepository.pruneCompletedRunsExceedingRetentionLimit())
        #expect(try await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 1) == nil)
        #expect(try await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 2) != nil)
        #expect(try await explorationCoreDataRepository.loadRunDetail(partyId: 1, partyRunId: 201) != nil)
    }

}
