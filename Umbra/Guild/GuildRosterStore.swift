// Owns player and character state for guild-facing UI without party or equipment cache responsibilities.

import Foundation
import Observation

@MainActor
@Observable
final class GuildRosterStore {
    private let repository: GuildRosterRepository

    private(set) var phase: StoreLoadPhase
    private(set) var playerState: PlayerState?
    private(set) var characters: [CharacterRecord]
    private(set) var charactersById: [Int: CharacterRecord]
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var lastHireMessage: String?

    init(repository: GuildRosterRepository) {
        self.repository = repository
        phase = .idle
        playerState = nil
        characters = []
        charactersById = [:]
    }

    init(phase: StoreLoadPhase, repository: GuildRosterRepository) {
        self.repository = repository
        self.phase = phase
        playerState = nil
        characters = []
        charactersById = [:]
    }

    func loadIfNeeded() {
        switch phase {
        case .idle, .failed:
            reload()
        case .loading, .loaded:
            return
        }
    }

    func reload() {
        if case .loading = phase {
            return
        }

        phase = .loading
        playerState = nil
        characters = []
        charactersById = [:]
        lastOperationError = nil
        lastHireMessage = nil

        do {
            let snapshot = try repository.loadSnapshot()
            playerState = snapshot.playerState
            applyCharacters(snapshot.characters)
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
    ) {
        guard !isMutating, phase == .loaded else {
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
            replaceCharacter(result.character)
            lastHireMessage = "\(result.character.name)を雇用しました。"
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func reviveCharacter(
        characterId: Int,
        masterData: MasterData
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            applySnapshot(
                try repository.reviveCharacter(
                    characterId: characterId,
                    masterData: masterData
                )
            )
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func reviveAllDefeated(masterData: MasterData) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            applySnapshot(try repository.reviveAllDefeated(masterData: masterData))
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func setAutoReviveDefeatedCharactersEnabled(
        _ isEnabled: Bool
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            applySnapshot(
                try repository.setAutoReviveDefeatedCharactersEnabled(isEnabled)
            )
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func replaceCharacter(_ character: CharacterRecord) {
        charactersById[character.characterId] = character

        if let index = characters.firstIndex(where: { $0.characterId == character.characterId }) {
            characters[index] = character
        } else if let insertIndex = characters.firstIndex(where: { $0.characterId > character.characterId }) {
            characters.insert(character, at: insertIndex)
        } else {
            characters.append(character)
        }
    }

    private func applyCharacters(_ characters: [CharacterRecord]) {
        self.characters = characters
        charactersById = Dictionary(uniqueKeysWithValues: characters.map { ($0.characterId, $0) })
    }

    private func applySnapshot(_ snapshot: GuildRosterSnapshot) {
        playerState = snapshot.playerState
        applyCharacters(snapshot.characters)
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
