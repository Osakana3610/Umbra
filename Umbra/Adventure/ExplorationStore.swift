// Owns adventure run state and coordinates deterministic sortie starts and progress refreshes for SwiftUI.

import Foundation
import Observation

@MainActor
@Observable
final class ExplorationStore {
    private let repository: ExplorationRepository

    private(set) var isLoaded = false
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var runs: [RunSessionRecord] = []

    init(repository: ExplorationRepository) {
        self.repository = repository
    }

    func loadIfNeeded() {
        guard !isLoaded else {
            return
        }

        reload()
    }

    func reload() {
        lastOperationError = nil

        do {
            applySnapshot(try repository.loadSnapshot())
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    @discardableResult
    func refreshProgress(
        at currentDate: Date,
        masterData: MasterData
    ) -> Bool {
        guard !isMutating else {
            return false
        }

        lastOperationError = nil

        do {
            let snapshot = try repository.refreshRuns(at: currentDate, masterData: masterData)
            applySnapshot(snapshot)
            return snapshot.didApplyRewards
        } catch {
            lastOperationError = Self.errorMessage(for: error)
            return false
        }
    }

    func startRun(
        partyId: Int,
        labyrinthId: Int,
        startedAt: Date,
        masterData: MasterData
    ) {
        mutate {
            try repository.startRun(
                partyId: partyId,
                labyrinthId: labyrinthId,
                startedAt: startedAt,
                maximumLoopCount: 1,
                masterData: masterData
            )
        }
    }

    func startRuns(
        partyIds: [Int],
        labyrinthId: Int,
        startedAt: Date,
        masterData: MasterData
    ) {
        guard !partyIds.isEmpty else {
            return
        }

        mutate {
            for partyId in partyIds {
                _ = try repository.startRun(
                    partyId: partyId,
                    labyrinthId: labyrinthId,
                    startedAt: startedAt,
                    maximumLoopCount: 1,
                    masterData: masterData
                )
            }
            return try repository.loadSnapshot()
        }
    }

    func status(for partyId: Int) -> ExplorationPartyStatus {
        let partyRuns = runs.filter { $0.partyId == partyId }
        return ExplorationPartyStatus(
            activeRun: partyRuns.first(where: { !$0.isCompleted }),
            latestCompletedRun: partyRuns.first(where: \.isCompleted)
        )
    }

    func hasActiveRun(for partyId: Int) -> Bool {
        status(for: partyId).activeRun != nil
    }

    private func mutate(
        _ operation: () throws -> ExplorationRunSnapshot
    ) {
        guard !isMutating else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            applySnapshot(try operation())
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
