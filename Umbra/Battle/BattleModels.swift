// Defines the domain model used to resolve and render deterministic single battles.

import Foundation

nonisolated protocol PersistenceOrderRepresentable: Sendable {
    nonisolated var persistenceOrder: Int { get }

    nonisolated init?(persistenceOrder: Int)
}

nonisolated enum BattleOutcome: String, Codable, Equatable, Sendable {
    case victory
    case draw
    case defeat
}

nonisolated enum BattleSide: String, Codable, Equatable, Sendable {
    case ally
    case enemy
}

nonisolated enum BattleLogActionKind: String, Codable, Equatable, Sendable {
    case breath
    case attack
    case unarmedRepeat
    case recoverySpell
    case attackSpell
    case defend
    case rescue
    case counter
    case extraAttack
    case pursuit
}

nonisolated enum BattleActionFlag: String, Codable, Equatable, Sendable {
    case critical
}

nonisolated enum BattleTargetResultKind: String, Codable, Equatable, Sendable {
    case damage
    case heal
    case miss
    case modifierApplied
    case ailmentRemoved
}

nonisolated enum BattleTargetResultFlag: String, Codable, Equatable, Sendable {
    case defeated
    case revived
    case guarded
}

nonisolated enum BattleAilment: Int, Codable, Equatable, Sendable {
    case sleep = 1
    case curse = 2
    case paralysis = 3
    case petrify = 4
}

nonisolated struct BattleContext: Codable, Equatable, Sendable {
    let runId: RunSessionID
    let rootSeed: UInt64
    let floorNumber: Int
    let battleNumber: Int
}

nonisolated struct BattleEnemySeed: Codable, Hashable, Equatable, Sendable {
    let enemyId: Int
    let level: Int
}

nonisolated struct BattleCombatantID: RawRepresentable, Codable, Hashable, Equatable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

nonisolated enum BattleCombatantImageReference: Codable, Equatable, Sendable {
    case partyMember(jobId: Int, portraitGender: PortraitGender)
    case enemy(enemyId: Int)
}

nonisolated struct BattleTargetResult: Codable, Equatable, Sendable {
    let targetId: BattleCombatantID
    let resultKind: BattleTargetResultKind
    let value: Int?
    let statusId: Int?
    let flags: [BattleTargetResultFlag]
}

nonisolated struct BattleActionRecord: Codable, Equatable, Sendable {
    let actorId: BattleCombatantID
    let actionKind: BattleLogActionKind
    let actionRef: Int?
    let actionFlags: [BattleActionFlag]
    let targetIds: [BattleCombatantID]
    let results: [BattleTargetResult]
}

nonisolated struct BattleTurnRecord: Codable, Equatable, Sendable {
    let turnNumber: Int
    let actions: [BattleActionRecord]
}

nonisolated struct BattleRecord: Codable, Equatable, Sendable {
    let runId: RunSessionID
    let floorNumber: Int
    let battleNumber: Int
    let result: BattleOutcome
    let turns: [BattleTurnRecord]
}

nonisolated struct BattleCombatantSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: BattleCombatantID
    let name: String
    let side: BattleSide
    let imageReference: BattleCombatantImageReference?
    let level: Int
    let initialHP: Int
    let maxHP: Int
    let remainingHP: Int
    let formationIndex: Int
}

nonisolated struct BattleRewardMetrics: Equatable, Sendable {
    let totalDamageTakenByAllies: Int
    let normalAttackKillCount: Int
}

extension BattleCombatantImageReference {
    nonisolated init?(
        persistenceKind: Int64,
        primaryID: Int64,
        secondaryID: Int64
    ) {
        switch Int(persistenceKind) {
        case 1:
            guard primaryID > 0,
                  let portraitGender = PortraitGender(rawValue: Int(secondaryID)) else {
                return nil
            }

            self = .partyMember(
                jobId: Int(primaryID),
                portraitGender: portraitGender
            )
        case 2:
            guard primaryID > 0 else {
                return nil
            }

            self = .enemy(enemyId: Int(primaryID))
        default:
            return nil
        }
    }

    nonisolated var persistenceKind: Int64 {
        switch self {
        case .partyMember:
            1
        case .enemy:
            2
        }
    }

    nonisolated var persistencePrimaryID: Int64 {
        switch self {
        case let .partyMember(jobId, _):
            Int64(jobId)
        case let .enemy(enemyId):
            Int64(enemyId)
        }
    }

    nonisolated var persistenceSecondaryID: Int64 {
        switch self {
        case let .partyMember(_, portraitGender):
            Int64(portraitGender.rawValue)
        case .enemy:
            0
        }
    }
}

