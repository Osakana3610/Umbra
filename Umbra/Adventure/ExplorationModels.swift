// Defines persisted exploration sessions, rewards, and log payloads for deterministic auto-progression.

import Foundation

enum RunCompletionReason: String, Codable, Equatable, Sendable {
    case cleared
    case defeated
    case draw
}

struct ExplorationBattleLog: Codable, Equatable, Sendable, Identifiable {
    let battleRecord: BattleRecord
    let combatants: [BattleCombatantSnapshot]

    var id: String {
        "\(battleRecord.runId)-\(battleRecord.battleNumber)"
    }
}

struct ExplorationExperienceReward: Codable, Equatable, Sendable, Identifiable {
    let characterId: Int
    let experience: Int

    var id: Int { characterId }
}

struct ExplorationDropReward: Codable, Equatable, Sendable, Identifiable {
    let itemID: CompositeItemID
    let sourceFloorNumber: Int
    let sourceBattleNumber: Int

    var id: String {
        "\(sourceFloorNumber)-\(sourceBattleNumber)-\(itemID.rawValue)"
    }
}

struct RunCompletionRecord: Codable, Equatable, Sendable {
    let completedAt: Date
    let reason: RunCompletionReason
    let completedLoopCount: Int
    let gold: Int
    let experienceRewards: [ExplorationExperienceReward]
    let dropRewards: [ExplorationDropReward]
}

struct RunSessionRecord: Equatable, Sendable, Identifiable {
    let partyRunId: Int
    let partyId: Int
    let labyrinthId: Int
    let targetFloorNumber: Int
    let startedAt: Date
    let rootSeed: UInt64
    let maximumLoopCount: Int
    let memberCharacterIds: [Int]
    let completedBattleCount: Int
    let currentPartyHPs: [Int]
    let battleLogs: [ExplorationBattleLog]
    let goldBuffer: Int
    let experienceRewards: [ExplorationExperienceReward]
    let dropRewards: [ExplorationDropReward]
    let completion: RunCompletionRecord?

    var id: String {
        "\(partyId):\(partyRunId)"
    }

    var isCompleted: Bool {
        completion != nil
    }
}

struct ExplorationRunSnapshot: Equatable, Sendable {
    let runs: [RunSessionRecord]
    let didApplyRewards: Bool
}

struct ExplorationPartyStatus: Equatable, Sendable {
    let activeRun: RunSessionRecord?
    let latestCompletedRun: RunSessionRecord?
}

enum ExplorationRepositoryError: LocalizedError {
    case invalidLabyrinth(labyrinthId: Int)
    case invalidParty(partyId: Int)
    case partyHasNoMembers(partyId: Int)
    case partyHasDefeatedMember(partyId: Int)
    case activeRunAlreadyExists(partyId: Int)
    case partyLockedByActiveRun(partyId: Int)
    case characterLockedByActiveRun(characterId: Int)
    case invalidRunMember(characterId: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidLabyrinth(labyrinthId):
            "迷宮が見つかりません。 labyrinthId=\(labyrinthId)"
        case let .invalidParty(partyId):
            "パーティが見つかりません。 partyId=\(partyId)"
        case let .partyHasNoMembers(partyId):
            "パーティ\(partyId)には出撃メンバーがいません。"
        case let .partyHasDefeatedMember(partyId):
            "パーティ\(partyId)にHPが0のメンバーがいるため出撃できません。"
        case let .activeRunAlreadyExists(partyId):
            "パーティ\(partyId)はすでに出撃中です。"
        case let .partyLockedByActiveRun(partyId):
            "パーティ\(partyId)は出撃中のため編成変更できません。"
        case let .characterLockedByActiveRun(characterId):
            "キャラクター\(characterId)は出撃中のため変更できません。"
        case let .invalidRunMember(characterId):
            "探索進行に必要なキャラクター情報が不足しています。 characterId=\(characterId)"
        }
    }
}
