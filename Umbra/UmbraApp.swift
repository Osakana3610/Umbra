// Boots the app shell and wires persistence, master data, and guild runtime state.

import SwiftUI

@main
struct UmbraApp: App {
    let persistenceController: PersistenceController
    @State private var masterDataStore: MasterDataStore
    @State private var guildStore: GuildStore

    init() {
        let persistenceController = PersistenceController.shared
        self.persistenceController = persistenceController
        _masterDataStore = State(initialValue: MasterDataStore())
        _guildStore = State(
            initialValue: GuildStore(
                repository: GuildRepository(container: persistenceController.container)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(masterDataStore: masterDataStore, guildStore: guildStore)
        }
    }
}