nonisolated struct SingleBattleResult: Equatable, Sendable {
    let context: BattleContext
    let battleRecord: BattleRecord
    let combatants: [BattleCombatantSnapshot]
    let rewardMetrics: BattleRewardMetrics

    init(
        context: BattleContext,
        battleRecord: BattleRecord,
        combatants: [BattleCombatantSnapshot],
        rewardMetrics: BattleRewardMetrics? = nil
    ) {
        self.context = context
        self.battleRecord = battleRecord
        self.combatants = combatants
        self.rewardMetrics = rewardMetrics ?? Self.makeRewardMetrics(
            battleRecord: battleRecord,
            combatants: combatants
        )
    }

    var result: BattleOutcome {
        battleRecord.result
    }

    var partyRemainingHPs: [Int] {
        // Ally snapshots are stored in a flat combatant list, so restore formation order before
        // upper layers reuse the remaining HPs as a party-shaped array.
        combatants
            .filter { $0.side == .ally }
            .sorted { $0.formationIndex < $1.formationIndex }
            .map(\.remainingHP)
    }

    private static func makeRewardMetrics(
        battleRecord: BattleRecord,
        combatants: [BattleCombatantSnapshot]
    ) -> BattleRewardMetrics {
        let allyIDs = Set(
            combatants
                .lazy
                .filter { $0.side == .ally }
                .map(\.id)
        )

        var totalDamageTakenByAllies = 0
        var normalAttackKillCount = 0

        for action in battleRecord.turns.lazy.flatMap(\.actions) {
            if action.actionKind == .attack {
                normalAttackKillCount += action.results.lazy.filter { $0.flags.contains(.defeated) }.count
            }

            for targetResult in action.results
            where targetResult.resultKind == .damage
                && allyIDs.contains(targetResult.targetId) {
                totalDamageTakenByAllies += targetResult.value ?? 0
            }
        }

        return BattleRewardMetrics(
            totalDamageTakenByAllies: totalDamageTakenByAllies,
            normalAttackKillCount: normalAttackKillCount
        )
    }
}

nonisolated enum SingleBattleError: LocalizedError {
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

extension BattleOutcome: PersistenceOrderRepresentable {
    nonisolated var persistenceOrder: Int {
        switch self {
        case .victory:
            0
        case .draw:
            1
        case .defeat:
            2
        }
    }

    nonisolated init?(persistenceOrder: Int) {
        switch persistenceOrder {
        case 0:
            self = .victory
        case 1:
            self = .draw
        case 2:
            self = .defeat
        default:
            return nil
        }
    }
}

extension BattleSide: PersistenceOrderRepresentable {
    nonisolated var persistenceOrder: Int {
        switch self {
        case .ally:
            0
        case .enemy:
            1
        }
    }

    nonisolated init?(persistenceOrder: Int) {
        switch persistenceOrder {
        case 0:
            self = .ally
        case 1:
            self = .enemy
        default:
            return nil
        }
    }
}

extension BattleLogActionKind: PersistenceOrderRepresentable {
    nonisolated var persistenceOrder: Int {
        switch self {
        case .breath:
            0
        case .attack:
            1
        case .unarmedRepeat:
            2
        case .recoverySpell:
            3
        case .attackSpell:
            4
        case .defend:
            5
        case .rescue:
            6
        case .counter:
            7
        case .extraAttack:
            8
        case .pursuit:
            9
        }
    }

    nonisolated init?(persistenceOrder: Int) {
        switch persistenceOrder {
        case 0:
            self = .breath
        case 1:
            self = .attack
        case 2:
            self = .unarmedRepeat
        case 3:
            self = .recoverySpell
        case 4:
            self = .attackSpell
        case 5:
            self = .defend
        case 6:
            self = .rescue
        case 7:
            self = .counter
        case 8:
            self = .extraAttack
        case 9:
            self = .pursuit
        default:
            return nil
        }
    }
}

extension BattleTargetResultKind: PersistenceOrderRepresentable {
    nonisolated var persistenceOrder: Int {
        switch self {
        case .damage:
            0
        case .heal:
            1
        case .miss:
            2
        case .modifierApplied:
            3
        case .ailmentRemoved:
            4
        }
    }

    nonisolated init?(persistenceOrder: Int) {
        switch persistenceOrder {
        case 0:
            self = .damage
        case 1:
            self = .heal
        case 2:
            self = .miss
        case 3:
            self = .modifierApplied
        case 4:
            self = .ailmentRemoved
        default:
            return nil
        }
    }
}
