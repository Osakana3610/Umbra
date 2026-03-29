// Holds guild-facing player and character state in memory for the UI.

import Foundation
import Observation

@MainActor
@Observable
final class GuildStore {
    enum Phase {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let repository: GuildRepository
    private(set) var phase: Phase
    private(set) var playerState: PlayerState?
    private(set) var charactersById: [Int: CharacterRecord]
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var lastHireMessage: String?

    init(repository: GuildRepository) {
        self.repository = repository
        self.phase = .idle
        self.playerState = nil
        self.charactersById = [:]
    }

    init(phase: Phase, repository: GuildRepository) {
        self.repository = repository
        self.phase = phase
        self.playerState = nil
        self.charactersById = [:]
    }

    var characters: [CharacterRecord] {
        charactersById.values.sorted { $0.characterId < $1.characterId }
    }

    func loadIfNeeded() async {
        switch phase {
        case .idle, .failed:
            await reload()
        case .loading, .loaded:
            return
        }
    }

    func reload() async {
        guard !isLoading else {
            return
        }

        phase = .loading
        playerState = nil
        charactersById = [:]
        lastOperationError = nil

        do {
            let loadedPlayerState = try repository.loadPlayerState()
            let loadedCharacters = try repository.loadCharacters()
            playerState = loadedPlayerState
            charactersById = Dictionary(
                uniqueKeysWithValues: loadedCharacters.map { ($0.characterId, $0) }
            )
            phase = .loaded
        } catch {
            phase = .failed(Self.errorMessage(for: error))
        }
    }

    func hireCharacter(
        raceId: Int,
        jobId: Int,
        aptitudeId: Int,
        masterData: MasterData
    ) async {
        guard !isMutating,
              case .loaded = phase else {
            return
        }

        isMutating = true
        lastOperationError = nil
        lastHireMessage = nil
        defer { isMutating = false }

        do {
            let result = try repository.hireCharacter(
                raceId: raceId,
                jobId: jobId,
                aptitudeId: aptitudeId,
                masterData: masterData
            )
            playerState = result.playerState
            charactersById[result.character.characterId] = result.character
            phase = .loaded
            lastHireMessage = "\(result.character.name)を雇用しました。"
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func hirePrice(raceId: Int, jobId: Int, masterData: MasterData) -> Int? {
        GuildHiring.price(raceId: raceId, jobId: jobId, masterData: masterData)
    }

    private var isLoading: Bool {
        if case .loading = phase {
            return true
        }

        return false
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
