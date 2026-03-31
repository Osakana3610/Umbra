// Coordinates exploration progression and reward application over Core Data-backed snapshots.

import Foundation

final class ExplorationSessionService {
    private let coreDataStore: ExplorationCoreDataStore

    init(coreDataStore: ExplorationCoreDataStore) {
        self.coreDataStore = coreDataStore
    }

    func startRun(
        partyId: Int,
        labyrinthId: Int,
        selectedDifficultyTitleId: Int,
        startedAt: Date,
        maximumLoopCount: Int,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        try await startConfiguredRuns(
            [
                ConfiguredRunStart(
                    partyId: partyId,
                    labyrinthId: labyrinthId,
                    selectedDifficultyTitleId: selectedDifficultyTitleId
                )
            ],
            startedAt: startedAt,
            maximumLoopCount: maximumLoopCount,
            masterData: masterData
        )
    }

    func startConfiguredRuns(
        _ runsToStart: [ConfiguredRunStart],
        startedAt: Date,
        maximumLoopCount: Int,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        guard !runsToStart.isEmpty else {
            return try await coreDataStore.loadSnapshot()
        }

        for runStart in runsToStart {
            var cachedStatuses: [Int: ExplorationMemberStatusCacheEntry] = [:]
            let plannedSession = try ExplorationResolver.plan(
                session: try await makeInitialSession(
                    runStart: runStart,
                    startedAt: startedAt,
                    maximumLoopCount: maximumLoopCount,
                    masterData: masterData
                ),
                masterData: masterData,
                cachedStatuses: &cachedStatuses
            )
            try await coreDataStore.insertRun(
                RunSessionRecord(
                    partyRunId: plannedSession.partyRunId,
                    partyId: plannedSession.partyId,
                    labyrinthId: plannedSession.labyrinthId,
                    selectedDifficultyTitleId: plannedSession.selectedDifficultyTitleId,
                    targetFloorNumber: plannedSession.targetFloorNumber,
                    startedAt: plannedSession.startedAt,
                    rootSeed: plannedSession.rootSeed,
                    maximumLoopCount: plannedSession.maximumLoopCount,
                    memberSnapshots: plannedSession.memberSnapshots,
                    memberCharacterIds: plannedSession.memberCharacterIds,
                    completedBattleCount: 0,
                    currentPartyHPs: plannedSession.memberSnapshots.map(\.currentHP),
                    memberExperienceMultipliers: plannedSession.memberExperienceMultipliers,
                    goldMultiplier: plannedSession.goldMultiplier,
                    rareDropMultiplier: plannedSession.rareDropMultiplier,
                    titleDropMultiplier: plannedSession.titleDropMultiplier,
                    partyAverageLuck: plannedSession.partyAverageLuck,
                    latestBattleFloorNumber: nil,
                    latestBattleNumber: nil,
                    latestBattleOutcome: nil,
                    battleLogs: plannedSession.battleLogs,
                    goldBuffer: plannedSession.goldBuffer,
                    experienceRewards: plannedSession.experienceRewards,
                    dropRewards: plannedSession.dropRewards,
                    completion: nil
                )
            )
        }

        return try await coreDataStore.loadSnapshot()
    }

    func refreshRuns(
        at currentDate: Date,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        let progressContexts = try await coreDataStore.loadProgressContexts()
        var runs: [RunSessionRecord] = []
        runs.reserveCapacity(progressContexts.count)
        var resolvedUpdates: [(currentSession: RunSessionRecord, resolvedSession: RunSessionRecord)] = []
        resolvedUpdates.reserveCapacity(progressContexts.count)

        for currentSession in progressContexts {
            let session: RunSessionRecord
            if currentSession.completion == nil {
                session = try ExplorationResolver.reveal(
                    session: currentSession,
                    upTo: currentDate,
                    masterData: masterData
                )
            } else {
                session = currentSession
            }
            resolvedUpdates.append(
                (currentSession: currentSession, resolvedSession: session)
            )
            runs.append(session.completion == nil ? session.summaryRecord : session)
        }

        let rewardApplication = try await coreDataStore.commitProgressUpdates(
            resolvedUpdates,
            masterData: masterData
        )

        return ExplorationRunSnapshot(
            runs: runs,
            didApplyRewards: rewardApplication.didApplyRewards,
            appliedInventoryCounts: rewardApplication.appliedInventoryCounts,
            dropNotificationBatches: resolvedUpdates.compactMap(Self.dropNotificationBatch(from:))
        )
    }

