// Lists defeated characters, exposes individual and bulk revival actions, and controls the guild's
// automatic-revival preference.
// The screen reads directly from roster state so manual revives and the return-time toggle stay in
// one place instead of being split across character detail and player settings views.

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
                            GameAssetImage(assetName: masterData.portraitAssetName(for: character))
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
                            // Persist the guild-wide preference immediately; the actual mass revive
                            // still happens later when the return flow resolves.
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
        .playerStatusContentInsetAware()
        .navigationTitle("蘇生メニュー")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("一括蘇生") {
                    rosterStore.reviveAllDefeated(masterData: masterData)
                }
                .disabled(defeatedCharacters.isEmpty || rosterStore.isMutating)
            }
        }
    }

    private var defeatedCharacters: [CharacterRecord] {
        // Treat zero HP as the single defeated-state source of truth for this menu.
        rosterStore.characters.filter { $0.currentHP == 0 }
    }
}
