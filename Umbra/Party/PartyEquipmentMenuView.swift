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
                        EquipmentCharacterRow(
                            character: member,
                            masterData: masterData,
                            nameResolver: nameResolver
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .playerStatusContentInsetAware()
        .navigationTitle("装備の変更")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var members: [CharacterRecord] {
        // Party member order is preserved so the equipment menu matches the formation shown on the
        // party detail and adventure screens.
        party.memberCharacterIds.compactMap { rosterStore.charactersById[$0] }
    }
}
