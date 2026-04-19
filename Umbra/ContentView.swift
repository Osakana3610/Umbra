// Shows app loading state and routes into the guild dashboard once data is ready.

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController: PersistenceController
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let shopStore: ShopInventoryStore
    let explorationStore: ExplorationStore
    let itemDropNotificationService: ItemDropNotificationService
    let equipmentStatusNotificationService: EquipmentStatusNotificationService
    let guildServices: GuildServices

    var body: some View {
        let masterData = MasterData.current

        Group {
            switch (rosterStore.phase, partyStore.phase) {
            case (.idle, _), (.loading, _), (_, .idle), (_, .loading):
                ProgressView("データを読み込み中")
            case let (.failed(message), _), let (_, .failed(message)):
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "読み込みに失敗しました",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                    Button("再読み込み") {
                        rosterStore.reload()
                        partyStore.reload()
                    }
                }
                .padding()
            case (.loaded, .loaded):
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
            rosterStore.loadIfNeeded()
            partyStore.loadIfNeeded()
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
    let itemDropNotificationService = ItemDropNotificationService(masterData: MasterData.current)
    let equipmentStatusNotificationService = EquipmentStatusNotificationService()
    let rosterStore = GuildRosterStore(coreDataRepository: guildCoreDataRepository, service: guildServices.roster, phase: .loading)
    return ContentView(
        persistenceController: persistenceController,
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
