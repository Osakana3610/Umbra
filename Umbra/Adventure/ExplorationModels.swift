// Defines persisted exploration sessions, rewards, and log payloads for deterministic auto-progression.

import Foundation

nonisolated struct RunSessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    let partyId: Int
    let partyRunId: Int

    var description: String {
        "\(partyId):\(partyRunId)"
    }
}

nonisolated enum RunCompletionReason: String, Codable, Equatable, Sendable {
    case cleared
    case defeated
    case draw
}

nonisolated struct ExplorationBattleLog: Codable, Equatable, Sendable, Identifiable {
    let battleRecord: BattleRecord
    let combatants: [BattleCombatantSnapshot]

    var id: String {
        "\(battleRecord.runId)-\(battleRecord.battleNumber)"
    }
}

nonisolated struct ExplorationExperienceReward: Codable, Equatable, Sendable, Identifiable {
    let characterId: Int
    let experience: Int

    var id: Int { characterId }
}

nonisolated struct ExplorationDropReward: Codable, Equatable, Sendable, Identifiable {
    let itemID: CompositeItemID
    let sourceFloorNumber: Int
    let sourceBattleNumber: Int

    var id: String {
        "\(sourceFloorNumber)-\(sourceBattleNumber)-\(itemID.rawValue)"
    }
}

nonisolated struct RunCompletionRecord: Codable, Equatable, Sendable {
    let completedAt: Date
    let reason: RunCompletionReason
    let gold: Int
    let experienceRewards: [ExplorationExperienceReward]
    let dropRewards: [ExplorationDropReward]
}

nonisolated struct RunSessionRecord: Equatable, Sendable, Identifiable {
    let partyRunId: Int
    let partyId: Int
    let labyrinthId: Int
    let selectedDifficultyTitleId: Int
    let targetFloorNumber: Int
    let startedAt: Date
    let rootSeed: UInt64
    let memberSnapshots: [CharacterRecord]
    let memberCharacterIds: [Int]
    let completedBattleCount: Int
    let currentPartyHPs: [Int]
    let memberExperienceMultipliers: [Double]
    let progressIntervalMultiplier: Double
    let goldMultiplier: Double
    let rareDropMultiplier: Double
    let partyAverageLuck: Double
    let latestBattleFloorNumber: Int?
    let latestBattleNumber: Int?
    let latestBattleOutcome: BattleOutcome?
    let battleLogs: [ExplorationBattleLog]
    let goldBuffer: Int
    let experienceRewards: [ExplorationExperienceReward]
    let dropRewards: [ExplorationDropReward]
    let completion: RunCompletionRecord?

    var runSessionID: RunSessionID {
        RunSessionID(
            partyId: partyId,
            partyRunId: partyRunId
        )
    }

    var id: RunSessionID {
        runSessionID
    }

    var isCompleted: Bool {
        completion != nil
    }

    func progressIntervalSeconds(baseIntervalSeconds: Int) -> Double {
        // Both inputs are clamped so malformed persisted multipliers never freeze progress or make
        // it run with a non-positive interval.
        let clampedBaseIntervalSeconds = max(baseIntervalSeconds, 1)
        let clampedMultiplier = max(progressIntervalMultiplier, 0.1)
        return Double(clampedBaseIntervalSeconds) * clampedMultiplier
    }

    var summaryRecord: RunSessionRecord {
        // Summary records intentionally drop heavy payloads so list screens can refresh progress
        // without carrying every stored battle log and reward row in memory.
        RunSessionRecord(
            partyRunId: partyRunId,
            partyId: partyId,
            labyrinthId: labyrinthId,
            selectedDifficultyTitleId: selectedDifficultyTitleId,
            targetFloorNumber: targetFloorNumber,
            startedAt: startedAt,
            rootSeed: rootSeed,
            memberSnapshots: memberSnapshots,
            memberCharacterIds: memberCharacterIds,
            completedBattleCount: completedBattleCount,
            currentPartyHPs: currentPartyHPs,
            memberExperienceMultipliers: memberExperienceMultipliers,
            progressIntervalMultiplier: progressIntervalMultiplier,
            goldMultiplier: goldMultiplier,
            rareDropMultiplier: rareDropMultiplier,
            partyAverageLuck: partyAverageLuck,
            latestBattleFloorNumber: latestBattleFloorNumber,
            latestBattleNumber: latestBattleNumber,
            latestBattleOutcome: latestBattleOutcome,
            battleLogs: [],
            goldBuffer: goldBuffer,
            experienceRewards: [],
            dropRewards: [],
            completion: completion.map { completion in
                RunCompletionRecord(
                    completedAt: completion.completedAt,
                    reason: completion.reason,
                    gold: completion.gold,
                    experienceRewards: [],
                    dropRewards: []
                )
            }
        )
    }
}

nonisolated struct ExplorationRunSnapshot: Equatable, Sendable {
    // Reward application is reported alongside the refreshed runs so UI layers can reload only the
    // dependent stores that actually changed.
    let runs: [RunSessionRecord]
    let didApplyRewards: Bool
    let appliedInventoryCounts: [CompositeItemID: Int]
    let dropNotificationBatches: [ExplorationDropNotificationBatch]
}

nonisolated struct ExplorationPartyStatus: Equatable, Sendable {
    let activeRun: RunSessionRecord?
    let latestCompletedRun: RunSessionRecord?
}

nonisolated struct ExplorationDropNotificationBatch: Equatable, Sendable {
    let partyId: Int
    let dropRewards: [ExplorationDropReward]
}

nonisolated enum ExplorationError: LocalizedError {
    case invalidLabyrinth(labyrinthId: Int)
    case labyrinthLocked(labyrinthId: Int)
    case invalidParty(partyId: Int)
    case runNotFound(partyId: Int, partyRunId: Int)
    case partyHasNoMembers(partyId: Int)
    case partyHasDefeatedMember(partyId: Int)
    case activeRunAlreadyExists(partyId: Int)
    case insufficientCatTickets
    case partyLockedByActiveRun(partyId: Int)
    case characterLockedByActiveRun(characterId: Int)
    case invalidRunMember(characterId: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidLabyrinth(labyrinthId):
            "迷宮が見つかりません。 labyrinthId=\(labyrinthId)"
        case let .labyrinthLocked(labyrinthId):
            "迷宮\(labyrinthId)はまだ解放されていません。"
        case let .invalidParty(partyId):
            "パーティが見つかりません。 partyId=\(partyId)"
        case let .runNotFound(partyId, partyRunId):
            "探索記録が見つかりません。 partyId=\(partyId) partyRunId=\(partyRunId)"
        case let .partyHasNoMembers(partyId):
            "パーティ\(partyId)には出撃メンバーがいません。"
        case let .partyHasDefeatedMember(partyId):
            "パーティ\(partyId)にHPが0のメンバーがいるため出撃できません。"
        case let .activeRunAlreadyExists(partyId):
            "パーティ\(partyId)はすでに出撃中です。"
        case .insufficientCatTickets:
            "キャット・チケットが不足しています。"
        case let .partyLockedByActiveRun(partyId):
            "パーティ\(partyId)は出撃中のため編成変更できません。"
        case let .characterLockedByActiveRun(characterId):
            "キャラクター\(characterId)は出撃中のため変更できません。"
        case let .invalidRunMember(characterId):
            "探索進行に必要なキャラクター情報が不足しています。 characterId=\(characterId)"
        }
    }
}
