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
    private(set) var partiesById: [Int: PartyRecord]
    private(set) var isMutating = false
    private(set) var lastOperationError: String?
    private(set) var lastHireMessage: String?

    init(repository: GuildRepository) {
        self.repository = repository
        self.phase = .idle
        self.playerState = nil
        self.charactersById = [:]
        self.partiesById = [:]
    }

    init(phase: Phase, repository: GuildRepository) {
        self.repository = repository
        self.phase = phase
        self.playerState = nil
        self.charactersById = [:]
        self.partiesById = [:]
    }

    var characters: [CharacterRecord] {
        charactersById.values.sorted { $0.characterId < $1.characterId }
    }

    var parties: [PartyRecord] {
        partiesById.values.sorted { $0.partyId < $1.partyId }
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
        partiesById = [:]
        lastOperationError = nil

        do {
            try loadSnapshot()
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
            try loadSnapshot()
            phase = .loaded
            lastHireMessage = "\(result.character.name)を雇用しました。"
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func unlockParty() async {
        await performMutation {
            try repository.unlockParty()
        }
    }

    func renameParty(partyId: Int, name: String) async {
        await performMutation {
            try repository.renameParty(partyId: partyId, name: name)
        }
    }

    func addCharacter(characterId: Int, toParty partyId: Int) async {
        await performMutation {
            try repository.addCharacter(characterId: characterId, toParty: partyId)
        }
    }

    func removeCharacter(characterId: Int, fromParty partyId: Int) async {
        await performMutation {
            try repository.removeCharacter(characterId: characterId, fromParty: partyId)
        }
    }

    func movePartyMembers(partyId: Int, fromOffsets: IndexSet, toOffset: Int) async {
        guard let party = partiesById[partyId] else {
            return
        }

        let reorderedMembers = reorderedMembers(
            from: party.memberCharacterIds,
            moving: fromOffsets,
            to: toOffset
        )

        await performMutation {
            try repository.replacePartyMembers(
                partyId: partyId,
                memberCharacterIds: reorderedMembers
            )
        }
    }

    func hirePrice(raceId: Int, jobId: Int, masterData: MasterData) -> Int? {
        GuildHiring.price(raceId: raceId, jobId: jobId, masterData: masterData)
    }

    func partyContainingCharacter(characterId: Int) -> PartyRecord? {
        parties.first(where: { $0.memberCharacterIds.contains(characterId) })
    }

    private var isLoading: Bool {
        if case .loading = phase {
            return true
        }

        return false
    }

    private func loadSnapshot() throws {
        let snapshot = try repository.loadSnapshot()
        playerState = snapshot.playerState
        charactersById = Dictionary(
            uniqueKeysWithValues: snapshot.characters.map { ($0.characterId, $0) }
        )
        partiesById = Dictionary(
            uniqueKeysWithValues: snapshot.parties.map { ($0.partyId, $0) }
        )
    }

    private func performMutation(_ operation: () throws -> Void) async {
        guard !isMutating,
              case .loaded = phase else {
            return
        }

        isMutating = true
        lastOperationError = nil
        lastHireMessage = nil
        defer { isMutating = false }

        do {
            try operation()
            try loadSnapshot()
            phase = .loaded
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    private func reorderedMembers(
        from memberCharacterIds: [Int],
        moving offsets: IndexSet,
        to destination: Int
    ) -> [Int] {
        let movedMembers = offsets.sorted().map { memberCharacterIds[$0] }
        var remainingMembers = memberCharacterIds.enumerated().compactMap { index, memberId in
            offsets.contains(index) ? nil : memberId
        }

        let insertionIndex = min(max(destination - offsets.filter { $0 < destination }.count, 0), remainingMembers.count)
        remainingMembers.insert(contentsOf: movedMembers, at: insertionIndex)
        return remainingMembers
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
