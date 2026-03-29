// Defines the domain model used to resolve and render deterministic single battles.

import Foundation

enum BattleOutcome: String, Codable, Equatable, Sendable {
    case victory
    case draw
    case defeat
}

enum BattleSide: String, Codable, Equatable, Sendable {
    case ally
    case enemy
}

enum BattleLogActionKind: String, Codable, Equatable, Sendable {
    case breath
    case attack
    case recoverySpell
    case attackSpell
    case defend
    case rescue
    case counter
    case extraAttack
    case pursuit
}

enum BattleActionFlag: String, Codable, Equatable, Sendable {
    case critical
}

enum BattleTargetResultKind: String, Codable, Equatable, Sendable {
    case damage
    case heal
    case miss
    case modifierApplied
    case ailmentRemoved
}

enum BattleTargetResultFlag: String, Codable, Equatable, Sendable {
    case defeated
    case revived
    case guarded
}

enum BattleAilment: Int, Codable, Equatable, Sendable {
    case sleep = 1
}

struct BattleContext: Codable, Equatable, Sendable {
    let runId: String
    let rootSeed: UInt64
    let floorNumber: Int
    let battleNumber: Int
}

struct BattleEnemySeed: Codable, Equatable, Sendable {
    let enemyId: Int
    let level: Int
}

struct BattleCombatantID: RawRepresentable, Codable, Hashable, Equatable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct BattleTargetResult: Codable, Equatable, Sendable {
    let targetId: BattleCombatantID
    let resultKind: BattleTargetResultKind
    let value: Int?
    let statusId: Int?
    let flags: [BattleTargetResultFlag]
}

struct BattleActionRecord: Codable, Equatable, Sendable {
    let actorId: BattleCombatantID
    let actionKind: BattleLogActionKind
    let actionRef: Int?
    let actionFlags: [BattleActionFlag]
    let targetIds: [BattleCombatantID]
    let results: [BattleTargetResult]
}

struct BattleTurnRecord: Codable, Equatable, Sendable {
    let turnNumber: Int
    let actions: [BattleActionRecord]
}

struct BattleRecord: Codable, Equatable, Sendable {
    let runId: String
    let floorNumber: Int
    let battleNumber: Int
    let result: BattleOutcome
    let turns: [BattleTurnRecord]
}

struct BattleCombatantSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: BattleCombatantID
    let name: String
    let side: BattleSide
    let level: Int
    let maxHP: Int
    let remainingHP: Int
    let formationIndex: Int
}

struct SingleBattleResult: Equatable, Sendable {
    let context: BattleContext
    let battleRecord: BattleRecord
    let combatants: [BattleCombatantSnapshot]

    var result: BattleOutcome {
        battleRecord.result
    }

    var partyRemainingHPs: [Int] {
        combatants
            .filter { $0.side == .ally }
            .sorted { $0.formationIndex < $1.formationIndex }
            .map(\.remainingHP)
    }
}

enum SingleBattleError: LocalizedError {
    case emptyParty
    case invalidPartyMember(Int)
    case invalidEnemy(Int)

    var errorDescription: String? {
        switch self {
        case .emptyParty:
            "パーティメンバーがいません。"
        case let .invalidPartyMember(characterId):
            "戦闘開始に必要なキャラクター情報が不足しています。characterId=\(characterId)"
        case let .invalidEnemy(enemyId):
            "戦闘開始に必要な敵情報が不足しています。enemyId=\(enemyId)"
        }
    }
}
