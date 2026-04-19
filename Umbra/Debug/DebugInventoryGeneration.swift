// Defines debug inventory-generation presets and the deterministic batch builder used by the debug menu.

import Foundation

enum DebugCombinationCountPreset: String, CaseIterable, Identifiable {
    case tenThousand
    case fiftyThousand
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tenThousand:
            "1万"
        case .fiftyThousand:
            "5万"
        case .custom:
            "任意"
        }
    }

    func resolveValue(customText: String) throws -> Int {
        // The debug menu stores free-form text separately from the segmented preset, so each
        // preset resolves itself into the concrete generation count used by the batch builder.
        switch self {
        case .tenThousand:
            return 10_000
        case .fiftyThousand:
            return 50_000
        case .custom:
            guard let value = Int(customText), value > 0 else {
                throw DebugMenuInputError.invalidCombinationCount
            }
            return value
        }
    }
}

enum DebugStackCountPreset: String, CaseIterable, Identifiable {
    case one
    case fifty
    case ninetyNine
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one:
            "1"
        case .fifty:
            "50"
        case .ninetyNine:
            "99"
        case .custom:
            "任意"
        }
    }

    func resolveValue(customText: String) throws -> Int {
        // Stack-count presets follow the same pattern as combination-count presets so the UI can
        // switch between fixed options and one validated custom value.
        switch self {
        case .one:
            return 1
        case .fifty:
            return 50
        case .ninetyNine:
            return 99
        case .custom:
            guard let value = Int(customText), value > 0 else {
                throw DebugMenuInputError.invalidStackCount
            }
            return value
        }
    }
}

enum DebugMenuInputError: LocalizedError {
    case invalidCombinationCount
    case invalidStackCount

    var errorDescription: String? {
        switch self {
        case .invalidCombinationCount:
            "組み合わせ数は1以上で入力してください。"
        case .invalidStackCount:
            "スタック数は1以上で入力してください。"
        }
    }
}

struct DebugGeneratedInventoryBatch: Sendable {
    let inventoryStacks: [CompositeItemStack]
    let generatedCombinationCount: Int
}

struct DebugItemBatchGenerator: Sendable {
    private let baseItemIDs: [Int]
    private let jewelItemIDs: [Int]
    private let titleIDs: [Int]
    private let superRareIDs: [Int]

    init(masterData: MasterData) {
        baseItemIDs = masterData.items
            .filter { $0.category != .jewel }
            .map(\.id)
        jewelItemIDs = masterData.items
            .filter { $0.category == .jewel }
            .map(\.id)
        titleIDs = masterData.titles.map(\.id)
        superRareIDs = masterData.superRares.map(\.id)
    }

    var titleOnlyCombinationCount: Int {
        baseItemIDs.count * titleIDs.count
    }

    var superRareAndTitleCombinationCount: Int {
        baseItemIDs.count * superRareIDs.count * titleIDs.count
    }

    var jewelEnhancedCombinationCount: Int {
        baseItemIDs.count
            * superRareIDs.count
            * titleIDs.count
            * jewelItemIDs.count
            * superRareIDs.count
            * titleIDs.count
    }

    var totalCombinationCount: Int {
        titleOnlyCombinationCount + superRareAndTitleCombinationCount + jewelEnhancedCombinationCount
    }

    func generate(
        requestedCombinationCount: Int,
        stackCount: Int
    ) -> DebugGeneratedInventoryBatch {
        guard requestedCombinationCount > 0, stackCount > 0 else {
            return DebugGeneratedInventoryBatch(inventoryStacks: [], generatedCombinationCount: 0)
        }

        var inventoryStacks: [CompositeItemStack] = []
        inventoryStacks.reserveCapacity(min(requestedCombinationCount, totalCombinationCount))

        func append(_ itemID: CompositeItemID) -> Bool {
            inventoryStacks.append(CompositeItemStack(itemID: itemID, count: stackCount))
            return inventoryStacks.count == requestedCombinationCount
        }

        // The loops deliberately exhaust lower-complexity combinations first so the generated test
        // data remains predictable for smaller requested sample sizes.
        for baseItemID in baseItemIDs {
            for titleID in titleIDs {
                if append(CompositeItemID.baseItem(itemId: baseItemID, titleId: titleID)) {
                    return DebugGeneratedInventoryBatch(
                        inventoryStacks: inventoryStacks,
                        generatedCombinationCount: inventoryStacks.count
                    )
                }
            }
        }

        for baseItemID in baseItemIDs {
            for superRareID in superRareIDs {
                for titleID in titleIDs {
                    if append(
                        CompositeItemID.baseItem(
                            itemId: baseItemID,
                            titleId: titleID,
                            superRareId: superRareID
                        )
                    ) {
                        return DebugGeneratedInventoryBatch(
                            inventoryStacks: inventoryStacks,
                            generatedCombinationCount: inventoryStacks.count
                        )
                    }
                }
            }
        }

        for baseItemID in baseItemIDs {
            for baseSuperRareID in superRareIDs {
                for baseTitleID in titleIDs {
                    for jewelItemID in jewelItemIDs {
                        for jewelSuperRareID in superRareIDs {
                            for jewelTitleID in titleIDs {
                                if append(
                                    CompositeItemID(
                                        baseSuperRareId: baseSuperRareID,
                                        baseTitleId: baseTitleID,
                                        baseItemId: baseItemID,
                                        jewelSuperRareId: jewelSuperRareID,
                                        jewelTitleId: jewelTitleID,
                                        jewelItemId: jewelItemID
                                    )
                                ) {
                                    return DebugGeneratedInventoryBatch(
                                        inventoryStacks: inventoryStacks,
                                        generatedCombinationCount: inventoryStacks.count
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        return DebugGeneratedInventoryBatch(
            inventoryStacks: inventoryStacks,
            generatedCombinationCount: inventoryStacks.count
        )
    }
}
