// Presents the guild overview with roster state and navigation into guild management screens.

import SwiftUI

struct GuildHomeView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let explorationStore: ExplorationStore

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
                            NavigationLink {
                                CharacterDetailView(
                                    characterId: character.characterId,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    explorationStore: explorationStore
                                )
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
                                        Text(summaryText(for: character))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("ギルド")
    }

    private var defeatedCharacters: [CharacterRecord] {
        rosterStore.characters.filter { $0.currentHP == 0 }
    }

    private func summaryText(for character: CharacterRecord) -> String {
        "\(masterData.characterSummaryText(for: character)) / HP \(character.currentHP)"
    }
}
