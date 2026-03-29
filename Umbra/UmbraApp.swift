// Boots the app shell and wires persistence, master data, and guild runtime state.

import SwiftUI

@main
struct UmbraApp: App {
    let persistenceController: PersistenceController
    let guildService: GuildService
    @State private var masterDataStore: MasterDataStore
    @State private var rosterStore: GuildRosterStore
    @State private var partyStore: PartyStore
    @State private var equipmentStore: EquipmentInventoryStore
    @State private var explorationStore: ExplorationStore

    init() {
        let persistenceController = PersistenceController.shared
        let guildCoreDataStore = GuildCoreDataStore(container: persistenceController.container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: persistenceController.container)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        self.persistenceController = persistenceController
        self.guildService = guildService
        _masterDataStore = State(initialValue: MasterDataStore())
        _rosterStore = State(
            initialValue: GuildRosterStore(
                coreDataStore: guildCoreDataStore,
                service: guildService
            )
        )
        _partyStore = State(
            initialValue: PartyStore(
                coreDataStore: guildCoreDataStore,
                service: guildService
            )
        )
        _equipmentStore = State(
            initialValue: EquipmentInventoryStore(
                coreDataStore: guildCoreDataStore,
                service: guildService
            )
        )
        _explorationStore = State(
            initialValue: ExplorationStore(
                coreDataStore: explorationCoreDataStore
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
                guildService: guildService
            )
        }
    }
}
