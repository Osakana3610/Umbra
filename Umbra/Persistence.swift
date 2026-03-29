// Configures the Core Data stack used by the app's persistent repositories.

import CoreData
import Foundation

struct PersistenceController {
    static let shared = makeSharedController()

    @MainActor
    static let preview: PersistenceController = {
        PersistenceController(inMemory: true)
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Umbra")
        if let firstDescription = container.persistentStoreDescriptions.first {
            firstDescription.shouldMigrateStoreAutomatically = true
            firstDescription.shouldInferMappingModelAutomatically = true

            if inMemory {
                firstDescription.url = URL(fileURLWithPath: "/dev/null")
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil
    }

    private static func makeSharedController() -> PersistenceController {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
        return PersistenceController(
            inMemory: arguments.contains("UITestInMemoryStore") || isRunningTests
        )
    }
}
