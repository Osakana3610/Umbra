// Owns adventure run state and coordinates deterministic sortie starts and progress refreshes for SwiftUI.

import Foundation
import Observation

struct ConfiguredRunStart: Sendable {
    let partyId: Int
    let labyrinthId: Int
    let selectedDifficultyTitleId: Int
}

@MainActor
@Observable
final class ExplorationStore {
    private let coreDataStore: ExplorationCoreDataStore
    private let service: ExplorationSessionService
    private let itemDropNotificationService: ItemDropNotificationService
    private let rosterStore: GuildRosterStore?

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var runs: [RunSessionRecord] = []
    private var isRefreshingProgress = false
    private var isResumingAutomaticRuns = false
    private var progressRefreshTask: Task<Void, Never>?
    private var retentionPruneTask: Task<Void, Never>?

    var isSortieLocked: Bool {
        isMutating || isResumingAutomaticRuns
    }

    init(
        coreDataStore: ExplorationCoreDataStore,
        itemDropNotificationService: ItemDropNotificationService,
        rosterStore: GuildRosterStore? = nil
    ) {
        self.coreDataStore = coreDataStore
        self.itemDropNotificationService = itemDropNotificationService
        self.rosterStore = rosterStore
        service = ExplorationSessionService(coreDataStore: coreDataStore)
    }

    func loadIfNeeded(masterData: MasterData) async {
        guard !isLoaded else {
            scheduleProgressRefresh(using: masterData)
            return
        }

        await reload(masterData: masterData)
    }

