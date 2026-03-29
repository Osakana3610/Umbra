// Edits a single party's name, members, and formation order.

import SwiftUI

struct PartyDetailView: View {
    let partyId: Int
    let masterData: MasterData
    let guildStore: GuildStore

    @State private var draftPartyName = ""
    @State private var pendingTransferCharacter: CharacterRecord?

    var body: some View {
        Group {
            if let party {
                List {
                    Section("基本情報") {
                        TextField("パーティ名", text: $draftPartyName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("パーティ名を保存") {
                            Task {
                                await guildStore.renameParty(
                                    partyId: party.partyId,
                                    name: draftPartyName
                                )
                            }
                        }
                        .disabled(!canSaveName(for: party))
                    }

                    Section("編成") {
                        PartyFormationStrip(
                            memberCharacterIds: party.memberCharacterIds,
                            charactersById: guildStore.charactersById
                        )

                        if party.memberCharacterIds.isEmpty {
                            Text("まだメンバーがいません。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(memberCharacters(for: party)) { character in
                                HStack(spacing: 12) {
                                    Image(character.portraitAssetName)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(character.name)
                                            .font(.headline)
                                        Text(characterSummary(for: character))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(positionText(for: character, in: party))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    Button("外す", role: .destructive) {
                                        Task {
                                            await guildStore.removeCharacter(
                                                characterId: character.characterId,
                                                fromParty: party.partyId
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .onMove { offsets, destination in
                                Task {
                                    await guildStore.movePartyMembers(
                                        partyId: party.partyId,
                                        fromOffsets: offsets,
                                        toOffset: destination
                                    )
                                }
                            }
                        }
                    }

                    Section("加入候補") {
                        if guildStore.characters.isEmpty {
                            Text("先にギルドでキャラクターを雇用してください。")
                                .foregroundStyle(.secondary)
                        } else if party.isFull {
                            Text("このパーティは6人編成です。")
                                .foregroundStyle(.secondary)
                        } else if availableCharacters(for: party).isEmpty {
                            Text("加入できるキャラクターがいません。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableCharacters(for: party)) { character in
                                Button {
                                    addCharacter(character, to: party)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(character.portraitAssetName)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 52, height: 52)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(character.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text(characterSummary(for: character))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)

                                            if let assignedParty = guildStore.partyContainingCharacter(
                                                characterId: character.characterId
                                            ) {
                                                Text("現在所属: \(assignedParty.name)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let error = guildStore.lastOperationError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle(party.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                            .disabled(party.memberCharacterIds.count < 2)
                    }
                }
                .onAppear {
                    syncDraftName(with: party)
                }
                .onChange(of: party.name) { _, newValue in
                    draftPartyName = newValue
                }
                .alert(
                    "所属パーティを変更しますか？",
                    isPresented: pendingTransferAlertBinding,
                    presenting: pendingTransferCharacter
                ) { character in
                    Button("移動する") {
                        Task {
                            await guildStore.addCharacter(
                                characterId: character.characterId,
                                toParty: party.partyId
                            )
                        }
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: { character in
                    let sourcePartyName = guildStore.partyContainingCharacter(
                        characterId: character.characterId
                    )?.name ?? ""
                    Text("\(character.name)を\(sourcePartyName)から外して追加します。")
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
        guildStore.partiesById[partyId]
    }

    private var pendingTransferAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingTransferCharacter != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTransferCharacter = nil
                }
            }
        )
    }

    private func syncDraftName(with party: PartyRecord) {
        if draftPartyName != party.name {
            draftPartyName = party.name
        }
    }

    private func canSaveName(for party: PartyRecord) -> Bool {
        let normalizedName = PartyRecord.normalizedName(draftPartyName)
        return !guildStore.isMutating &&
            !normalizedName.isEmpty &&
            normalizedName != party.name
    }

    private func memberCharacters(for party: PartyRecord) -> [CharacterRecord] {
        party.memberCharacterIds.compactMap { guildStore.charactersById[$0] }
    }

    private func availableCharacters(for party: PartyRecord) -> [CharacterRecord] {
        guildStore.characters.filter { !party.memberCharacterIds.contains($0.characterId) }
    }

    private func addCharacter(_ character: CharacterRecord, to party: PartyRecord) {
        guard let sourceParty = guildStore.partyContainingCharacter(characterId: character.characterId),
              sourceParty.partyId != party.partyId else {
            Task {
                await guildStore.addCharacter(characterId: character.characterId, toParty: party.partyId)
            }
            return
        }

        pendingTransferCharacter = character
    }

    private func characterSummary(for character: CharacterRecord) -> String {
        let raceName = masterData.races.first(where: { $0.id == character.raceId })?.name ?? "不明"
        let jobName = masterData.jobs.first(where: { $0.id == character.currentJobId })?.name ?? "不明"
        return "\(raceName) / \(jobName) / Lv.\(character.level) / HP \(character.currentHP)"
    }

    private func positionText(for character: CharacterRecord, in party: PartyRecord) -> String {
        guard let index = party.memberCharacterIds.firstIndex(of: character.characterId) else {
            return ""
        }

        return switch index {
        case 0:
            "最前列"
        case party.memberCharacterIds.count - 1:
            "最後列"
        default:
            "\(index + 1)番目"
        }
    }
}

private struct PartyFormationStrip: View {
    let memberCharacterIds: [Int]
    let charactersById: [Int: CharacterRecord]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<PartyRecord.memberLimit, id: \.self) { index in
                if index < memberCharacterIds.count,
                   let character = charactersById[memberCharacterIds[index]] {
                    Image(character.portraitAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.clear)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
