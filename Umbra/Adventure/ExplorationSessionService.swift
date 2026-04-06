// Coordinates exploration progression and reward application over Core Data-backed snapshots.

import Foundation

final class ExplorationSessionService {
    private let coreDataStore: ExplorationCoreDataStore
    private static let catTicketRewardMultiplier = 2.0
    private static let catTicketProgressIntervalMultiplier = 0.5

    init(coreDataStore: ExplorationCoreDataStore) {
        self.coreDataStore = coreDataStore
    }

    func startRun(
        partyId: Int,
        labyrinthId: Int,
        selectedDifficultyTitleId: Int,
        startedAt: Date,
        catTicketUsage: CatTicketUsage = .never,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        try await startConfiguredRuns(
            [
                ConfiguredRunStart(
                    partyId: partyId,
                    labyrinthId: labyrinthId,
                    selectedDifficultyTitleId: selectedDifficultyTitleId,
                    catTicketUsage: catTicketUsage
                )
            ],
            startedAt: startedAt,
            masterData: masterData
        )
    }

    func startConfiguredRuns(
        _ runsToStart: [ConfiguredRunStart],
        startedAt: Date,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        guard !runsToStart.isEmpty else {
            return try await coreDataStore.loadSnapshot()
        }

        var remainingCatTicketCount = try await coreDataStore.loadCatTicketCount()

        for runStart in runsToStart {
            let appliesCatTicket: Bool
            switch runStart.catTicketUsage {
            case .never:
                appliesCatTicket = false
            case .automaticIfAvailable:
                appliesCatTicket = remainingCatTicketCount > 0
            case .required:
                guard remainingCatTicketCount > 0 else {
                    throw ExplorationError.insufficientCatTickets
                }
                appliesCatTicket = true
            }
            var cachedStatuses: [Int: ExplorationMemberStatusCacheEntry] = [:]
            // Status caches are scoped per planned run so repeated character calculations inside
            // planning do not recompute the same derived stats for one party setup.
            let plannedSession = try ExplorationResolver.plan(
                session: try await makeInitialSession(
                    runStart: runStart,
                    startedAt: startedAt,
                    appliesCatTicket: appliesCatTicket,
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
                    memberSnapshots: plannedSession.memberSnapshots,
                    memberCharacterIds: plannedSession.memberCharacterIds,
                    completedBattleCount: 0,
                    currentPartyHPs: plannedSession.memberSnapshots.map(\.currentHP),
                    memberExperienceMultipliers: plannedSession.memberExperienceMultipliers,
                    progressIntervalMultiplier: plannedSession.progressIntervalMultiplier,
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
                ),
                consumesCatTicket: appliesCatTicket
            )
            if appliesCatTicket {
                remainingCatTicketCount -= 1
            }
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
                // Active runs are revealed up to the requested wall-clock time; completed runs are
                // passed through unchanged to avoid re-resolving rewards.
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
        appliesCatTicket: Bool,
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
            Set(skillIds).reduce(into: 1.0) { partialResult, skillId in
                guard let skill = skillTable[skillId] else {
                    return
                }

                for effect in skill.effects where effect.kind == .rewardMultiplier && effect.target == target {
                    guard let value = effect.value else {
                        continue
                    }
                    // Run-start reward multipliers are baked into the stored session so later
                    // progress refreshes do not have to recalculate them from mutable roster data.
                    switch effect.operation {
                    case "pctAdd":
                        partialResult *= 1.0 + value
                    case nil, "mul":
                        partialResult *= value
                    default:
                        continue
                    }
                }
            }
        }

        let partyRewardSkillIds = memberStatuses.flatMap(\.skillIds)
        let memberExperienceMultipliers = memberStatuses.map { status in
            let baseMultiplier = rewardMultiplier(for: status.skillIds, target: "experience")
            return appliesCatTicket
                ? baseMultiplier * Self.catTicketRewardMultiplier
                : baseMultiplier
        }
        let partyAverageLuck = memberStatuses.isEmpty
            ? 0
            : Double(memberStatuses.reduce(into: 0) { partialResult, status in
                partialResult += status.baseStats.luck
            }) / Double(memberStatuses.count)
        var rootSeed = startedAt.timeIntervalSinceReferenceDate.bitPattern
        rootSeed ^= UInt64(runStart.partyId) &* 0x9e3779b97f4a7c15
        rootSeed ^= UInt64(startContext.nextPartyRunId) &* 0xbf58476d1ce4e5b9

        // The root seed is derived from time, party, and party-run identity so one party can start
        // multiple deterministic runs without colliding with earlier sessions.
        return RunSessionRecord(
            partyRunId: startContext.nextPartyRunId,
            partyId: runStart.partyId,
            labyrinthId: labyrinth.id,
            selectedDifficultyTitleId: startContext.selectedDifficultyTitleId,
            targetFloorNumber: labyrinth.floors.last?.floorNumber ?? 1,
            startedAt: startedAt,
            rootSeed: rootSeed,
            memberSnapshots: startContext.partyMembers,
            memberCharacterIds: startContext.partyMembers.map(\.characterId),
            completedBattleCount: 0,
            currentPartyHPs: startContext.partyMembers.map(\.currentHP),
            memberExperienceMultipliers: memberExperienceMultipliers,
            progressIntervalMultiplier: appliesCatTicket
                ? Self.catTicketProgressIntervalMultiplier
                : 1.0,
            goldMultiplier: rewardMultiplier(for: partyRewardSkillIds, target: "gold")
                * (appliesCatTicket ? Self.catTicketRewardMultiplier : 1.0),
            rareDropMultiplier: rewardMultiplier(for: partyRewardSkillIds, target: "rareDrop")
                * (appliesCatTicket ? Self.catTicketRewardMultiplier : 1.0),
            titleDropMultiplier: rewardMultiplier(for: partyRewardSkillIds, target: "titleDrop")
                * (appliesCatTicket ? Self.catTicketRewardMultiplier : 1.0),
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

        // Notifications are limited to newly revealed drop rewards since the previous snapshot.
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
