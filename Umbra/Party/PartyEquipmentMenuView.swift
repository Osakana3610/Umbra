// Lists party members and opens each member's equipment editor without reloading unrelated state.

import SwiftUI

struct PartyEquipmentMenuView: View {
    let party: PartyRecord
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let equipmentStore: EquipmentInventoryStore

    private let nameResolver: EquipmentDisplayNameResolver

    init(
        party: PartyRecord,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        equipmentStore: EquipmentInventoryStore
    ) {
        self.party = party
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.equipmentStore = equipmentStore
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        List {
            if members.isEmpty {
                ContentUnavailableView(
                    "メンバーがいません",
                    systemImage: "person.3",
                    description: Text("パーティにメンバーを編成すると装備を変更できます。")
                )
            } else {
                ForEach(members) { member in
                    NavigationLink {
                        CharacterEquipmentView(
                            characterId: member.characterId,
                            masterData: masterData,
                            rosterStore: rosterStore,
                            equipmentStore: equipmentStore
                        )
                    } label: {
                        PartyEquipmentMemberRow(
                            character: member,
                            masterData: masterData,
                            nameResolver: nameResolver
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("装備の変更")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var members: [CharacterRecord] {
        // Party member order is preserved so the equipment menu matches the formation shown on the
        // party detail and adventure screens.
        party.memberCharacterIds.compactMap { rosterStore.charactersById[$0] }
    }
}

private struct PartyEquipmentMemberRow: View {
    let character: CharacterRecord
    let masterData: MasterData
    let nameResolver: EquipmentDisplayNameResolver

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(character.portraitAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(character.name)
                        .font(.headline)

                    Text("装備 \(character.equippedItemCount)/\(character.maximumEquippedItemCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(masterData.characterSummaryText(for: character))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if character.orderedEquippedItemStacks.isEmpty {
                    Text("装備なし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(character.orderedEquippedItemStacks) { stack in
                        let displayName = nameResolver.displayName(for: stack.itemID)
                        Text(stack.count > 1 ? "\(displayName) x\(stack.count)" : displayName)
                            .font(stack.itemID.baseSuperRareId > 0 ? .body.weight(.semibold) : .body)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
