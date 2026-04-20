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

nonisolated struct AutomaticRunResumeOutcome: Equatable, Sendable {
    let didApplyRewards: Bool
    let appliedInventoryCounts: [CompositeItemID: Int]
    let appliedShopInventoryCounts: [CompositeItemID: Int]
    let dropNotificationBatches: [ExplorationDropNotificationBatch]
}

nonisolated struct AutomaticRunResumeStep: Equatable, Sendable {
    let completedRun: RunSessionRecord
    let outcome: AutomaticRunResumeOutcome
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
                    partyRunId: plannedSession.session.partyRunId,
                    partyId: plannedSession.session.partyId,
                    labyrinthId: plannedSession.session.labyrinthId,
                    selectedDifficultyTitleId: plannedSession.session.selectedDifficultyTitleId,
                    targetFloorNumber: plannedSession.session.targetFloorNumber,
                    startedAt: plannedSession.session.startedAt,
                    rootSeed: plannedSession.session.rootSeed,
                    memberSnapshots: plannedSession.session.memberSnapshots,
                    memberCharacterIds: plannedSession.session.memberCharacterIds,
                    totalBattleCount: plannedSession.session.totalBattleCount,
                    completedBattleCount: 0,
                    currentPartyHPs: plannedSession.session.memberSnapshots.map(\.currentHP),
                    memberExperienceMultipliers: plannedSession.session.memberExperienceMultipliers,
                    progressIntervalMultiplier: plannedSession.session.progressIntervalMultiplier,
                    goldMultiplier: plannedSession.session.goldMultiplier,
                    rareDropMultiplier: plannedSession.session.rareDropMultiplier,
                    partyAverageLuck: plannedSession.session.partyAverageLuck,
                    latestBattleFloorNumber: nil,
                    latestBattleNumber: nil,
                    latestBattleOutcome: nil,
                    goldBuffer: plannedSession.session.goldBuffer,
                    experienceRewards: plannedSession.session.experienceRewards,
                    dropRewards: plannedSession.session.dropRewards,
                    completion: nil
                ),
                battleLogs: plannedSession.battleLogs,
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
        let progressContexts = try await coreDataRepository.loadSnapshot().runs
        let resolvedProgress = try await resolveProgress(
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

    func resumeAutomaticRun(
        partyId: Int,
        labyrinthId: Int,
        selectedDifficultyTitleId: Int,
        startedAt: Date,
        catTicketUsage: CatTicketUsage,
        reopenedAt: Date,
        masterData: MasterData
    ) async throws -> AutomaticRunResumeStep? {
        guard startedAt < reopenedAt else {
            return nil
        }

        let availableCatTicketCount = try await coreDataRepository.loadCatTicketCount()
        let appliesCatTicket: Bool
        switch catTicketUsage {
        case .never:
            appliesCatTicket = false
        case .automaticIfAvailable:
            appliesCatTicket = availableCatTicketCount > 0
        case .required:
            guard availableCatTicketCount > 0 else {
                throw ExplorationError.insufficientCatTickets
            }
            appliesCatTicket = true
        }

        let initialSession = try await makeInitialSession(
            runStart: ConfiguredRunStart(
                partyId: partyId,
                labyrinthId: labyrinthId,
                selectedDifficultyTitleId: selectedDifficultyTitleId,
                catTicketUsage: catTicketUsage
            ),
            startedAt: startedAt,
            appliesCatTicket: appliesCatTicket,
            masterData: masterData
        )
        let plannedSession = try await Self.planSession(
            initialSession,
            masterData: masterData,
            cachedStatuses: [:]
        )
        guard let completion = plannedSession.session.completion,
              completion.completedAt <= reopenedAt else {
            return nil
        }

        try await coreDataRepository.insertRun(
            plannedSession.session,
            battleLogs: plannedSession.battleLogs,
            consumesCatTicket: appliesCatTicket
        )

        let rewardApplication = try await coreDataRepository.commitProgressUpdates(
            [(currentSession: plannedSession.session, resolvedSession: plannedSession.session)],
            masterData: masterData
        )
        return AutomaticRunResumeStep(
            completedRun: plannedSession.session,
            outcome: AutomaticRunResumeOutcome(
                didApplyRewards: rewardApplication.didApplyRewards,
                appliedInventoryCounts: rewardApplication.appliedInventoryCounts,
                appliedShopInventoryCounts: rewardApplication.appliedShopInventoryCounts,
                dropNotificationBatches: Self.completedRunDropNotificationBatch(from: plannedSession.session).map { [$0] } ?? []
            )
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
    ) async throws -> PlannedExplorationRun {
        var cachedStatuses = cachedStatuses
        return try ExplorationResolver.plan(
            session: initialSession,
            masterData: masterData,
            cachedStatuses: &cachedStatuses
        )
    }

    private func resolveProgress(
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
                // rebuilt from summary plus the newly visible battle snapshot only.
                resolvedSession = try await revealProgress(
                    currentSession,
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
            runs.append(resolvedSession)
        }

        return ResolvedRunProgress(runs: runs, updates: updates)
    }

    private func revealProgress(
        _ session: RunSessionRecord,
        upTo currentDate: Date,
        masterData: MasterData
    ) async throws -> RunSessionRecord {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == session.labyrinthId }) else {
            throw ExplorationError.invalidLabyrinth(labyrinthId: session.labyrinthId)
        }

        let interval = session.progressIntervalSeconds(baseIntervalSeconds: labyrinth.progressIntervalSeconds)
        let revealedBattleCount = min(
            max(Int(currentDate.timeIntervalSince(session.startedAt) / interval), 0),
            session.totalBattleCount
        )
        guard revealedBattleCount > session.completedBattleCount else {
            return session
        }

        let latestBattle = try await coreDataRepository.loadBattleLogIndexEntries(
            partyId: session.partyId,
            partyRunId: session.partyRunId,
            battleIndex: revealedBattleCount - 1,
            count: 1
        )
        guard let latestBattle = latestBattle.first else {
            throw ExplorationError.runNotFound(
                partyId: session.partyId,
                partyRunId: session.partyRunId
            )
        }

        let completionReason: RunCompletionReason = switch latestBattle.result {
        case .victory:
            .cleared
        case .defeat:
            .defeated
        case .draw:
            .draw
        }

        return RunSessionRecord(
            partyRunId: session.partyRunId,
            partyId: session.partyId,
            labyrinthId: session.labyrinthId,
            selectedDifficultyTitleId: session.selectedDifficultyTitleId,
            targetFloorNumber: session.targetFloorNumber,
            startedAt: session.startedAt,
            rootSeed: session.rootSeed,
            memberSnapshots: session.memberSnapshots,
            memberCharacterIds: session.memberCharacterIds,
            totalBattleCount: session.totalBattleCount,
            completedBattleCount: revealedBattleCount,
            currentPartyHPs: latestBattle.currentPartyHPs,
            memberExperienceMultipliers: session.memberExperienceMultipliers,
            progressIntervalMultiplier: session.progressIntervalMultiplier,
            goldMultiplier: session.goldMultiplier,
            rareDropMultiplier: session.rareDropMultiplier,
            partyAverageLuck: session.partyAverageLuck,
            latestBattleFloorNumber: latestBattle.floorNumber,
            latestBattleNumber: latestBattle.battleNumber,
            latestBattleOutcome: latestBattle.result,
            goldBuffer: session.goldBuffer,
            experienceRewards: session.experienceRewards,
            dropRewards: session.dropRewards,
            completion: revealedBattleCount == session.totalBattleCount
                ? RunCompletionRecord(
                    completedAt: ExplorationResolver.completionDate(
                        startedAt: session.startedAt,
                        interval: interval,
                        completedBattleCount: revealedBattleCount
                    ),
                    reason: completionReason,
                    gold: session.goldBuffer,
                    experienceRewards: session.experienceRewards,
                    dropRewards: session.dropRewards
                )
                : nil
        )
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
        func explorationRuleProduct(for skillIds: [Int], target: ExplorationRuleTarget) -> Double {
            Set(skillIds).reduce(into: 1.0) { partialResult, skillId in
                guard let skill = skillTable[skillId] else {
                    return
                }

                for effect in skill.effects {
                    guard case let .explorationRule(effectTarget, value, _) = effect,
                          effectTarget == target else {
                        continue
                    }
                    partialResult *= value
                }
            }
        }

        let partyRewardSkillIds = memberStatuses.flatMap(\.skillIds)
        let memberExperienceMultipliers = memberStatuses.map { status in
            let baseMultiplier = status.rewardMultiplier(for: .experienceGainMultiplier)
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
            totalBattleCount: 0,
            completedBattleCount: 0,
            currentPartyHPs: startContext.partyMembers.map(\.currentHP),
            memberExperienceMultipliers: memberExperienceMultipliers,
            progressIntervalMultiplier: (
                appliesCatTicket
                    ? Self.catTicketProgressIntervalMultiplier
                    : 1.0
            ) * explorationRuleProduct(for: partyRewardSkillIds, target: .explorationTimeMultiplier),
            goldMultiplier: ExplorationResolver.rewardMultiplier(
                target: .goldGainMultiplier,
                skillIds: partyRewardSkillIds,
                skillTable: skillTable
            )
                * (appliesCatTicket ? Self.catTicketRewardMultiplier : 1.0),
            rareDropMultiplier: ExplorationResolver.rewardMultiplier(
                target: .rareDropMultiplier,
                skillIds: partyRewardSkillIds,
                skillTable: skillTable
            )
                * (appliesCatTicket ? Self.catTicketRewardMultiplier : 1.0),
            partyAverageLuck: partyAverageLuck,
            latestBattleFloorNumber: nil,
            latestBattleNumber: nil,
            latestBattleOutcome: nil,
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

    private static func completedRunDropNotificationBatch(
        from session: RunSessionRecord
    ) -> ExplorationDropNotificationBatch? {
        guard let completion = session.completion,
              !completion.dropRewards.isEmpty else {
            return nil
        }

        return ExplorationDropNotificationBatch(
            partyId: session.partyId,
            dropRewards: completion.dropRewards
        )
    }
}
