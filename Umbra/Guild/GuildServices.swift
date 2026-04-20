// Defines the guild-domain service bundle and shared result types used across roster, party,
// inventory, shop, and equipment flows.
// The app passes this bundle around as the guild write API so views and stores can depend on one
// stable composition root instead of reconstructing service graphs ad hoc.

import Foundation

struct HireCharacterResult: Sendable {
    let playerState: PlayerState
    let character: CharacterRecord
    let hireCost: Int
}

struct EconomicCapJewelSelection: Identifiable, Equatable, Sendable {
    let itemID: CompositeItemID
    let characterId: Int?

    var id: String {
        if let characterId {
            // Equipped jewels need the owner encoded into identity because the same composite item can
            // appear on multiple characters at once.
            return "\(itemID.stableKey)|\(characterId)"
        }
        return itemID.stableKey
    }
}

enum GuildServiceError: LocalizedError {
    case invalidHireSelection
    case insufficientGold(required: Int, available: Int)
    case maxPartyCountReached
    case partyUnlockRequiresCapJewel
    case invalidPartyUnlockJewel
    case invalidParty(partyId: Int)
    case invalidJobChangeTarget(jobId: Int)
    case invalidPartyName
    case partyFull(partyId: Int)
    case characterNotFound(characterId: Int)
    case characterAlreadyChangedJob(characterId: Int)
    case jobChangeRequirementNotMet(jobId: Int)
    case invalidPartyMemberOrder
    case invalidItemStack
    case invalidStackCount
    case inventoryItemUnavailable
    case shopItemUnavailable
    case stockOrganizationUnavailable
    case equipLimitReached(maximumCount: Int)
    case equippedItemNotFound
    case invalidCharacterName
    case characterNotDefeated(characterId: Int)
    case invalidCharacterState(characterId: Int)
    case invalidJewelEnhancement
    case invalidJewelExtraction

    var errorDescription: String? {
        switch self {
        case .invalidHireSelection:
            "雇用条件が不正です。"
        case .insufficientGold(let required, let available):
            "所持金が不足しています。必要=\(required) 現在=\(available)"
        case .maxPartyCountReached:
            "これ以上パーティを解放できません。"
        case .partyUnlockRequiresCapJewel:
            "このパーティ枠の解放には99,999,999G相当の宝石が必要です。"
        case .invalidPartyUnlockJewel:
            "解放条件を満たす宝石ではありません。"
        case .invalidParty(let partyId):
            "パーティが見つかりません。 partyId=\(partyId)"
        case .invalidJobChangeTarget(let jobId):
            "転職先の職業が不正です。 jobId=\(jobId)"
        case .invalidPartyName:
            "パーティ名を入力してください。"
        case .partyFull(let partyId):
            "パーティ\(partyId)はすでに6人です。"
        case .characterNotFound(let characterId):
            "キャラクターが見つかりません。 characterId=\(characterId)"
        case .characterAlreadyChangedJob(let characterId):
            "キャラクター\(characterId)はすでに転職済みです。"
        case .jobChangeRequirementNotMet(let jobId):
            "転職条件を満たしていません。 jobId=\(jobId)"
        case .invalidPartyMemberOrder:
            "パーティ編成の並び順が不正です。"
        case .invalidItemStack:
            "アイテム定義が不正です。"
        case .invalidStackCount:
            "スタック数は1以上で指定してください。"
        case .inventoryItemUnavailable:
            "対象アイテムを所持していません。"
        case .shopItemUnavailable:
            "商店に対象アイテムがありません。"
        case .stockOrganizationUnavailable:
            "在庫整理の条件を満たしていません。"
        case .equipLimitReached(let maximumCount):
            "これ以上装備できません。装備上限は\(maximumCount)件です。"
        case .equippedItemNotFound:
            "装備中のアイテムが見つかりません。"
        case .invalidCharacterName:
            "名前を入力してください。"
        case .characterNotDefeated(let characterId):
            "キャラクターは戦闘不能ではありません。 characterId=\(characterId)"
        case .invalidCharacterState(let characterId):
            "キャラクター状態が不正です。 characterId=\(characterId)"
        case .invalidJewelEnhancement:
            "宝石強化の組み合わせが不正です。"
        case .invalidJewelExtraction:
            "宝石を外せないアイテムです。"
        }
    }
}

@MainActor
struct GuildServices {
    let roster: GuildRosterService
    let parties: PartyManagementService
    let inventory: InventoryManagementService
    let shop: ShopTradingService
    let equipment: EquipmentMutationService

    init(
        coreDataRepository: GuildCoreDataRepository,
        explorationCoreDataRepository: ExplorationCoreDataRepository
    ) {
        // All guild-facing services share the same repositories so mutations observe one coherent
        // persistence view and exploration safety checks.
        roster = GuildRosterService(
            coreDataRepository: coreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        parties = PartyManagementService(
            coreDataRepository: coreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
        inventory = InventoryManagementService(coreDataRepository: coreDataRepository)
        shop = ShopTradingService(coreDataRepository: coreDataRepository)
        equipment = EquipmentMutationService(
            coreDataRepository: coreDataRepository,
            explorationCoreDataRepository: explorationCoreDataRepository
        )
    }
}
