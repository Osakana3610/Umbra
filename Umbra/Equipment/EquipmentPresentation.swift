// Shares lightweight display helpers for equipment inventory and character summaries.

import Foundation

struct EquipmentDisplayNameResolver {
    private let itemsByID: [Int: MasterData.Item]
    private let titlesByID: [Int: MasterData.Title]
    private let superRaresByID: [Int: MasterData.SuperRare]

    init(masterData: MasterData) {
        itemsByID = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        titlesByID = Dictionary(uniqueKeysWithValues: masterData.titles.map { ($0.id, $0) })
        superRaresByID = Dictionary(uniqueKeysWithValues: masterData.superRares.map { ($0.id, $0) })
    }

    func displayName(for itemID: CompositeItemID) -> String {
        let baseName = prefixedName(
            itemName: itemsByID[itemID.baseItemId]?.name ?? "不明なアイテム",
            titleName: titlesByID[itemID.baseTitleId]?.name,
            superRareName: superRaresByID[itemID.baseSuperRareId]?.name
        )

        guard itemID.jewelItemId > 0 else {
            return baseName
        }

        let jewelName = prefixedName(
            itemName: itemsByID[itemID.jewelItemId]?.name ?? "不明な宝石",
            titleName: titlesByID[itemID.jewelTitleId]?.name,
            superRareName: superRaresByID[itemID.jewelSuperRareId]?.name
        )
        return "\(baseName)[\(jewelName)]"
    }

    private func prefixedName(
        itemName: String,
        titleName: String?,
        superRareName: String?
    ) -> String {
        ([superRareName, titleName].compactMap {
            guard let value = $0, !value.isEmpty else {
                return nil
            }
            return value
        } + [itemName]).joined()
    }
}

extension CharacterRecord {
    var maximumEquippedItemCount: Int {
        3 + Int((Double(level) / 20).rounded())
    }

    var equippedItemCount: Int {
        equippedItemStacks.reduce(into: 0) { partialResult, stack in
            partialResult += stack.count
        }
    }
}

extension MasterData {
    func raceName(for raceID: Int) -> String {
        races.first(where: { $0.id == raceID })?.name ?? "不明"
    }

    func jobName(for jobID: Int) -> String {
        jobs.first(where: { $0.id == jobID })?.name ?? "不明"
    }

    func jobDisplayName(for character: CharacterRecord) -> String {
        let currentJobName = jobName(for: character.currentJobId)
        guard character.previousJobId != 0 else {
            return currentJobName
        }

        return "\(currentJobName)（\(jobName(for: character.previousJobId))）"
    }

    func aptitudeName(for aptitudeID: Int) -> String {
        aptitudes.first(where: { $0.id == aptitudeID })?.name ?? "不明"
    }

    func characterSummaryText(for character: CharacterRecord) -> String {
        "Lv.\(character.level) / \(raceName(for: character.raceId)) / \(jobDisplayName(for: character)) / \(aptitudeName(for: character.aptitudeId))"
    }
}

extension ItemCategory {
    var sortOrder: Int {
        switch self {
        case .sword:
            0
        case .katana:
            1
        case .bow:
            2
        case .wand:
            3
        case .rod:
            4
        case .armor:
            5
        case .shield:
            6
        case .robe:
            7
        case .gauntlet:
            8
        case .jewel:
            9
        case .misc:
            10
        }
    }

    var displayName: String {
        switch self {
        case .sword:
            "剣"
        case .katana:
            "刀"
        case .bow:
            "弓"
        case .wand:
            "短杖"
        case .rod:
            "杖"
        case .armor:
            "鎧"
        case .shield:
            "盾"
        case .robe:
            "ローブ"
        case .gauntlet:
            "籠手"
        case .jewel:
            "宝石"
        case .misc:
            "その他"
        }
    }
}

extension ItemRarity {
    var sortOrder: Int {
        switch self {
        case .normal:
            1
        case .uncommon:
            2
        case .rare:
            3
        case .mythic:
            4
        case .godfiend:
            5
        }
    }
}
