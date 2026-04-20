// Owns party state and mutations without pulling character or equipment snapshots into the same store.

import Foundation
import Observation

@MainActor
@Observable
final class PartyStore {
    private let coreDataRepository: GuildCoreDataRepository
    private let service: PartyManagementService

    private(set) var phase: StoreLoadPhase
    private(set) var parties: [PartyRecord]
    private(set) var partiesById: [Int: PartyRecord]
    private(set) var contentRevision = 0
    private(set) var isMutating = false
    private(set) var lastOperationError: String?

    init(
        coreDataRepository: GuildCoreDataRepository,
        service: PartyManagementService,
        phase: StoreLoadPhase = .idle
    ) {
        self.coreDataRepository = coreDataRepository
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

        // Reload resets the lightweight caches first so views never observe a half-rebuilt party
        // list after a persistence error.
        phase = .loading
        parties = []
        partiesById = [:]
        lastOperationError = nil

        do {
            applyParties(try coreDataRepository.loadParties())
            phase = .loaded
        } catch {
            phase = .failed(UserFacingErrorMessage.resolve(error))
        }
    }

    func unlockParty(
        masterData: MasterData,
        consuming requiredJewel: EconomicCapJewelSelection? = nil
    ) {
        guard !isMutating, phase == .loaded else {
            return
        }

        isMutating = true
        lastOperationError = nil
        defer { isMutating = false }

        do {
            if let requiredJewel {
                applyParties(
                    try service.unlockParty(
                        consuming: requiredJewel,
                        masterData: masterData
                    )
                )
            } else {
                applyParties(try service.unlockParty())
            }
        } catch {
            lastOperationError = UserFacingErrorMessage.resolve(error)
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
            lastOperationError = UserFacingErrorMessage.resolve(error)
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

        // Membership edits apply optimistically so drag-and-drop style actions feel immediate,
        // but the previous snapshot is restored if the async service validation rejects them.
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
                lastOperationError = UserFacingErrorMessage.resolve(error)
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
                lastOperationError = UserFacingErrorMessage.resolve(error)
            }
        }
    }

    func setAutomaticallyUsesCatTicket(
        partyId: Int,
        isEnabled: Bool
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
                    try await service.setAutomaticallyUsesCatTicket(
                        partyId: partyId,
                        isEnabled: isEnabled
                    )
                )
            } catch {
                lastOperationError = UserFacingErrorMessage.resolve(error)
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

        // Removal uses the same optimistic path as insertion so local order and membership update
        // together, then reconcile against persisted state when the service returns.
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
                lastOperationError = UserFacingErrorMessage.resolve(error)
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
                lastOperationError = UserFacingErrorMessage.resolve(error)
            }
        }
    }

    func partyContainingCharacter(characterId: Int) -> PartyRecord? {
        parties.first(where: { $0.memberCharacterIds.contains(characterId) })
    }

    func synchronizeLoadedParties(_ parties: [PartyRecord]) {
        guard phase == .loaded else {
            return
        }

        applyParties(parties)
    }

    private func applyParties(_ parties: [PartyRecord]) {
        self.parties = parties
        // The ID lookup is rebuilt eagerly because most party-facing screens dereference by ID.
        partiesById = Dictionary(uniqueKeysWithValues: parties.map { ($0.partyId, $0) })
        contentRevision &+= 1
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

        // SwiftUI reports the destination in the pre-removal coordinate space, so the insertion
        // index must be adjusted by the number of moved rows that were originally before it.
        let insertionIndex = min(
            max(destination - offsets.filter { $0 < destination }.count, 0),
            remainingMembers.count
        )
        remainingMembers.insert(contentsOf: movedMembers, at: insertionIndex)
        return remainingMembers
    }

}
