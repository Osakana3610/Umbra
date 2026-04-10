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
    @State private var shopStore: ShopInventoryStore
    @State private var explorationStore: ExplorationStore
    @State private var itemDropNotificationService: ItemDropNotificationService

    init() {
        let persistenceController = PersistenceController.shared
        let guildCoreDataStore = GuildCoreDataStore(container: persistenceController.container)
        let explorationCoreDataStore = ExplorationCoreDataStore(container: persistenceController.container)
        let masterDataStore = MasterDataStore()
        let itemDropNotificationService = ItemDropNotificationService(masterDataStore: masterDataStore)
        let guildService = GuildService(
            coreDataStore: guildCoreDataStore,
            explorationCoreDataStore: explorationCoreDataStore
        )
        self.persistenceController = persistenceController
        self.guildService = guildService
        _masterDataStore = State(initialValue: masterDataStore)
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
        _shopStore = State(
            initialValue: ShopInventoryStore(
                service: guildService
            )
        )
        // Exploration and notification services are constructed once at app launch so background
        // resume and overlay state survive view re-composition.
        _explorationStore = State(
            initialValue: ExplorationStore(
                coreDataStore: explorationCoreDataStore,
                itemDropNotificationService: itemDropNotificationService,
                rosterStore: _rosterStore.wrappedValue
            )
        )
        _itemDropNotificationService = State(initialValue: itemDropNotificationService)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                masterDataStore: masterDataStore,
                rosterStore: rosterStore,
                partyStore: partyStore,
                equipmentStore: equipmentStore,
                persistenceController: persistenceController,
                shopStore: shopStore,
                explorationStore: explorationStore,
                itemDropNotificationService: itemDropNotificationService,
                guildService: guildService
            )
        }
    }
}
