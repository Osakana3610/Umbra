// Coordinates exploration progression and reward application over Core Data-backed snapshots.

import Foundation

nonisolated private struct ResolvedRunUpdate: Sendable {
    let currentSession: RunSessionRecord
    let resolvedSession: RunSessionRecord
}

nonisolated private struct ResolvedRunProgress: Sendable {
    let runs: [RunSessionRecord]
    let updates: [ResolvedRunUpdate]
}

final class ExplorationSessionService {
    private let coreDataRepository: ExplorationCoreDataRepository
    nonisolated private static let catTicketRewardMultiplier = 2.0
    nonisolated private static let catTicketProgressIntervalMultiplier = 0.5

    init(coreDataRepository: ExplorationCoreDataRepository) {
        self.coreDataRepository = coreDataRepository
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
            return try await coreDataRepository.loadSnapshot()
        }

        var remainingCatTicketCount = try await coreDataRepository.loadCatTicketCount()

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
            let cachedStatuses: [Int: ExplorationMemberStatusCacheEntry] = [:]
            // Status caches are scoped per planned run so repeated character calculations inside
            // planning do not recompute the same derived stats for one party setup.
            let initialSession = try await makeInitialSession(
                runStart: runStart,
                startedAt: startedAt,
                appliesCatTicket: appliesCatTicket,
                masterData: masterData
            )
            let plannedSession = try await Self.planSession(
                initialSession,
                masterData: masterData,
                cachedStatuses: cachedStatuses
            )
            try await coreDataRepository.insertRun(
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

        return try await coreDataRepository.loadSnapshot()
    }

    func refreshRuns(
        at currentDate: Date,
        masterData: MasterData
    ) async throws -> ExplorationRunSnapshot {
        let progressContexts = try await coreDataRepository.loadProgressContexts()
        let resolvedProgress = try await Self.resolveProgress(
            progressContexts,
            at: currentDate,
            masterData: masterData
        )

        let rewardApplication = try await coreDataRepository.commitProgressUpdates(
            resolvedProgress.updates.map { update in
                (currentSession: update.currentSession, resolvedSession: update.resolvedSession)
            },
            masterData: masterData
        )

        return ExplorationRunSnapshot(
            runs: resolvedProgress.runs,
            didApplyRewards: rewardApplication.didApplyRewards,
            appliedInventoryCounts: rewardApplication.appliedInventoryCounts,
            appliedShopInventoryCounts: rewardApplication.appliedShopInventoryCounts,
            dropNotificationBatches: resolvedProgress.updates.compactMap(Self.dropNotificationBatch(from:))
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

        let startContext = try await coreDataRepository.loadStartContext(
            partyId: runStart.partyId,
            labyrinthId: labyrinth.id,
            requestedDifficultyTitleId: runStart.selectedDifficultyTitleId,
            masterData: masterData
        )
        return try await Self.buildInitialSession(
            runStart: runStart,
            startedAt: startedAt,
            appliesCatTicket: appliesCatTicket,
            labyrinth: labyrinth,
            startContext: startContext,
            masterData: masterData
        )
    }

    @concurrent
    nonisolated private static func planSession(
        _ initialSession: RunSessionRecord,
        masterData: MasterData,
        cachedStatuses: [Int: ExplorationMemberStatusCacheEntry]
    ) async throws -> RunSessionRecord {
        var cachedStatuses = cachedStatuses
        return try ExplorationResolver.plan(
            session: initialSession,
            masterData: masterData,
            cachedStatuses: &cachedStatuses
        )
    }

    @concurrent
    nonisolated private static func resolveProgress(
        _ progressContexts: [RunSessionRecord],
        at currentDate: Date,
        masterData: MasterData
    ) async throws -> ResolvedRunProgress {
        var runs: [RunSessionRecord] = []
        runs.reserveCapacity(progressContexts.count)
        var updates: [ResolvedRunUpdate] = []
        updates.reserveCapacity(progressContexts.count)

        for currentSession in progressContexts {
            let resolvedSession: RunSessionRecord
            if currentSession.completion == nil {
                // Active runs are revealed up to the requested wall-clock time; completed runs are
                // passed through unchanged to avoid re-resolving rewards.
                resolvedSession = try ExplorationResolver.reveal(
                    session: currentSession,
                    upTo: currentDate,
                    masterData: masterData
                )
            } else {
                resolvedSession = currentSession
            }

            updates.append(
                ResolvedRunUpdate(
                    currentSession: currentSession,
                    resolvedSession: resolvedSession
                )
            )
            runs.append(resolvedSession.completion == nil ? resolvedSession.summaryRecord : resolvedSession)
        }

        return ResolvedRunProgress(runs: runs, updates: updates)
    }

    @concurrent
    nonisolated private static func buildInitialSession(
        runStart: ConfiguredRunStart,
        startedAt: Date,
        appliesCatTicket: Bool,
        labyrinth: MasterData.Labyrinth,
        startContext: (nextPartyRunId: Int, partyMembers: [CharacterRecord], selectedDifficultyTitleId: Int),
        masterData: MasterData
    ) async throws -> RunSessionRecord {
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
        func explorationRuleProduct(for skillIds: [Int], target: String) -> Double {
            Set(skillIds).reduce(into: 1.0) { partialResult, skillId in
                guard let skill = skillTable[skillId] else {
                    return
                }

                for effect in skill.effects where effect.kind == .explorationRule && effect.target == target {
                    guard let value = effect.value else {
                        continue
                    }
                    partialResult *= value
                }
            }
        }

        let partyRewardSkillIds = memberStatuses.flatMap(\.skillIds)
        let memberExperienceMultipliers = memberStatuses.map { status in
            let baseMultiplier = status.rewardMultiplier(for: "experienceGainMultiplier")
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
            progressIntervalMultiplier: (
                appliesCatTicket
                    ? Self.catTicketProgressIntervalMultiplier
                    : 1.0
            ) * explorationRuleProduct(for: partyRewardSkillIds, target: "explorationTimeMultiplier"),
            goldMultiplier: ExplorationResolver.rewardMultiplier(
                target: "goldGainMultiplier",
                skillIds: partyRewardSkillIds,
                skillTable: skillTable
            )
                * (appliesCatTicket ? Self.catTicketRewardMultiplier : 1.0),
            rareDropMultiplier: ExplorationResolver.rewardMultiplier(
                target: "rareDropMultiplier",
                skillIds: partyRewardSkillIds,
                skillTable: skillTable
            )
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
        from update: ResolvedRunUpdate
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
