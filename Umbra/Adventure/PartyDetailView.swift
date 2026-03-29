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
                                displayedHPs: activeRun?.currentPartyHPs
                            )
                        }
                        .padding(.bottom, 4)
                    }

                    Section {
                        HStack(spacing: 12) {
                            Text("パーティのスキルを見る")
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("未実装")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
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
                        Section("出撃先迷宮") {
                            Picker("迷宮", selection: selectedLabyrinthBinding) {
                                Text("未設定").tag(Optional<Int>.none)
                                ForEach(masterData.labyrinths) { labyrinth in
                                    Text(labyrinth.name)
                                        .tag(Optional(labyrinth.id))
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .disabled(isRunLocked)

                            if isRunLocked {
                                Text("探索中は出撃先を変更できません。")
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
                .task {
                    if partyNameDraft.isEmpty {
                        partyNameDraft = party.name
                    }
                    await explorationStore.loadIfNeeded()
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

    private var selectedLabyrinthBinding: Binding<Int?> {
        Binding(
            get: {
                party?.selectedLabyrinthId
            },
            set: { selectedLabyrinthId in
                guard let party else {
                    return
                }
                partyStore.setSelectedLabyrinth(
                    partyId: party.partyId,
                    selectedLabyrinthId: selectedLabyrinthId
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
