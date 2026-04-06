// Shows a party summary and management destinations for the selected party.

import SwiftUI

struct PartyDetailView: View {
    let partyId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    @State private var partyNameDraft = ""
    @State private var presentedCharacter: CharacterRecord?
    @FocusState private var isPartyNameFieldFocused: Bool

    var body: some View {
        Group {
            if let party {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("パーティ名", text: $partyNameDraft)
                                .focused($isPartyNameFieldFocused)
                                .submitLabel(.done)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    commitPartyName(for: party)
                                }
                                .onChange(of: isPartyNameFieldFocused) { _, isFocused in
                                    guard !isFocused else {
                                        return
                                    }

                                    commitPartyName(for: party)
                                }
                                .accessibilityLabel("パーティ名")

                            PartyMembersView(
                                memberCharacterIds: party.memberCharacterIds,
                                charactersById: rosterStore.charactersById,
                                displayedHPs: activeRun?.currentPartyHPs,
                                onSelectCharacter: { character in
                                    presentedCharacter = character
                                }
                            )
                        }
                        .padding(.bottom, 4)
                    }

                    Section {
                        NavigationLink("パーティのスキルを見る") {
                            PartySkillSummaryView(
                                partyId: party.partyId,
                                masterData: masterData,
                                rosterStore: rosterStore,
                                partyStore: partyStore
                            )
                        }

                        if isRunLocked {
                            lockedManagementRow("メンバーを変更する (6名まで)")
                        } else {
                            NavigationLink("メンバーを変更する (6名まで)") {
                                PartyMemberEditorView(
                                    partyId: party.partyId,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    explorationStore: explorationStore
                                )
                            }
                        }

                        if isRunLocked {
                            lockedManagementRow("装備の変更")
                        } else {
                            NavigationLink("装備の変更") {
                                PartyEquipmentMenuView(
                                    party: party,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    equipmentStore: equipmentStore
                                )
                            }
                        }
                    }

