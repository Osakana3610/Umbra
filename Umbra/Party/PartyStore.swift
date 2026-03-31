// Owns party state and mutations without pulling character or equipment snapshots into the same store.

import Foundation
import Observation

@MainActor
@Observable
final class PartyStore {
    private let coreDataStore: GuildCoreDataStore
    private let service: GuildService

    private(set) var phase: StoreLoadPhase
    private(set) var parties: [PartyRecord]
    private(set) var partiesById: [Int: PartyRecord]
    private(set) var isMutating = false
    private(set) var lastOperationError: String?

    init(
        coreDataStore: GuildCoreDataStore,
        service: GuildService,
        phase: StoreLoadPhase = .idle
    ) {
        self.coreDataStore = coreDataStore
        self.service = service
        self.phase = phase
        parties = []
        partiesById = [:]
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
        parties = []
        partiesById = [:]
        lastOperationError = nil

        do {
            applyParties(try coreDataStore.loadParties())
            phase = .loaded
        } catch {
            phase = .failed(Self.errorMessage(for: error))
        }
    }

    func unlockParty() {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            applyParties(try service.unlockParty())
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func renameParty(partyId: Int, name: String) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            applyParties(try service.renameParty(partyId: partyId, name: name))
        } catch {
            lastOperationError = Self.errorMessage(for: error)
        }
    }

    func addCharacter(characterId: Int, toParty partyId: Int) {
        guard !isMutating,
              phase == .loaded,
              let targetPartyIndex = parties.firstIndex(where: { $0.partyId == partyId }) else {
            return
        }

        let previousParties = parties
        var updatedParties = parties

        if let sourcePartyIndex = updatedParties.firstIndex(where: { $0.memberCharacterIds.contains(characterId) }) {
            updatedParties[sourcePartyIndex].memberCharacterIds.removeAll { $0 == characterId }
        }
        updatedParties[targetPartyIndex].memberCharacterIds.append(characterId)

        isMutating = true
        lastOperationError = nil
        applyParties(updatedParties)

        Task {
            defer { isMutating = false }

            do {
                applyParties(
                    try await service.addCharacter(
                        characterId: characterId,
                        toParty: partyId
                    )
                )
            } catch {
                applyParties(previousParties)
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func setSelectedLabyrinth(
        partyId: Int,
        selectedLabyrinthId: Int?,
        selectedDifficultyTitleId: Int?
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                applyParties(
                    try await service.setSelectedLabyrinth(
                        partyId: partyId,
                        selectedLabyrinthId: selectedLabyrinthId,
                        selectedDifficultyTitleId: selectedDifficultyTitleId
                    )
                )
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func removeCharacter(characterId: Int, fromParty partyId: Int) {
        guard !isMutating,
              phase == .loaded,
              let partyIndex = parties.firstIndex(where: { $0.partyId == partyId }) else {
            return
        }

        let previousParties = parties
        var updatedParties = parties
        updatedParties[partyIndex].memberCharacterIds.removeAll { $0 == characterId }

        isMutating = true
        lastOperationError = nil
        applyParties(updatedParties)

        Task {
            defer { isMutating = false }

            do {
                applyParties(
                    try await service.removeCharacter(
                        characterId: characterId,
                        fromParty: partyId
                    )
                )
            } catch {
                applyParties(previousParties)
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func movePartyMembers(partyId: Int, fromOffsets: IndexSet, toOffset: Int) {
        guard !isMutating,
              phase == .loaded,
              let party = partiesById[partyId] else {
            return
        }

        let reorderedMembers = reorderedMembers(
            from: party.memberCharacterIds,
            moving: fromOffsets,
            to: toOffset
        )

        isMutating = true
        lastOperationError = nil

        Task {
            defer { isMutating = false }

            do {
                applyParties(
                    try await service.replacePartyMembers(
                        partyId: partyId,
                        memberCharacterIds: reorderedMembers
                    )
                )
            } catch {
                lastOperationError = Self.errorMessage(for: error)
            }
        }
    }

    func partyContainingCharacter(characterId: Int) -> PartyRecord? {
        parties.first(where: { $0.memberCharacterIds.contains(characterId) })
    }

    private func applyParties(_ parties: [PartyRecord]) {
        self.parties = parties
        partiesById = Dictionary(uniqueKeysWithValues: parties.map { ($0.partyId, $0) })
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

        let insertionIndex = min(
            max(destination - offsets.filter { $0 < destination }.count, 0),
            remainingMembers.count
        )
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