    private func makeInitialSession(
        runStart: ConfiguredRunStart,
        startedAt: Date,
        maximumLoopCount: Int,
        masterData: MasterData
    ) async throws -> RunSessionRecord {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == runStart.labyrinthId }) else {
            throw ExplorationError.invalidLabyrinth(labyrinthId: runStart.labyrinthId)
        }

        let startContext = try await coreDataStore.loadStartContext(
            partyId: runStart.partyId,
            labyrinthId: labyrinth.id,
            requestedDifficultyTitleId: runStart.selectedDifficultyTitleId,
            masterData: masterData
        )
        let skillTable = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        let memberStatuses = try startContext.partyMembers.map { member in
            guard let status = CharacterDerivedStatsCalculator.status(
                for: member,
                masterData: masterData
            ) else {
                throw ExplorationError.invalidRunMember(characterId: member.characterId)
            }
            return status
        }
        func rewardMultiplier(for skillIds: [Int], target: String) -> Double {
            skillIds.reduce(into: 1.0) { partialResult, skillId in
                guard let skill = skillTable[skillId] else {
                    return
                }

                for effect in skill.effects where effect.kind == .rewardMultiplier && effect.target == target {
                    guard let value = effect.value else {
                        continue
                    }
                    partialResult *= value
                }
            }
        }

        let memberExperienceMultipliers = memberStatuses.map { status in
            rewardMultiplier(for: status.skillIds, target: "experience")
        }
        let partyAverageLuck = memberStatuses.isEmpty
            ? 0
            : Double(memberStatuses.reduce(into: 0) { partialResult, status in
                partialResult += status.baseStats.luck
            }) / Double(memberStatuses.count)
        var rootSeed = startedAt.timeIntervalSinceReferenceDate.bitPattern
        rootSeed ^= UInt64(runStart.partyId) &* 0x9e3779b97f4a7c15
        rootSeed ^= UInt64(startContext.nextPartyRunId) &* 0xbf58476d1ce4e5b9

        return RunSessionRecord(
            partyRunId: startContext.nextPartyRunId,
            partyId: runStart.partyId,
            labyrinthId: labyrinth.id,
            selectedDifficultyTitleId: startContext.selectedDifficultyTitleId,
            targetFloorNumber: labyrinth.floors.last?.floorNumber ?? 1,
            startedAt: startedAt,
            rootSeed: rootSeed,
            maximumLoopCount: maximumLoopCount,
            memberSnapshots: startContext.partyMembers,
            memberCharacterIds: startContext.partyMembers.map(\.characterId),
            completedBattleCount: 0,
            currentPartyHPs: startContext.partyMembers.map(\.currentHP),
            memberExperienceMultipliers: memberExperienceMultipliers,
            goldMultiplier: memberStatuses.reduce(into: 1.0) { partialResult, status in
                partialResult *= rewardMultiplier(for: status.skillIds, target: "gold")
            },
            rareDropMultiplier: memberStatuses.reduce(into: 1.0) { partialResult, status in
                partialResult *= rewardMultiplier(for: status.skillIds, target: "rareDrop")
            },
            titleDropMultiplier: memberStatuses.reduce(into: 1.0) { partialResult, status in
                partialResult *= rewardMultiplier(for: status.skillIds, target: "titleDrop")
            },
            partyAverageLuck: partyAverageLuck,
            latestBattleFloorNumber: nil,
            latestBattleNumber: nil,
            latestBattleOutcome: nil,
            battleLogs: [],
            goldBuffer: 0,
            experienceRewards: [],
            dropRewards: [],
            completion: nil
        )
    }

    private static func dropNotificationBatch(
        from update: (currentSession: RunSessionRecord, resolvedSession: RunSessionRecord)
    ) -> ExplorationDropNotificationBatch? {
        let currentBattleCount = update.currentSession.completedBattleCount
        let resolvedBattleCount = update.resolvedSession.completedBattleCount
        guard resolvedBattleCount > currentBattleCount else {
            return nil
        }

        let revealedDropRewards = update.resolvedSession.dropRewards.filter { reward in
            reward.sourceBattleNumber > currentBattleCount
                && reward.sourceBattleNumber <= resolvedBattleCount
        }
        guard !revealedDropRewards.isEmpty else {
            return nil
        }

        return ExplorationDropNotificationBatch(
            partyId: update.resolvedSession.partyId,
            dropRewards: revealedDropRewards
        )
    }
}
