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

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var runs: [RunSessionRecord] = []

    init(coreDataStore: ExplorationCoreDataStore) {
        self.coreDataStore = coreDataStore
        service = ExplorationSessionService(coreDataStore: coreDataStore)
    }

    func loadIfNeeded() async {
        guard !isLoaded else {
            return
        }

        await reload()
    }

    func reload() async {
        lastOperationError = nil

        do {
            applySnapshot(try await coreDataStore.loadSnapshot())
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
              runs.contains(where: { !$0.isCompleted }) else {
            return (false, [:])
        }

        lastOperationError = nil

        do {
            let snapshot = try await service.refreshRuns(at: currentDate, masterData: masterData)
            applySnapshot(snapshot)
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
        await mutate {
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

        await mutate {
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
        _ operation: () async throws -> ExplorationRunSnapshot
    ) async {
        guard !isMutating else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            applySnapshot(try await operation())
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    private func applySnapshot(_ snapshot: ExplorationRunSnapshot) {
        runs = snapshot.runs
        isLoaded = true
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
