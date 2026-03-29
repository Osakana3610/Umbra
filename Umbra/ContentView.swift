import SwiftUI

// Shows app loading state and routes into the guild dashboard once data is ready.

struct ContentView: View {
    let masterDataStore: MasterDataStore
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore
    let guildService: GuildService

    var body: some View {
        Group {
            switch (masterDataStore.phase, rosterStore.phase, partyStore.phase) {
            case (.idle, _, _), (.loading, _, _), (_, .idle, _), (_, .loading, _), (_, _, .idle), (_, _, .loading):
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
                    rosterStore: rosterStore,
                    partyStore: partyStore,
                    equipmentStore: equipmentStore,
                    explorationStore: explorationStore,
                    guildService: guildService
                )
            }
        }
        .task {
            async let masterDataLoad = masterDataStore.loadIfNeeded()
            rosterStore.loadIfNeeded()
            partyStore.loadIfNeeded()
            _ = await masterDataLoad
        }
    }
}

#Preview {
    let persistenceController = PersistenceController.preview
    let guildCoreDataStore = GuildCoreDataStore(container: persistenceController.container)
    let guildService = GuildService(
        coreDataStore: guildCoreDataStore,
        explorationCoreDataStore: ExplorationCoreDataStore(container: persistenceController.container)
    )
    return ContentView(
        masterDataStore: MasterDataStore(phase: .loading),
        rosterStore: GuildRosterStore(coreDataStore: guildCoreDataStore, service: guildService, phase: .loading),
        partyStore: PartyStore(coreDataStore: guildCoreDataStore, service: guildService, phase: .loading),
        equipmentStore: EquipmentInventoryStore(coreDataStore: guildCoreDataStore, service: guildService),
        explorationStore: ExplorationStore(
            coreDataStore: ExplorationCoreDataStore(container: persistenceController.container)
        ),
        guildService: guildService
    )
}