                    if !masterData.labyrinths.isEmpty {
                        Section("出撃設定") {
                            Picker("迷宮", selection: selectedLabyrinthBinding) {
                                Text("未設定").tag(Optional<Int>.none)
                                ForEach(masterData.labyrinths) { labyrinth in
                                    Text(labyrinth.name)
                                        .tag(Optional(labyrinth.id))
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .disabled(isRunLocked)

                            if selectedLabyrinth != nil {
                                Picker("探索難易度", selection: selectedDifficultyTitleBinding) {
                                    ForEach(availableDifficultyTitles) { title in
                                        Text(
                                            masterData.explorationLabyrinthDisplayName(
                                                labyrinthName: selectedLabyrinth?.name ?? "",
                                                difficultyTitleId: title.id
                                            )
                                        )
                                            .tag(title.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.secondary)
                                .disabled(isRunLocked)
                            }

                            Toggle(
                                "自動的にキャット・チケットを使用",
                                isOn: automaticallyUsesCatTicketBinding
                            )
                            .disabled(isRunLocked)

                            if isRunLocked {
                                Text("探索中は出撃設定を変更できません。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
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
                .navigationTitle("パーティ詳細")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $presentedCharacter) { character in
                    NavigationStack {
                        CharacterDetailView(
                            characterId: character.characterId,
                            masterData: masterData,
                            rosterStore: rosterStore,
                            explorationStore: explorationStore
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("閉じる") {
                                    presentedCharacter = nil
                                }
                            }
                        }
                    }
                }
                .task {
                    if partyNameDraft.isEmpty {
                        partyNameDraft = party.name
                    }
                    await explorationStore.loadIfNeeded(masterData: masterData)
                }
                .onDisappear {
                    commitPartyName(for: party)
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

    private var activeRun: RunSessionRecord? {
        explorationStore.status(for: partyId).activeRun
    }

    private var isRunLocked: Bool {
        activeRun != nil
    }

    private var selectedLabyrinth: MasterData.Labyrinth? {
        guard let labyrinthId = party?.selectedLabyrinthId else {
            return nil
        }

        return masterData.labyrinths.first(where: { $0.id == labyrinthId })
    }

    private var highestUnlockedDifficultyTitleId: Int? {
        guard let labyrinthId = selectedLabyrinth?.id else {
            return nil
        }

        return rosterStore.labyrinthProgressByLabyrinthId[labyrinthId]?.highestUnlockedDifficultyTitleId
    }

    private var availableDifficultyTitles: [MasterData.Title] {
        guard selectedLabyrinth != nil else {
            return []
        }

        let titles = masterData.explorationDifficultyTitles
        let highestUnlockedTitleId = highestUnlockedDifficultyTitleId
            ?? masterData.defaultExplorationDifficultyTitle?.id
        guard let highestUnlockedTitleId,
              let unlockedIndex = titles.firstIndex(where: { $0.id == highestUnlockedTitleId }) else {
            return titles
        }

        // The picker exposes only the unlocked prefix for the currently selected labyrinth.
        return Array(titles.prefix(unlockedIndex + 1))
    }

    private var selectedLabyrinthBinding: Binding<Int?> {
        Binding(
            get: {
                party?.selectedLabyrinthId
            },
            set: { selectedLabyrinthId in
                guard let party else {
                    return
                }
                let resolvedDifficultyTitleId: Int?
                if let selectedLabyrinthId {
                    // Changing labyrinth re-resolves difficulty immediately so the saved title
                    // remains valid for the new unlock state.
                    let highestUnlockedTitleId = rosterStore.labyrinthProgressByLabyrinthId[selectedLabyrinthId]?
                        .highestUnlockedDifficultyTitleId
                    resolvedDifficultyTitleId = masterData.resolvedExplorationDifficultyTitleId(
                        requestedTitleId: party.selectedDifficultyTitleId,
                        highestUnlockedTitleId: highestUnlockedTitleId
                    )
                } else {
                    resolvedDifficultyTitleId = nil
                }
                partyStore.setSelectedLabyrinth(
                    partyId: party.partyId,
                    selectedLabyrinthId: selectedLabyrinthId,
                    selectedDifficultyTitleId: resolvedDifficultyTitleId
                )
            }
        )
    }

    private var selectedDifficultyTitleBinding: Binding<Int> {
        Binding(
            get: {
                guard let party else {
                    return masterData.defaultExplorationDifficultyTitle?.id ?? 0
                }

                return masterData.resolvedExplorationDifficultyTitleId(
                    requestedTitleId: party.selectedDifficultyTitleId,
                    highestUnlockedTitleId: highestUnlockedDifficultyTitleId
                )
            },
            set: { selectedDifficultyTitleId in
                guard let party else {
                    return
                }

                partyStore.setSelectedLabyrinth(
                    partyId: party.partyId,
                    selectedLabyrinthId: party.selectedLabyrinthId,
                    selectedDifficultyTitleId: selectedDifficultyTitleId
                )
            }
        )
    }

    private var automaticallyUsesCatTicketBinding: Binding<Bool> {
        Binding(
            get: {
                party?.automaticallyUsesCatTicket ?? false
            },
            set: { isEnabled in
                guard let party else {
                    return
                }

                partyStore.setAutomaticallyUsesCatTicket(
                    partyId: party.partyId,
                    isEnabled: isEnabled
                )
            }
        )
    }

    private func commitPartyName(for party: PartyRecord) {
        let normalizedName = PartyRecord.normalizedName(partyNameDraft)
        guard !normalizedName.isEmpty else {
            partyNameDraft = party.name
            return
        }
        guard normalizedName != party.name else {
            partyNameDraft = party.name
            return
        }

        // The field is reset from persisted state after rename so any service-side normalization
        // is reflected back into the draft text.
        partyStore.renameParty(partyId: party.partyId, name: normalizedName)
        if let refreshedName = partyStore.partiesById[party.partyId]?.name {
            partyNameDraft = refreshedName
        }
    }

    @ViewBuilder
    private func lockedManagementRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "lock")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

}
