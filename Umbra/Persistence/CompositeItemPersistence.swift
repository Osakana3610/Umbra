// Bridges composite equipment identities to Core Data's six-column storage layout.

import CoreData
import Foundation

protocol CompositeItemIdentityManagedObject: AnyObject {
    nonisolated var baseSuperRareIdValue: Int64 { get set }
    nonisolated var baseTitleIdValue: Int64 { get set }
    nonisolated var baseItemIdValue: Int64 { get set }
    nonisolated var jewelSuperRareIdValue: Int64 { get set }
    nonisolated var jewelTitleIdValue: Int64 { get set }
    nonisolated var jewelItemIdValue: Int64 { get set }
}

enum CompositeItemPersistence {
    nonisolated static func predicate(for itemID: CompositeItemID) -> NSPredicate {
        NSPredicate(
            format: """
            baseSuperRareIdValue == %d AND baseTitleIdValue == %d AND baseItemIdValue == %d AND \
            jewelSuperRareIdValue == %d AND jewelTitleIdValue == %d AND jewelItemIdValue == %d
            """,
            itemID.baseSuperRareId,
            itemID.baseTitleId,
            itemID.baseItemId,
            itemID.jewelSuperRareId,
            itemID.jewelTitleId,
            itemID.jewelItemId
        )
    }

    nonisolated static func predicate<S: Sequence>(for itemIDs: S) -> NSPredicate? where S.Element == CompositeItemID {
        let predicates = itemIDs.map(predicate(for:))
        guard !predicates.isEmpty else {
            return nil
        }

        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    nonisolated static var sortDescriptors: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "baseItemIdValue", ascending: true),
            NSSortDescriptor(key: "baseSuperRareIdValue", ascending: true),
            NSSortDescriptor(key: "baseTitleIdValue", ascending: true),
            NSSortDescriptor(key: "jewelItemIdValue", ascending: true),
            NSSortDescriptor(key: "jewelSuperRareIdValue", ascending: true),
            NSSortDescriptor(key: "jewelTitleIdValue", ascending: true)
        ]
    }
}

extension CompositeItemID {
    nonisolated init(entity: some CompositeItemIdentityManagedObject) {
        self.init(
            baseSuperRareId: Int(entity.baseSuperRareIdValue),
            baseTitleId: Int(entity.baseTitleIdValue),
            baseItemId: Int(entity.baseItemIdValue),
            jewelSuperRareId: Int(entity.jewelSuperRareIdValue),
            jewelTitleId: Int(entity.jewelTitleIdValue),
            jewelItemId: Int(entity.jewelItemIdValue)
        )
    }

    nonisolated func apply(to entity: some CompositeItemIdentityManagedObject) {
        entity.baseSuperRareIdValue = Int64(baseSuperRareId)
        entity.baseTitleIdValue = Int64(baseTitleId)
        entity.baseItemIdValue = Int64(baseItemId)
        entity.jewelSuperRareIdValue = Int64(jewelSuperRareId)
        entity.jewelTitleIdValue = Int64(jewelTitleId)
        entity.jewelItemIdValue = Int64(jewelItemId)
    }
}

extension InventoryItemEntity: CompositeItemIdentityManagedObject {}
extension PlayerStateAutoSellItemEntity: CompositeItemIdentityManagedObject {}
extension RunSessionDropRewardEntity: CompositeItemIdentityManagedObject {}
extension ShopItemEntity: CompositeItemIdentityManagedObject {}
extension CharacterEquippedItemEntity: CompositeItemIdentityManagedObject {}
extension RunSessionMemberEquippedItemEntity: CompositeItemIdentityManagedObject {}
