// Lists defeated characters, supports individual or bulk revival, and controls automatic revival on return.

import SwiftUI

struct ReviveMenuView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore

    var body: some View {
        List {
            Section("戦闘不能") {
                if defeatedCharacters.isEmpty {
                    Text("戦闘不能のキャラクターはいません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(defeatedCharacters) { character in
                        HStack(spacing: 12) {
                            Image(character.portraitAssetName)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(character.name)
                                    .font(.headline)
                                Text(masterData.characterSummaryText(for: character))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("HP 0")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("蘇生") {
                                rosterStore.reviveCharacter(
                                    characterId: character.characterId,
                                    masterData: masterData
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(rosterStore.isMutating)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Toggle(
                    "自動的に蘇生",
                    isOn: Binding(
                        get: {
                            rosterStore.playerState?.autoReviveDefeatedCharacters ?? false
                        },
                        set: { isEnabled in
                            rosterStore.setAutoReviveDefeatedCharactersEnabled(isEnabled)
                        }
                    )
                )
                .disabled(rosterStore.isMutating)

                Text("有効時は、帰還時にHPが0のキャラクターを自動で全快蘇生します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = rosterStore.lastOperationError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("蘇生メニュー")
    }

    private var defeatedCharacters: [CharacterRecord] {
        rosterStore.characters.filter { $0.currentHP == 0 }
    }
}
