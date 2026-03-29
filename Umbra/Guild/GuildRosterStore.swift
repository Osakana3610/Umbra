// Owns player and character state for guild-facing UI without party or equipment cache responsibilities.

import Foundation
import Observation

@MainActor
@Observable
final class GuildRosterStore {
    private let coreDataStore: GuildCoreDataStore
    private let service: GuildService

    private(set) var phase: StoreLoadPhase
    private(set) var playerState: PlayerState?
    private(set) var characters: [CharacterRecord]
    private(set) var charactersById: [Int: CharacterRecord]
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var lastHireMessage: String?

    init(
        coreDataStore: GuildCoreDataStore,
        service: GuildService,
        phase: StoreLoadPhase = .idle
    ) {
        self.coreDataStore = coreDataStore
        self.service = service
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
            let snapshot = try coreDataStore.loadRosterSnapshot()
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
            let result = try service.hireCharacter(
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
            let snapshot = try service.reviveCharacter(
                characterId: characterId,
                masterData: masterData
            )
            playerState = snapshot.playerState
            applyCharacters(snapshot.characters)
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
            let snapshot = try service.reviveAllDefeated(masterData: masterData)
            playerState = snapshot.playerState
            applyCharacters(snapshot.characters)
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
            let snapshot = try service.setAutoReviveDefeatedCharactersEnabled(isEnabled)
            playerState = snapshot.playerState
            applyCharacters(snapshot.characters)
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

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}
