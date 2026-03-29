// Boots the app shell and wires persistence, master data, and guild runtime state.

import SwiftUI

@main
struct UmbraApp: App {
    let persistenceController: PersistenceController
    let equipmentRepository: EquipmentRepository
    @State private var masterDataStore: MasterDataStore
    @State private var rosterStore: GuildRosterStore
    @State private var partyStore: PartyStore
    @State private var equipmentStore: EquipmentInventoryStore
    @State private var explorationStore: ExplorationStore

    init() {
        let persistenceController = PersistenceController.shared
        let equipmentRepository = EquipmentRepository(container: persistenceController.container)
        self.persistenceController = persistenceController
        self.equipmentRepository = equipmentRepository
        _masterDataStore = State(initialValue: MasterDataStore())
        _rosterStore = State(
            initialValue: GuildRosterStore(
                repository: GuildRosterRepository(container: persistenceController.container)
            )
        )
        _partyStore = State(
            initialValue: PartyStore(
                repository: PartyRepository(container: persistenceController.container)
            )
        )
        _equipmentStore = State(
            initialValue: EquipmentInventoryStore(
                repository: equipmentRepository
            )
        )
        _explorationStore = State(
            initialValue: ExplorationStore(
                coreDataStore: ExplorationCoreDataStore(container: persistenceController.container)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                masterDataStore: masterDataStore,
                rosterStore: rosterStore,
                partyStore: partyStore,
                equipmentStore: equipmentStore,
                explorationStore: explorationStore,
                equipmentRepository: equipmentRepository
            )
        }
    }
}
