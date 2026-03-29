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
        startedAt: Date,
        maximumLoopCount: Int,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        try await startConfiguredRuns(
            [ConfiguredRunStart(partyId: partyId, labyrinthId: labyrinthId)],
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
            guard let labyrinth = masterData.labyrinths.first(where: { $0.id == runStart.labyrinthId }) else {
                throw ExplorationError.invalidLabyrinth(labyrinthId: runStart.labyrinthId)
            }
            let startContext = try await coreDataStore.loadStartContext(partyId: runStart.partyId)
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
            let memberExperienceMultipliers = memberStatuses.map { status in
                var multiplier = 1.0
                for skillId in status.skillIds {
                    guard let skill = skillTable[skillId] else {
                        continue
                    }

                    for effect in skill.effects where effect.kind == .rewardMultiplier && effect.target == "experience" {
                        guard let value = effect.value else {
                            continue
                        }
                        multiplier *= value
                    }
                }
                return multiplier
            }
            let partyAverageLuck = memberStatuses.isEmpty
                ? 0
                : Double(memberStatuses.reduce(into: 0) { partialResult, status in
                    partialResult += status.baseStats.luck
                }) / Double(memberStatuses.count)
            var rootSeed = startedAt.timeIntervalSinceReferenceDate.bitPattern
            rootSeed ^= UInt64(runStart.partyId) &* 0x9e3779b97f4a7c15
            rootSeed ^= UInt64(startContext.nextPartyRunId) &* 0xbf58476d1ce4e5b9

            func combinedRewardMultiplier(target: String) -> Double {
                memberStatuses.reduce(into: 1.0) { partialResult, status in
                    for skillId in status.skillIds {
                        guard let skill = skillTable[skillId] else {
                            continue
                        }

                        for effect in skill.effects where effect.kind == .rewardMultiplier && effect.target == target {
                            guard let value = effect.value else {
                                continue
                            }
                            partialResult *= value
                        }
                    }
                }
            }

            let session = RunSessionRecord(
                partyRunId: startContext.nextPartyRunId,
                partyId: runStart.partyId,
                labyrinthId: labyrinth.id,
                targetFloorNumber: labyrinth.floors.last?.floorNumber ?? 1,
                startedAt: startedAt,
                rootSeed: rootSeed,
                maximumLoopCount: maximumLoopCount,
                memberCharacterIds: startContext.partyMembers.map(\.characterId),
                completedBattleCount: 0,
                currentPartyHPs: startContext.partyMembers.map(\.currentHP),
                memberExperienceMultipliers: memberExperienceMultipliers,
                goldMultiplier: combinedRewardMultiplier(target: "gold"),
                rareDropMultiplier: combinedRewardMultiplier(target: "rareDrop"),
                titleDropMultiplier: combinedRewardMultiplier(target: "titleDrop"),
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
            try await coreDataStore.insertRun(session)
        }

        return try await coreDataStore.loadSnapshot()
    }

    func refreshRuns(
        at currentDate: Date,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        let progressContexts = try await coreDataStore.loadProgressContexts()
        var didApplyRewards = false
        var appliedInventoryCounts: [CompositeItemID: Int] = [:]

        for progressContext in progressContexts {
            let currentSession = progressContext.session
            let session: RunSessionRecord
            if currentSession.completion == nil {
                session = try ExplorationResolver.resolve(
                    session: currentSession,
                    upTo: currentDate,
                    partyMembers: progressContext.livePartyMembers,
                    masterData: masterData
                )
            } else {
                session = currentSession
            }
            let rewardApplication = try await coreDataStore.commitProgressUpdate(
                currentSession: currentSession,
                resolvedSession: session,
                masterData: masterData
            )
            didApplyRewards = didApplyRewards || rewardApplication.didApplyRewards
            for (itemID, count) in rewardApplication.appliedInventoryCounts {
                appliedInventoryCounts[itemID, default: 0] += count
            }
        }

        let snapshot = try await coreDataStore.loadSnapshot()
        return ExplorationRunSnapshot(
            runs: snapshot.runs,
            didApplyRewards: didApplyRewards,
            appliedInventoryCounts: appliedInventoryCounts
        )
    }
}
