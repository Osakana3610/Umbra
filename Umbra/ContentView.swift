import SwiftUI

// Shows app loading state and routes into the guild dashboard once data is ready.

struct ContentView: View {
    let masterDataStore: MasterDataStore
    let guildStore: GuildStore

    var body: some View {
        Group {
            switch (masterDataStore.phase, guildStore.phase) {
            case (.idle, _), (.loading, _), (_, .idle), (_, .loading):
                ProgressView("マスターデータを読み込み中")
            case let (.failed(message), _), let (_, .failed(message)):
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "読み込みに失敗しました",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                    Button("再読み込み") {
                        Task {
                            async let masterDataReload = masterDataStore.reload()
                            async let guildReload = guildStore.reload()
                            _ = await (masterDataReload, guildReload)
                        }
                    }
                }
                .padding()
            case let (.loaded(masterData), .loaded):
                RootTabView(masterData: masterData, guildStore: guildStore)
            }
        }
        .task {
            async let masterDataLoad = masterDataStore.loadIfNeeded()
            async let guildLoad = guildStore.loadIfNeeded()
            _ = await (masterDataLoad, guildLoad)
        }
    }
}

#Preview {
    let persistenceController = PersistenceController.preview
    let guildRepository = GuildRepository(container: persistenceController.container)
    return ContentView(
        masterDataStore: MasterDataStore(phase: .loading),
        guildStore: GuildStore(phase: .loading, repository: guildRepository)
    )
}
