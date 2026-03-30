// Owns adventure run state and coordinates deterministic sortie starts and progress refreshes for SwiftUI.

import Foundation
import Observation

struct ConfiguredRunStart: Sendable {
    let partyId: Int
    let labyrinthId: Int
}

@MainActor
@Observable
final class ExplorationStore {
    private let coreDataStore: ExplorationCoreDataStore
    private let service: ExplorationSessionService
    private let itemDropNotificationService: ItemDropNotificationService

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var runs: [RunSessionRecord] = []
    private var isRefreshingProgress = false
    private var progressRefreshTask: Task<Void, Never>?

    init(
        coreDataStore: ExplorationCoreDataStore,
        itemDropNotificationService: ItemDropNotificationService
    ) {
        self.coreDataStore = coreDataStore
        self.itemDropNotificationService = itemDropNotificationService
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
        startedAt: Date,
        masterData: MasterData
    ) async {
        await mutate(masterData: masterData) {
            try await service.startRun(
                partyId: partyId,
                labyrinthId: labyrinthId,
                startedAt: startedAt,
                maximumLoopCount: 1,
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
                maximumLoopCount: 1,
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

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}
