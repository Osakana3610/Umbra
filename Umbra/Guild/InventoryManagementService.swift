// Owns inventory-ingress mutations that add validated item stacks into shared storage.

import Foundation

@MainActor
final class InventoryManagementService {
    private let coreDataRepository: GuildCoreDataRepository

    init(coreDataRepository: GuildCoreDataRepository) {
        self.coreDataRepository = coreDataRepository
    }

    func addInventoryStacks(
        _ inventoryStacks: [CompositeItemStack],
        masterData: MasterData
    ) throws {
        guard !inventoryStacks.isEmpty else {
            return
        }

        // Debug and reward flows both inject prepared stacks here, so every incoming stack is
        // validated before the shared inventory snapshot is merged and persisted.
        for stack in inventoryStacks {
            guard stack.count > 0 else {
                throw GuildServiceError.invalidStackCount
            }
            guard stack.itemID.isValid(in: masterData) else {
                throw GuildServiceError.invalidItemStack
            }
        }

        let allInventoryStacks = (try coreDataRepository.loadInventoryStacks() + inventoryStacks)
            .normalizedCompositeItemStacks()
        try coreDataRepository.saveInventoryStacks(allInventoryStacks)
    }
}
