import SwiftUI
import CoreData

// Boots the app shell and wires persistence plus master-data loading state.

@main
struct UmbraApp: App {
    let persistenceController = PersistenceController.shared
    @State private var masterDataStore = MasterDataStore()

    var body: some Scene {
        WindowGroup {
            ContentView(masterDataStore: masterDataStore)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
