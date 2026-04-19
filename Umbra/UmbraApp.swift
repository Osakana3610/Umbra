// Boots the app shell and wires persistence, master data, and guild runtime state.

import SwiftUI

@main
struct UmbraApp: App {
    let persistenceController: PersistenceController
    let guildServices: GuildServices
    @State private var masterDataStore: MasterDataLoadStore
    @State private var rosterStore: GuildRosterStore
    @State private var partyStore: PartyStore
    @State private var equipmentStore: EquipmentInventoryStore
    @State private var shopStore: ShopInventoryStore
    @State private var explorationStore: ExplorationStore
    @State private var itemDropNotificationService: ItemDropNotificationService
    @State private var equipmentStatusNotificationService: EquipmentStatusNotificationService

    init() {
        // Construct the persistence-backed services once here so every tab observes the same
        // long-lived store graph.
        let persistenceController = PersistenceController.shared
        let guildCoreDataRepository = GuildCoreDataRepository(container: persistenceController.container)
        let explorationCoreDataRepository = ExplorationCoreDataRepository(container: persistenceController.container)
        let masterDataStore = MasterDataLoadStore()
        let itemDropNotificationService = ItemDropNotificationService(masterDataStore: masterDataStore)
        let equipmentStatusNotificationService = EquipmentStatusNotificationService()
        let guildServices = GuildServices(
            coreDataRepository: guildCoreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        self.persistenceController = persistenceController
        self.guildServices = guildServices
        _masterDataStore = State(initialValue: masterDataStore)
        _rosterStore = State(
            initialValue: GuildRosterStore(
                coreDataRepository: guildCoreDataRepository,
                service: guildServices.roster
            )
        )
        _partyStore = State(
            initialValue: PartyStore(
                coreDataRepository: guildCoreDataRepository,
                service: guildServices.parties
            )
        )
        _equipmentStore = State(
            initialValue: EquipmentInventoryStore(
                coreDataRepository: guildCoreDataRepository,
                service: guildServices.equipment,
                equipmentStatusNotificationService: equipmentStatusNotificationService
            )
        )
        _shopStore = State(
            initialValue: ShopInventoryStore(
                service: guildServices.shop
            )
        )
        // Exploration and notification services are constructed once at app launch so background
        // resume and overlay state survive view re-composition.
        _explorationStore = State(
            initialValue: ExplorationStore(
                coreDataRepository: explorationCoreDataRepository,
                itemDropNotificationService: itemDropNotificationService,
                rosterStore: _rosterStore.wrappedValue,
                equipmentStore: _equipmentStore.wrappedValue,
                shopStore: _shopStore.wrappedValue
            )
        )
        _itemDropNotificationService = State(initialValue: itemDropNotificationService)
        _equipmentStatusNotificationService = State(initialValue: equipmentStatusNotificationService)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                persistenceController: persistenceController,
                masterDataStore: masterDataStore,
                rosterStore: rosterStore,
                partyStore: partyStore,
                equipmentStore: equipmentStore,
                shopStore: shopStore,
                explorationStore: explorationStore,
                itemDropNotificationService: itemDropNotificationService,
                equipmentStatusNotificationService: equipmentStatusNotificationService,
                guildServices: guildServices
            )
        }
    }
}