    func reload(masterData: MasterData) async {
        lastOperationError = nil

        do {
            applySnapshot(
                try await coreDataStore.loadSnapshot(),
                masterData: masterData
            )
            scheduleCompletedRunRetentionPrune(using: masterData)
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    @discardableResult
    func refreshProgress(
        at currentDate: Date,
        masterData: MasterData
    ) async -> (didApplyRewards: Bool, appliedInventoryCounts: [CompositeItemID: Int]) {
        // Progress refresh is serialized so one timer tick, foreground refresh, or resume flow
        // cannot apply the same deterministic rewards twice.
        guard !isMutating,
              !isRefreshingProgress,
              runs.contains(where: { !$0.isCompleted }) else {
            return (false, [:])
        }

        isRefreshingProgress = true
        lastOperationError = nil
        defer { isRefreshingProgress = false }

        do {
            let snapshot = try await service.refreshRuns(at: currentDate, masterData: masterData)
            applySnapshot(snapshot, masterData: masterData)
            if snapshot.didApplyRewards {
                rosterStore?.refreshFromPersistence()
            }
            itemDropNotificationService.publish(batches: snapshot.dropNotificationBatches)
            return (snapshot.didApplyRewards, snapshot.appliedInventoryCounts)
        } catch {
            lastOperationError = Self.errorMessage(for: error)
            return (false, [:])
        }
    }

    func startRun(
        partyId: Int,
        labyrinthId: Int,
        selectedDifficultyTitleId: Int,
        startedAt: Date,
        masterData: MasterData
    ) async {
        await mutate(masterData: masterData) {
            try await service.startRun(
                partyId: partyId,
                labyrinthId: labyrinthId,
                selectedDifficultyTitleId: selectedDifficultyTitleId,
                startedAt: startedAt,
                masterData: masterData
            )
        }
    }

    func startConfiguredRuns(
        _ runsToStart: [ConfiguredRunStart],
        startedAt: Date,
        masterData: MasterData
    ) async {
        guard !runsToStart.isEmpty else {
            return
        }

        await mutate(masterData: masterData) {
            try await service.startConfiguredRuns(
                runsToStart,
                startedAt: startedAt,
                masterData: masterData
            )
        }
    }

    func recordBackgroundedAt(
        _ date: Date,
        guildService: GuildService
    ) {
        do {
            try guildService.recordBackgroundedAt(date)
            rosterStore?.refreshFromPersistence()
            lastOperationError = nil
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func resumeBackgroundProgress(
        reopenedAt: Date,
        partyStore: PartyStore,
        guildService: GuildService,
        masterData: MasterData
    ) async {
        guard !isResumingAutomaticRuns else {
            return
        }

        isResumingAutomaticRuns = true
        defer { isResumingAutomaticRuns = false }

        // Resume first synchronizes any in-flight runs, then reconstructs queued automatic runs
        // from the saved background timestamp before starting them one by one.
        rosterStore?.refreshFromPersistence()
        partyStore.reload()
        await reload(masterData: masterData)
        _ = await refreshProgress(
            at: reopenedAt,
            masterData: masterData
        )
        guard lastOperationError == nil else {
            return
        }

        do {
            try guildService.queueAutomaticRunsForResume(
                reopenedAt: reopenedAt,
                masterData: masterData
            )
            rosterStore?.refreshFromPersistence()
            partyStore.reload()
        } catch {
            lastOperationError = Self.errorMessage(for: error)
            return
        }

        while let pendingRun = nextPendingAutomaticRun(
            partyStore: partyStore,
            masterData: masterData
        ) {
            // Automatic runs are consumed sequentially so each completion can update persisted
            // HP, rewards, and unlock state before the next queued sortie is started.
            await startRun(
                partyId: pendingRun.partyId,
                labyrinthId: pendingRun.labyrinthId,
                selectedDifficultyTitleId: pendingRun.selectedDifficultyTitleId,
                startedAt: pendingRun.startedAt,
                masterData: masterData
            )
            guard lastOperationError == nil else {
                return
            }

            do {
                try guildService.consumePendingAutomaticRun(partyId: pendingRun.partyId)
                partyStore.reload()
            } catch {
                lastOperationError = Self.errorMessage(for: error)
                return
            }

            _ = await refreshProgress(
                at: reopenedAt,
                masterData: masterData
            )
            guard lastOperationError == nil else {
                return
            }
        }
    }

    func status(for partyId: Int) -> ExplorationPartyStatus {
        let partyRuns = runs.filter { $0.partyId == partyId }
        return ExplorationPartyStatus(
            activeRun: partyRuns.first(where: { !$0.isCompleted }),
            latestCompletedRun: partyRuns.first(where: \.isCompleted)
        )
    }

    func loadRunDetail(
        partyId: Int,
        partyRunId: Int
    ) async -> RunSessionRecord? {
        do {
            return try await coreDataStore.loadRunDetail(
                partyId: partyId,
                partyRunId: partyRunId
            )
        } catch {
            lastOperationError = Self.errorMessage(for: error)
            return nil
        }
    }

    func hasActiveRun(for partyId: Int) -> Bool {
        status(for: partyId).activeRun != nil
    }

    func hasActiveRun(forCharacterId characterId: Int) -> Bool {
        runs.contains { !$0.isCompleted && $0.memberCharacterIds.contains(characterId) }
    }

    func enforceCompletedRunRetention(masterData: MasterData) {
        guard isLoaded else {
            return
        }

        scheduleCompletedRunRetentionPrune(using: masterData)
    }

    private func mutate(
        masterData: MasterData,
        _ operation: () async throws -> ExplorationRunSnapshot
    ) async {
        guard !isMutating else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            // Mutations always replace the full snapshot returned by the service so the UI does
            // not mix stale run lists with freshly persisted progress.
            applySnapshot(try await operation(), masterData: masterData)
            rosterStore?.refreshFromPersistence()
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    private func applySnapshot(
        _ snapshot: ExplorationRunSnapshot,
        masterData: MasterData
    ) {
        runs = snapshot.runs
        isLoaded = true
        scheduleProgressRefresh(using: masterData)
    }

    private func scheduleProgressRefresh(using masterData: MasterData) {
        progressRefreshTask?.cancel()

        guard let nextProgressDate = nextProgressDate(using: masterData) else {
            progressRefreshTask = nil
            return
        }

        progressRefreshTask = Task { [weak self] in
            let delay = max(nextProgressDate.timeIntervalSinceNow, 0)
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled,
                  let self else {
                return
            }

            // The timer re-checks progress against the current wall clock at fire time so resumed
            // apps do not rely on a stale captured date.
            _ = await self.refreshProgress(
                at: Date(),
                masterData: masterData
            )
        }
    }

    private func scheduleCompletedRunRetentionPrune(using masterData: MasterData) {
        retentionPruneTask?.cancel()
        retentionPruneTask = Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            do {
                // Retention pruning reloads only when rows were actually deleted, avoiding an
                // unnecessary full snapshot rebuild on every refresh.
                guard try await self.coreDataStore.pruneCompletedRunsExceedingRetentionLimit() else {
                    return
                }

                let snapshot = try await self.coreDataStore.loadSnapshot()
                guard !Task.isCancelled else {
                    return
                }

                self.applySnapshot(snapshot, masterData: masterData)
            } catch {
                return
            }
        }
    }

    private func nextProgressDate(using masterData: MasterData) -> Date? {
        runs
            .compactMap { run in
                guard run.completion == nil,
                      let labyrinth = masterData.labyrinths.first(where: { $0.id == run.labyrinthId }) else {
                    return nil
                }

                // Progress advances once per battle interval, so the next refresh time is derived
                // from the battle count already completed within the stored run.
                return run.startedAt.addingTimeInterval(
                    Double(labyrinth.progressIntervalSeconds * (run.completedBattleCount + 1))
                )
            }
            .min()
    }

    private func nextPendingAutomaticRun(
        partyStore: PartyStore,
        masterData: MasterData
    ) -> (partyId: Int, labyrinthId: Int, selectedDifficultyTitleId: Int, startedAt: Date)? {
        for party in partyStore.parties {
            guard party.pendingAutomaticRunCount > 0,
                  status(for: party.partyId).activeRun == nil,
                  let labyrinthId = party.selectedLabyrinthId,
                  masterData.labyrinths.contains(where: { $0.id == labyrinthId }) else {
                continue
            }

            // Automatic runs reuse the resolved highest unlocked difficulty instead of trusting a
            // stale saved party selection from before the app was backgrounded.
            let highestUnlockedDifficultyTitleId = rosterStore?.labyrinthProgressByLabyrinthId[labyrinthId]?
                .highestUnlockedDifficultyTitleId
            let selectedDifficultyTitleId = masterData.resolvedExplorationDifficultyTitleId(
                requestedTitleId: party.selectedDifficultyTitleId,
                highestUnlockedTitleId: highestUnlockedDifficultyTitleId
            )
            guard let startedAt = party.pendingAutomaticRunStartedAt
                ?? status(for: party.partyId).latestCompletedRun?.completion?.completedAt else {
                continue
            }
            return (
                partyId: party.partyId,
                labyrinthId: labyrinthId,
                selectedDifficultyTitleId: selectedDifficultyTitleId,
                startedAt: startedAt
            )
        }

        return nil
    }

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}
