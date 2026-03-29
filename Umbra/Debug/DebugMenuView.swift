// Hosts debug-only inventory generation controls for large equipment test datasets.

import SwiftUI

struct DebugMenuView: View {
    let masterData: MasterData
    let equipmentRepository: EquipmentRepository
    let equipmentStore: EquipmentInventoryStore

    @State private var combinationCountPreset: DebugCombinationCountPreset = .tenThousand
    @State private var customCombinationCountText = ""
    @State private var stackCountPreset: DebugStackCountPreset = .one
    @State private var customStackCountText = ""
    @State private var isGenerating = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private var generator: DebugItemBatchGenerator {
        DebugItemBatchGenerator(masterData: masterData)
    }

    var body: some View {
        Form {
            Section("生成対象") {
                Text("称号のみ → 超レア+称号 → 超レア+称号+宝石強化 の順で生成します。")
                Text("要求件数に足りない場合は次のグループへ進み、全組み合わせを使い切ったらそこで終了します。")
                    .foregroundStyle(.secondary)
            }

            Section("組み合わせ数") {
                Picker("組み合わせ数", selection: $combinationCountPreset) {
                    ForEach(DebugCombinationCountPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                if combinationCountPreset == .custom {
                    TextField("任意件数", text: $customCombinationCountText)
                        .keyboardType(.numberPad)
                }
            }

            Section("スタック数") {
                Picker("スタック数", selection: $stackCountPreset) {
                    ForEach(DebugStackCountPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                if stackCountPreset == .custom {
                    TextField("任意スタック数", text: $customStackCountText)
                        .keyboardType(.numberPad)
                }
            }

            Section("候補数") {
                Text("称号のみ: \(generator.titleOnlyCombinationCount.formatted()) 件")
                Text("超レア+称号: \(generator.superRareAndTitleCombinationCount.formatted()) 件")
                Text("超レア+称号+宝石強化: \(generator.jewelEnhancedCombinationCount.formatted()) 件")
                Text("合計: \(generator.totalCombinationCount.formatted()) 件")
                    .fontWeight(.semibold)
            }

            Section {
                Button {
                    Task {
                        await generateInventory()
                    }
                } label: {
                    if isGenerating {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("生成中...")
                        }
                    } else {
                        Text("デバッグ用アイテムを生成")
                    }
                }
                .disabled(isGenerating)
            }

            if let resultMessage {
                Section("結果") {
                    Text(resultMessage)
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section("エラー") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func generateInventory() async {
        guard !isGenerating else {
            return
        }

        isGenerating = true
        resultMessage = nil
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let requestedCombinationCount = try resolvedCombinationCount()
            let stackCount = try resolvedStackCount()
            let batch = generator.generate(
                requestedCombinationCount: requestedCombinationCount,
                stackCount: stackCount
            )

            guard batch.generatedCombinationCount > 0 else {
                resultMessage = "生成可能な組み合わせがありませんでした。"
                return
            }

            try equipmentRepository.addInventoryStacks(batch.inventoryStacks, masterData: masterData)
            if equipmentStore.isLoaded {
                try equipmentStore.reload(masterData: masterData)
            }

            let generatedItemCount = batch.generatedCombinationCount * stackCount
            if batch.generatedCombinationCount < requestedCombinationCount {
                resultMessage = "\(batch.generatedCombinationCount.formatted()) 件の組み合わせを生成しました。要求 \(requestedCombinationCount.formatted()) 件に対し、生成可能な全組み合わせを使い切りました。総追加数は \(generatedItemCount.formatted()) 個です。"
            } else {
                resultMessage = "\(batch.generatedCombinationCount.formatted()) 件の組み合わせを生成しました。総追加数は \(generatedItemCount.formatted()) 個です。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedCombinationCount() throws -> Int {
        try combinationCountPreset.resolveValue(customText: customCombinationCountText)
    }

    private func resolvedStackCount() throws -> Int {
        try stackCountPreset.resolveValue(customText: customStackCountText)
    }
}

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
