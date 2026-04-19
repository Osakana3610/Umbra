// Lists hired characters and allows confirmed permanent dismissal from the guild.

import SwiftUI

struct CharacterDismissalView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore
    let rosterService: GuildRosterService

    @State private var pendingDismissalCharacterId: Int?
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("一度解雇したキャラクターは帰ってきません。慎重に判断してください。")
                    .foregroundStyle(.secondary)
            }

            Section("雇用中のキャラクター") {
                if rosterStore.characters.isEmpty {
                    Text("まだ雇用していません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rosterStore.characters) { character in
                        CharacterDismissalRow(
                            character: character,
                            portraitAssetName: masterData.portraitAssetName(for: character),
                            partyName: partyStore.partyContainingCharacter(characterId: character.characterId)?.name,
                            summaryText: masterData.characterSummaryText(for: character),
                            isLocked: explorationStore.hasActiveRun(forCharacterId: character.characterId)
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("解雇", role: .destructive) {
                                pendingDismissalCharacterId = character.characterId
                            }
                            .disabled(isDeleting || explorationStore.hasActiveRun(forCharacterId: character.characterId))
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .playerStatusContentInsetAware()
        .navigationTitle("解雇")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "解雇しますか？",
            isPresented: isShowingDismissalConfirmation,
            presenting: pendingDismissalCharacter
        ) { character in
            Button("解雇", role: .destructive) {
                delete(character)
            }
            Button("キャンセル", role: .cancel) {
                pendingDismissalCharacterId = nil
            }
        } message: { character in
            Text(dismissalMessage(for: character))
        }
    }

    private var pendingDismissalCharacter: CharacterRecord? {
        guard let pendingDismissalCharacterId else {
            return nil
        }

        return rosterStore.charactersById[pendingDismissalCharacterId]
    }

    private var isShowingDismissalConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDismissalCharacter != nil },
            set: { isPresented in
                // Clearing the pending ID on dismiss keeps the alert source of truth entirely in
                // this one optional instead of mirroring it in separate state.
                if !isPresented {
                    pendingDismissalCharacterId = nil
                }
            }
        )
    }

    private func dismissalMessage(for character: CharacterRecord) -> String {
        if let party = partyStore.partyContainingCharacter(characterId: character.characterId) {
            return "\(character.name)を解雇します。\(party.name)からも外れ、装備中のアイテムはインベントリに戻ります。一度解雇したキャラクターはギルドに帰ってくることはありません。"
        }

        return "\(character.name)を解雇します。装備中のアイテムはインベントリに戻ります。一度解雇したキャラクターはギルドに帰ってくることはありません。"
    }

    private func delete(_ character: CharacterRecord) {
        guard !isDeleting else {
            return
        }

        isDeleting = true
        errorMessage = nil

        Task {
            defer {
                isDeleting = false
                pendingDismissalCharacterId = nil
            }

            do {
                try await rosterService.deleteCharacter(characterId: character.characterId)
                // Dismissal can reshape party membership and shared inventory, so refresh all three
                // views from persistence after the mutation commits.
                rosterStore.refreshFromPersistence()
                partyStore.reload()
                if equipmentStore.isLoaded {
                    equipmentStore.applyInventoryChanges(
                        Dictionary(
                            character.equippedItemStacks.map { ($0.itemID, $0.count) },
                            uniquingKeysWith: +
                        ),
                        masterData: masterData
                    )
                    equipmentStore.removeCharacter(characterId: character.characterId)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CharacterDismissalRow: View {
    let character: CharacterRecord
    let portraitAssetName: String
    let partyName: String?
    let summaryText: String
    let isLocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GameAssetImage(assetName: portraitAssetName)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)

                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("HP \(character.currentHP)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let partyName {
                    Text("所属: \(partyName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isLocked {
                    Text("出撃中のため解雇できません。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
