// Edits a single party's name, members, and formation order.

import SwiftUI

struct PartyDetailView: View {
    let partyId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

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
                            partyStore.renameParty(partyId: party.partyId, name: draftPartyName)
                        }
                        .disabled(!canSaveName(for: party))
                    }

                    Section("編成") {
                        PartyFormationStrip(
                            memberCharacterIds: party.memberCharacterIds,
                            charactersById: rosterStore.charactersById
                        )

                        if isExploring {
                            Text("探索中は編成変更できません。")
                                .foregroundStyle(.secondary)
                        } else if party.memberCharacterIds.isEmpty {
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
                                        partyStore.removeCharacter(
                                            characterId: character.characterId,
                                            fromParty: party.partyId
                                        )
                                    }
                                    .disabled(isExploring)
                                }
                                .padding(.vertical, 4)
                            }
                            .onMove { offsets, destination in
                                partyStore.movePartyMembers(
                                    partyId: party.partyId,
                                    fromOffsets: offsets,
                                    toOffset: destination
                                )
                            }
                        }
                    }

                    Section("探索") {
                        if let activeRun {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("探索中")
                                    .font(.headline)
                                Text(activeRunSummary(activeRun))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            NavigationLink("探索記録を開く") {
                                RunSessionDetailView(
                                    partyId: activeRun.partyId,
                                    partyRunId: activeRun.partyRunId,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    equipmentStore: equipmentStore,
                                    explorationStore: explorationStore
                                )
                            }
                        } else if let latestCompletedRun {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("前回の探索")
                                    .font(.headline)
                                Text(completedRunSummary(latestCompletedRun))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            NavigationLink("探索記録を開く") {
                                RunSessionDetailView(
                                    partyId: latestCompletedRun.partyId,
                                    partyRunId: latestCompletedRun.partyRunId,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    equipmentStore: equipmentStore,
                                    explorationStore: explorationStore
                                )
                            }
                        } else {
                            Text("まだ探索していません。")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("装備") {
                        if isExploring {
                            Text("探索中は装備変更できません。")
                                .foregroundStyle(.secondary)
                        } else {
                            NavigationLink("装備を変更する") {
                                PartyEquipmentMenuView(
                                    party: party,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    equipmentStore: equipmentStore
                                )
                            }
                        }
                    }

                    Section("単体戦闘") {
                        if party.memberCharacterIds.isEmpty {
                            Text("単体戦闘を始めるにはメンバーを編成してください。")
                                .foregroundStyle(.secondary)
                        } else if !canStartSingleBattle(for: party) {
                            Text("HPが0のメンバーを含むパーティでは単体戦闘を開始できません。")
                                .foregroundStyle(.secondary)
                        } else {
                            NavigationLink("戦闘を選ぶ") {
                                SingleBattleSelectionView(
                                    party: party,
                                    masterData: masterData,
                                    rosterStore: rosterStore
                                )
                            }
                        }
                    }

                    Section("加入候補") {
                        if isExploring {
                            Text("探索中は加入・離脱できません。")
                                .foregroundStyle(.secondary)
                        } else if rosterStore.characters.isEmpty {
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

                                            if let assignedParty = partyStore.partyContainingCharacter(
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

                    if let error = partyStore.lastOperationError {
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
                            .disabled(party.memberCharacterIds.count < 2 || isExploring)
                    }
                }
                .onAppear {
                    syncDraftName(with: party)
                    explorationStore.loadIfNeeded()
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
                        partyStore.addCharacter(characterId: character.characterId, toParty: party.partyId)
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: { character in
                    let sourcePartyName = partyStore.partyContainingCharacter(
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
        partyStore.partiesById[partyId]
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

    private var activeRun: RunSessionRecord? {
        explorationStore.status(for: partyId).activeRun
    }

    private var latestCompletedRun: RunSessionRecord? {
        explorationStore.status(for: partyId).latestCompletedRun
    }

    private var isExploring: Bool {
        activeRun != nil
    }

    private func syncDraftName(with party: PartyRecord) {
        if draftPartyName != party.name {
            draftPartyName = party.name
        }
    }

    private func canSaveName(for party: PartyRecord) -> Bool {
        let normalizedName = PartyRecord.normalizedName(draftPartyName)
        return !partyStore.isMutating &&
            !normalizedName.isEmpty &&
            normalizedName != party.name
    }

    private func memberCharacters(for party: PartyRecord) -> [CharacterRecord] {
        party.memberCharacterIds.compactMap { rosterStore.charactersById[$0] }
    }

    private func availableCharacters(for party: PartyRecord) -> [CharacterRecord] {
        rosterStore.characters.filter { !party.memberCharacterIds.contains($0.characterId) }
    }

    private func canStartSingleBattle(for party: PartyRecord) -> Bool {
        memberCharacters(for: party).allSatisfy { $0.currentHP > 0 }
    }

    private func addCharacter(_ character: CharacterRecord, to party: PartyRecord) {
        guard let sourceParty = partyStore.partyContainingCharacter(characterId: character.characterId),
              sourceParty.partyId != party.partyId else {
            partyStore.addCharacter(characterId: character.characterId, toParty: party.partyId)
            return
        }

        pendingTransferCharacter = character
    }

    private func characterSummary(for character: CharacterRecord) -> String {
        "\(masterData.raceName(for: character.raceId)) / \(masterData.jobName(for: character.currentJobId)) / Lv.\(character.level) / HP \(character.currentHP)"
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

    private func activeRunSummary(_ run: RunSessionRecord) -> String {
        let labyrinthName = masterData.labyrinths.first(where: { $0.id == run.labyrinthId })?.name ?? "不明な迷宮"
        return "\(labyrinthName) / \(run.completedBattleCount)戦完了"
    }

    private func completedRunSummary(_ run: RunSessionRecord) -> String {
        guard let completion = run.completion else {
            return ""
        }

        let resultText: String
        switch completion.reason {
        case .cleared:
            resultText = "踏破"
        case .defeated:
            resultText = "全滅"
        case .draw:
            resultText = "引き分け"
        }
        return "\(resultText) / \(completion.gold) G / アイテム \(completion.dropRewards.count) 件"
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
