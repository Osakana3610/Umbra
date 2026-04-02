// Presents the guild overview with roster state and navigation into guild management screens.

import SwiftUI

struct GuildHomeView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore
    let guildService: GuildService
    @State private var presentedCharacter: CharacterRecord?

    var body: some View {
        List {
            if rosterStore.playerState != nil {
                Section {
                    NavigationLink {
                        HireView(masterData: masterData, rosterStore: rosterStore)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.plus")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("雇用する")
                                    .font(.headline)
                                Text("新しいキャラクターをギルドに迎えます。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("hire-entry-link")

                    NavigationLink {
                        ReviveMenuView(masterData: masterData, rosterStore: rosterStore)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cross.case")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("蘇生メニュー")
                                    .font(.headline)
                                Text("戦闘不能のキャラクターを蘇生します。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("雇用中のキャラクター") {
                    if rosterStore.characters.isEmpty {
                        Text("まだ雇用していません。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rosterStore.characters) { character in
                            HStack(spacing: 12) {
                                Image(character.portraitAssetName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name)
                                        .font(.headline)
                                    Text(summaryText(for: character))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    presentedCharacter = character
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.tint)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(character.name)の詳細")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("整理") {
                    NavigationLink("解雇") {
                        CharacterDismissalView(
                            masterData: masterData,
                            rosterStore: rosterStore,
                            partyStore: partyStore,
                            equipmentStore: equipmentStore,
                            explorationStore: explorationStore,
                            guildService: guildService
                        )
                    }
                }
            }
        }
        .navigationTitle("ギルド")
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
    }

    private func summaryText(for character: CharacterRecord) -> String {
        "\(masterData.characterSummaryText(for: character)) / HP \(character.currentHP)"
    }
}
