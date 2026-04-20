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
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [description]
        } else if let firstDescription = container.persistentStoreDescriptions.first {
            firstDescription.shouldMigrateStoreAutomatically = true
            firstDescription.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        if inMemory {
            let context = container.viewContext
            for entityName in container.managedObjectModel.entities.compactMap(\.name) {
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                let objects = (try? context.fetch(request)) ?? []
                for object in objects {
                    context.delete(object)
                }
            }
            if context.hasChanges {
                try? context.save()
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
