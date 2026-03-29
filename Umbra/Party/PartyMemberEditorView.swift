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

    var body: some View {
        Group {
            if let party {
                List {
                    Section("パーティメンバー (\(party.memberCharacterIds.count)/\(PartyRecord.memberLimit))") {
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
                                        partyStore.removeCharacter(
                                            characterId: character.characterId,
                                            fromParty: party.partyId
                                        )
                                    }
                                    .disabled(!canEditMembers)
                                }
                            }
                            .onMove { offsets, destination in
                                guard canEditMembers else {
                                    return
                                }
                                partyStore.movePartyMembers(
                                    partyId: party.partyId,
                                    fromOffsets: offsets,
                                    toOffset: destination
                                )
                            }
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
                                            partyStore.addCharacter(
                                                characterId: character.characterId,
                                                toParty: party.partyId
                                            )
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
                .navigationTitle("メンバー編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                            .disabled(partyMembers.count < 2 || !canEditMembers)
                    }
                }
                .alert(
                    "メンバーを移籍しますか？",
                    isPresented: isShowingTransferConfirmation,
                    presenting: transferCandidate
                ) { candidate in
                    Button("移籍") {
                        partyStore.addCharacter(
                            characterId: candidate.character.characterId,
                            toParty: party.partyId
                        )
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
                if !isPresented {
                    transferCandidate = nil
                }
            }
        )
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
            Image(character.portraitAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)

                Text("\(masterData.raceName(for: character.raceId)) / \(masterData.jobName(for: character.currentJobId)) / \(masterData.aptitudeName(for: character.aptitudeId))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("Lv \(character.level)")
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
