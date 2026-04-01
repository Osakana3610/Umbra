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
    private static let automaticRunCatchUpLimit = 20

    private let coreDataStore: ExplorationCoreDataStore
    private let service: ExplorationSessionService
    private let itemDropNotificationService: ItemDropNotificationService
    private let rosterStore: GuildRosterStore?

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var runs: [RunSessionRecord] = []
    private var isRefreshingProgress = false
    private var isResumingIdleProgress = false
    private var progressRefreshTask: Task<Void, Never>?
    private var retentionPruneTask: Task<Void, Never>?

    var isSortieLocked: Bool {
        isMutating || isResumingIdleProgress
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

    @discardableResult
    func resumeIdleProgress(
        since checkpointDate: Date?,
        currentDate: Date,
        parties: [PartyRecord],
        masterData: MasterData
    ) async -> Bool {
        guard !isMutating,
              !isRefreshingProgress,
              !isResumingIdleProgress else {
            return false
        }

        guard let checkpointDate,
              checkpointDate < currentDate,
              let rosterStore else {
            return true
        }

        isResumingIdleProgress = true
        defer { isResumingIdleProgress = false }

        _ = await refreshProgress(at: currentDate, masterData: masterData)
        guard lastOperationError == nil else {
            return false
        }

        for party in parties {
            guard let runStart = automaticRunStart(for: party, masterData: masterData, rosterStore: rosterStore),
                  let runDurationSeconds = automaticRunDurationSeconds(
                    labyrinthId: runStart.labyrinthId,
                    masterData: masterData
                  ) else {
                continue
            }

            let availableAt = automaticRunAvailableAt(
                for: party.partyId,
                checkpointDate: checkpointDate
            )
            let automaticRunCount = min(
                Int(currentDate.timeIntervalSince(availableAt) / Double(runDurationSeconds)),
                Self.automaticRunCatchUpLimit
            )
            guard automaticRunCount > 0 else {
                continue
            }

            for automaticRunIndex in 0..<automaticRunCount {
                guard canAutomaticallyStartRun(for: party, rosterStore: rosterStore) else {
                    break
                }

                let startedAt = availableAt.addingTimeInterval(
                    Double(runDurationSeconds * automaticRunIndex)
                )
                await startRun(
                    partyId: runStart.partyId,
                    labyrinthId: runStart.labyrinthId,
                    selectedDifficultyTitleId: runStart.selectedDifficultyTitleId,
                    startedAt: startedAt,
                    masterData: masterData
                )
                guard lastOperationError == nil else {
                    return false
                }

                _ = await refreshProgress(at: currentDate, masterData: masterData)
                guard lastOperationError == nil else {
                    return false
                }
            }
        }

        return true
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

                return run.startedAt.addingTimeInterval(
                    Double(labyrinth.progressIntervalSeconds * (run.completedBattleCount + 1))
                )
            }
            .min()
    }

    private func automaticRunStart(
        for party: PartyRecord,
        masterData: MasterData,
        rosterStore: GuildRosterStore
    ) -> ConfiguredRunStart? {
        guard canAutomaticallyStartRun(for: party, rosterStore: rosterStore),
              let labyrinthId = configuredLabyrinthId(for: party, masterData: masterData),
              let selectedDifficultyTitleId = configuredDifficultyTitleId(
                for: party,
                masterData: masterData,
                rosterStore: rosterStore
              ) else {
            return nil
        }

        return ConfiguredRunStart(
            partyId: party.partyId,
            labyrinthId: labyrinthId,
            selectedDifficultyTitleId: selectedDifficultyTitleId
        )
    }

    private func automaticRunAvailableAt(
        for partyId: Int,
        checkpointDate: Date
    ) -> Date {
        let latestCompletionDate = runs
            .filter { $0.partyId == partyId }
            .compactMap { $0.completion?.completedAt }
            .max()

        return max(checkpointDate, latestCompletionDate ?? checkpointDate)
    }

    private func automaticRunDurationSeconds(
        labyrinthId: Int,
        masterData: MasterData
    ) -> Int? {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == labyrinthId }) else {
            return nil
        }

        let totalBattleCount = labyrinth.floors.reduce(0) { partialResult, floor in
            partialResult + floor.battleCount
        }
        guard totalBattleCount > 0 else {
            return nil
        }

        return totalBattleCount * labyrinth.progressIntervalSeconds
    }

    private func canAutomaticallyStartRun(
        for party: PartyRecord,
        rosterStore: GuildRosterStore
    ) -> Bool {
        guard !hasActiveRun(for: party.partyId),
              !party.memberCharacterIds.isEmpty else {
            return false
        }

        return party.memberCharacterIds.allSatisfy { characterId in
            (rosterStore.charactersById[characterId]?.currentHP ?? 0) > 0
        }
    }

    private func configuredLabyrinthId(
        for party: PartyRecord,
        masterData: MasterData
    ) -> Int? {
        guard let selectedLabyrinthId = party.selectedLabyrinthId,
              masterData.labyrinths.contains(where: { $0.id == selectedLabyrinthId }) else {
            return nil
        }

        return selectedLabyrinthId
    }

    private func configuredDifficultyTitleId(
        for party: PartyRecord,
        masterData: MasterData,
        rosterStore: GuildRosterStore
    ) -> Int? {
        guard let labyrinthId = configuredLabyrinthId(for: party, masterData: masterData) else {
            return nil
        }

        let highestUnlockedTitleId = rosterStore.labyrinthProgressByLabyrinthId[labyrinthId]?
            .highestUnlockedDifficultyTitleId
        return masterData.resolvedExplorationDifficultyTitleId(
            requestedTitleId: party.selectedDifficultyTitleId,
            highestUnlockedTitleId: highestUnlockedTitleId
        )
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
