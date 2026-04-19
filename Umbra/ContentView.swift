// Shows app loading state and routes into the guild dashboard once data is ready.

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController: PersistenceController
    let masterDataStore: MasterDataLoadStore
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let shopStore: ShopInventoryStore
    let explorationStore: ExplorationStore
    let itemDropNotificationService: ItemDropNotificationService
    let equipmentStatusNotificationService: EquipmentStatusNotificationService
    let guildServices: GuildServices

    var body: some View {
        Group {
            switch (masterDataStore.phase, rosterStore.phase, partyStore.phase) {
            case (.idle, _, _), (.loading, _, _), (_, .idle, _), (_, .loading, _), (_, _, .idle), (_, _, .loading):
                // The shell waits for master data, roster, and party state together because all
                // three are required to construct the tab hierarchy coherently.
                ProgressView("マスターデータを読み込み中")
            case let (.failed(message), _, _), let (_, .failed(message), _), let (_, _, .failed(message)):
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "読み込みに失敗しました",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                    Button("再読み込み") {
                        Task {
                            // Master data reload is async, while roster and party reload from local
                            // persistence synchronously on the main actor.
                            async let masterDataReload = masterDataStore.reload()
                            rosterStore.reload()
                            partyStore.reload()
                            _ = await masterDataReload
                        }
                    }
                }
                .padding()
            case let (.loaded(masterData), .loaded, .loaded):
                RootTabView(
                    masterData: masterData,
                    persistenceController: persistenceController,
                    rosterStore: rosterStore,
                    partyStore: partyStore,
                    equipmentStore: equipmentStore,
                    shopStore: shopStore,
                    explorationStore: explorationStore,
                    itemDropNotificationService: itemDropNotificationService,
                    equipmentStatusNotificationService: equipmentStatusNotificationService,
                    guildServices: guildServices
                )
                .task {
                    guard scenePhase == .active else {
                        return
                    }

                    // Foreground entry replays background progress before the user interacts with
                    // the tab UI so pending rewards and auto-runs are visible immediately.
                    await explorationStore.resumeBackgroundProgress(
                        reopenedAt: Date(),
                        partyStore: partyStore,
                        partyService: guildServices.parties,
                        masterData: masterData
                    )
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        explorationStore.recordBackgroundedAt(
                            Date(),
                            partyService: guildServices.parties
                        )
                    } else {
                        Task {
                            await explorationStore.resumeBackgroundProgress(
                                reopenedAt: Date(),
                                partyStore: partyStore,
                                partyService: guildServices.parties,
                                masterData: masterData
                            )
                        }
                    }
                }
            }
        }
        .task {
            // Startup loads master data and local stores in parallel to minimize time spent on the
            // initial loading screen.
            async let masterDataLoad = masterDataStore.loadIfNeeded()
            rosterStore.loadIfNeeded()
            partyStore.loadIfNeeded()
            _ = await masterDataLoad
        }
    }
}

#Preview {
    let persistenceController = PersistenceController.preview
    let guildCoreDataRepository = GuildCoreDataRepository(container: persistenceController.container)
    let guildServices = GuildServices(
        coreDataRepository: guildCoreDataRepository,
        explorationCoreDataRepository: ExplorationCoreDataRepository(container: persistenceController.container)
    )
    let masterDataStore = MasterDataLoadStore(phase: .loading)
    let itemDropNotificationService = ItemDropNotificationService(masterDataStore: masterDataStore)
    let equipmentStatusNotificationService = EquipmentStatusNotificationService()
    let rosterStore = GuildRosterStore(coreDataRepository: guildCoreDataRepository, service: guildServices.roster, phase: .loading)
    return ContentView(
        persistenceController: persistenceController,
        masterDataStore: masterDataStore,
        rosterStore: rosterStore,
        partyStore: PartyStore(coreDataRepository: guildCoreDataRepository, service: guildServices.parties, phase: .loading),
        equipmentStore: EquipmentInventoryStore(
            coreDataRepository: guildCoreDataRepository,
            service: guildServices.equipment,
            equipmentStatusNotificationService: equipmentStatusNotificationService
        ),
        shopStore: ShopInventoryStore(service: guildServices.shop),
        explorationStore: ExplorationStore(
            coreDataRepository: ExplorationCoreDataRepository(container: persistenceController.container),
            itemDropNotificationService: itemDropNotificationService,
            rosterStore: rosterStore,
            equipmentStore: EquipmentInventoryStore(
                coreDataRepository: guildCoreDataRepository,
                service: guildServices.equipment,
                equipmentStatusNotificationService: equipmentStatusNotificationService
            ),
            shopStore: ShopInventoryStore(service: guildServices.shop)
        ),
        itemDropNotificationService: itemDropNotificationService,
        equipmentStatusNotificationService: equipmentStatusNotificationService,
        guildServices: guildServices
    )
}
