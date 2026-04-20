// Owns player and character state for guild-facing UI without party or equipment cache responsibilities.

import Foundation
import Observation

@MainActor
@Observable
final class GuildRosterStore {
    private let coreDataRepository: GuildCoreDataRepository
    private let service: GuildRosterService

    private(set) var phase: StoreLoadPhase
    private(set) var playerState: PlayerState?
    private(set) var characters: [CharacterRecord]
    private(set) var charactersById: [Int: CharacterRecord]
    private(set) var labyrinthProgressRecords: [LabyrinthProgressRecord]
    private(set) var labyrinthProgressByLabyrinthId: [Int: LabyrinthProgressRecord]
    private(set) var contentRevision = 0
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var lastHireMessage: String?

    init(
        coreDataRepository: GuildCoreDataRepository,
        service: GuildRosterService,
        phase: StoreLoadPhase = .idle
    ) {
        self.coreDataRepository = coreDataRepository
        self.service = service
        self.phase = phase
        playerState = nil
        characters = []
        charactersById = [:]
        labyrinthProgressRecords = []
        labyrinthProgressByLabyrinthId = [:]
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

        // A full reload clears derived lookup tables first so partially loaded state never leaks
        // into the guild UI after a persistence failure.
        phase = .loading
        playerState = nil
        characters = []
        charactersById = [:]
        labyrinthProgressRecords = []
        labyrinthProgressByLabyrinthId = [:]
        lastOperationError = nil
        lastHireMessage = nil

        do {
            let snapshot = try coreDataRepository.loadRosterSnapshot()
            applySnapshot(snapshot)
            phase = .loaded
        } catch {
            phase = .failed(UserFacingErrorMessage.resolve(error))
        }
    }

    func refreshFromPersistence() {
        guard phase == .loaded,
              !isMutating else {
            return
        }

        do {
            // This path bypasses the cached snapshot and forces a fresh Core Data read so adventure
            // rewards and background updates can be reflected without rebuilding the whole store.
            let snapshot = try coreDataRepository.loadFreshRosterSnapshot()
            applySnapshot(snapshot)
            lastOperationError = nil
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
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
            lastHireMessage = "\(result.character.name)を雇用しました！"
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
        }
    }

    func dismissHireMessage() {
        lastHireMessage = nil
    }

    func replacePlayerState(_ playerState: PlayerState) {
        self.playerState = playerState
        contentRevision &+= 1
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
            applySnapshot(snapshot)
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
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
            applySnapshot(snapshot)
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
        }
    }

    func renameCharacter(
        characterId: Int,
        name: String
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            let character = try service.renameCharacter(
                characterId: characterId,
                name: name
            )
            replaceCharacter(character)
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
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
            applySnapshot(snapshot)
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
        }
    }

    func setAutoSellEnabled(
        itemID: CompositeItemID,
        isEnabled: Bool,
        masterData: MasterData
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            let playerState = try service.setAutoSellEnabled(
                itemID: itemID,
                isEnabled: isEnabled,
                masterData: masterData
            )
            self.playerState = playerState
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
        }
    }

    func updateAutoBattleSettings(
        characterId: Int,
        autoBattleSettings: CharacterAutoBattleSettings
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                let character = try await service.updateAutoBattleSettings(
                    characterId: characterId,
                    autoBattleSettings: autoBattleSettings
                )
                replaceCharacter(character)
            } catch {
                lastOperationError = UserFacingErrorMessage.resolve(error)
            }
        }
    }

    func changeJob(
        characterId: Int,
        to targetJobId: Int,
        masterData: MasterData
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                let character = try await service.changeJob(
                    characterId: characterId,
                    to: targetJobId,
                    masterData: masterData
                )
                replaceCharacter(character)
            } catch {
                lastOperationError = UserFacingErrorMessage.resolve(error)
            }
        }
    }

    func replaceCharacter(_ character: CharacterRecord) {
        charactersById[character.characterId] = character

        // Keep the array sorted by persistent character ID so list views and dictionary lookups
        // stay in sync without requiring a full snapshot reload for single-character edits.
        if let index = characters.firstIndex(where: { $0.characterId == character.characterId }) {
            characters[index] = character
        } else if let insertIndex = characters.firstIndex(where: { $0.characterId > character.characterId }) {
            characters.insert(character, at: insertIndex)
        } else {
            characters.append(character)
        }
        contentRevision &+= 1
    }

    private func applyCharacters(_ characters: [CharacterRecord]) {
        self.characters = characters
        charactersById = Dictionary(uniqueKeysWithValues: characters.map { ($0.characterId, $0) })
    }

    private func applySnapshot(_ snapshot: GuildRosterSnapshot) {
        playerState = snapshot.playerState
        applyCharacters(snapshot.characters)
        labyrinthProgressRecords = snapshot.labyrinthProgressRecords
        // Difficulty unlock lookups are precomputed because adventure screens resolve them per
        // party card and during automatic-run resume.
        labyrinthProgressByLabyrinthId = Dictionary(
            uniqueKeysWithValues: snapshot.labyrinthProgressRecords.map { ($0.labyrinthId, $0) }
        )
        contentRevision &+= 1
    }

}
