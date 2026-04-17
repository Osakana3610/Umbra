// Manages party membership by adding, removing, searching, transferring, and reordering members.

import SwiftUI

struct PartyMemberEditorView: View {
    let partyId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let explorationStore: ExplorationStore

    @State private var searchText = ""
    @State private var transferCandidate: TransferCandidate?
    @State private var isEditingPartyMembers = false

    var body: some View {
        Group {
            if let party {
                List {
                    Section {
                        if partyMembers.isEmpty {
                            Text("まだメンバーがいません。控えから追加してください。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(partyMembers) { character in
                                PartyCharacterRow(
                                    character: character,
                                    masterData: masterData
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("外す", role: .destructive) {
                                        removeMember(character, from: party.partyId)
                                    }
                                    .disabled(!canEditMembers)
                                }
                            }
                            .onMove(perform: partyMembersMoveAction(for: party))
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text("パーティメンバー (\(party.memberCharacterIds.count)/\(PartyRecord.memberLimit))")

                            Spacer()

                            Button(isEditingPartyMembers ? "完了" : "編集") {
                                isEditingPartyMembers.toggle()
                            }
                            .buttonStyle(.borderless)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                            .disabled(!canShowMemberEditControl)
                        }
                    }

                    Section {
                        PartyMemberSearchRow(searchText: $searchText)

                        if filteredReserveMembers.isEmpty {
                            if !trimmedSearchText.isEmpty && filteredOtherPartySections.isEmpty {
                                ContentUnavailableView.search(text: trimmedSearchText)
                            } else if trimmedSearchText.isEmpty {
                                Text("未所属の控えキャラクターはいません。")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(filteredReserveMembers) { character in
                                PartyCharacterRow(
                                    character: character,
                                    masterData: masterData
                                ) {
                                    addButton(
                                        accessibilityLabel: "\(character.name)を追加",
                                        action: {
                                            withAnimation {
                                                partyStore.addCharacter(
                                                    characterId: character.characterId,
                                                    toParty: party.partyId
                                                )
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    } header: {
                        Text("控え")
                    } footer: {
                        if !canEditMembers {
                            Text("探索中のパーティは編成を変更できません。")
                        } else if !canAddMember {
                            Text("パーティが満員です。メンバーを外すと追加できます。")
                        }
                    }

                    ForEach(filteredOtherPartySections) { section in
                        Section(section.party.name) {
                            ForEach(section.members) { character in
                                PartyCharacterRow(
                                    character: character,
                                    masterData: masterData
                                ) {
                                    addButton(
                                        accessibilityLabel: "\(section.party.name)から\(character.name)を移籍",
                                        action: {
                                            transferCandidate = TransferCandidate(
                                                character: character,
                                                sourceParty: section.party
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }

                    if let error = partyStore.lastOperationError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .playerStatusContentInsetAware()
                .navigationTitle("メンバー編集")
                .navigationBarTitleDisplayMode(.inline)
                .environment(
                    \.editMode,
                    Binding.constant(
                        isEditingPartyMembers && canShowMemberEditControl ? .active : .inactive
                    )
                )
                .alert(
                    "メンバーを移籍しますか？",
                    isPresented: isShowingTransferConfirmation,
                    presenting: transferCandidate
                ) { candidate in
                    Button("移籍") {
                        withAnimation {
                            partyStore.addCharacter(
                                characterId: candidate.character.characterId,
                                toParty: party.partyId
                            )
                        }
                        transferCandidate = nil
                    }
                    Button("キャンセル", role: .cancel) {
                        transferCandidate = nil
                    }
                } message: { candidate in
                    Text("\(candidate.character.name)を\(candidate.sourceParty.name)から\(party.name)へ移します。")
                }
            } else {
                ContentUnavailableView(
                    "パーティが見つかりません",
                    systemImage: "person.3.sequence"
                )
            }
        }
    }

    private var party: PartyRecord? {
        partyStore.partiesById[partyId]
    }

    private var partyMembers: [CharacterRecord] {
        party?.memberCharacterIds.compactMap { rosterStore.charactersById[$0] } ?? []
    }

    private var canAddMember: Bool {
        (party?.memberCharacterIds.count ?? 0) < PartyRecord.memberLimit
    }

    private var canEditMembers: Bool {
        !explorationStore.hasActiveRun(for: partyId)
    }

    private var canShowMemberEditControl: Bool {
        canEditMembers && partyMembers.count >= 2
    }

    private var reserveMembers: [CharacterRecord] {
        rosterStore.characters.filter { character in
            partyStore.partyContainingCharacter(characterId: character.characterId) == nil
        }
    }

    private var filteredReserveMembers: [CharacterRecord] {
        guard !trimmedSearchText.isEmpty else {
            return reserveMembers
        }

        return reserveMembers.filter { $0.name.localizedStandardContains(trimmedSearchText) }
    }

    private var filteredOtherPartySections: [OtherPartySection] {
        partyStore.parties.compactMap { sourceParty in
            guard sourceParty.partyId != partyId,
                  !explorationStore.hasActiveRun(for: sourceParty.partyId) else {
                return nil
            }

            // Members from parties that are currently exploring are excluded entirely so transfer
            // actions never compete with persisted run membership.
            let members = sourceParty.memberCharacterIds.compactMap { characterId in
                rosterStore.charactersById[characterId]
            }
            .filter {
                trimmedSearchText.isEmpty || $0.name.localizedStandardContains(trimmedSearchText)
            }

            guard !members.isEmpty else {
                return nil
            }

            return OtherPartySection(party: sourceParty, members: members)
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingTransferConfirmation: Binding<Bool> {
        Binding(
            get: { transferCandidate != nil },
            set: { isPresented in
                // Clearing the candidate on dismiss keeps alert presentation state driven by one
                // source of truth instead of a second boolean flag.
                if !isPresented {
                    transferCandidate = nil
                }
            }
        )
    }

    private func removeMember(_ character: CharacterRecord, from partyId: Int) {
        withAnimation {
            partyStore.removeCharacter(
                characterId: character.characterId,
                fromParty: partyId
            )
        }
    }

    private func partyMembersMoveAction(
        for party: PartyRecord
    ) -> ((IndexSet, Int) -> Void)? {
        // Reordering is exposed only while the local edit mode is active and the party is not in
        // an active run, matching the rest of the membership mutation rules.
        guard isEditingPartyMembers, canEditMembers else {
            return nil
        }

        return { offsets, destination in
            partyStore.movePartyMembers(
                partyId: party.partyId,
                fromOffsets: offsets,
                toOffset: destination
            )
        }
    }

    @ViewBuilder
    private func addButton(
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(canAddMember && canEditMembers ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        // The add affordance follows the same gate for reserve adds and transfers so the UI does
        // not invite edits that the store would reject anyway.
        .disabled(!canAddMember || !canEditMembers || partyStore.isMutating)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PartyCharacterRow<Accessory: View>: View {
    let character: CharacterRecord
    let masterData: MasterData
    private let showsAccessory: Bool
    private let accessory: Accessory

    init(
        character: CharacterRecord,
        masterData: MasterData
    ) where Accessory == EmptyView {
        self.character = character
        self.masterData = masterData
        showsAccessory = false
        accessory = EmptyView()
    }

    init(
        character: CharacterRecord,
        masterData: MasterData,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.character = character
        self.masterData = masterData
        showsAccessory = true
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            GameAssetImage(assetName: masterData.portraitAssetName(for: character))
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)

                Text("\(masterData.raceName(for: character.raceId)) / \(masterData.jobDisplayName(for: character)) / \(masterData.aptitudeName(for: character.aptitudeId))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("Lv.\(character.level)")
                    Text("HP \(character.currentHP)")
                }
                .font(.caption)
                .monospacedDigit()

                if character.currentHP == 0 {
                    Text("戦闘不能")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if showsAccessory {
                Spacer(minLength: 12)
                accessory
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PartyMemberSearchRow: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("キャラクター名で検索", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct OtherPartySection: Identifiable {
    let party: PartyRecord
    let members: [CharacterRecord]

    var id: Int { party.partyId }
}

private struct TransferCandidate: Identifiable {
    let character: CharacterRecord
    let sourceParty: PartyRecord

    var id: String {
        "\(sourceParty.partyId)-\(character.characterId)"
    }
}
