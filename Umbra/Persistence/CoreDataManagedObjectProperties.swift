// Declares manual Core Data managed object members as nonisolated so background contexts can use typed access.

import CoreData
import Foundation

extension CharacterEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<CharacterEntity> {
        return NSFetchRequest<CharacterEntity>(entityName: "CharacterEntity")
    }

    @NSManaged nonisolated public var actionPriorityRawValue: String?
    @NSManaged nonisolated public var attackRate: Int64
    @NSManaged nonisolated public var attackSpellRate: Int64
    @NSManaged nonisolated public var aptitudeId: Int64
    @NSManaged nonisolated public var breathRate: Int64
    @NSManaged nonisolated public var characterId: Int64
    @NSManaged nonisolated public var currentHP: Int64
    @NSManaged nonisolated public var currentJobId: Int64
    @NSManaged nonisolated public var equippedItemStacksRawValue: String?
    @NSManaged nonisolated public var experience: Int64
    @NSManaged nonisolated public var level: Int64
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var portraitVariant: Int64
    @NSManaged nonisolated public var previousJobId: Int64
    @NSManaged nonisolated public var raceId: Int64
    @NSManaged nonisolated public var recoverySpellRate: Int64

}

extension CharacterEntity : Identifiable {

}

extension InventoryItemEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<InventoryItemEntity> {
        return NSFetchRequest<InventoryItemEntity>(entityName: "InventoryItemEntity")
    }

    @NSManaged nonisolated public var count: Int64
    @NSManaged nonisolated public var stackKeyRawValue: String?

}

extension InventoryItemEntity : Identifiable {

}

extension PartyEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<PartyEntity> {
        return NSFetchRequest<PartyEntity>(entityName: "PartyEntity")
    }

    @NSManaged nonisolated public var memberCharacterIdsRawValue: String?
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var partyId: Int64
    @NSManaged nonisolated public var pendingAutomaticRunCount: Int64
    @NSManaged nonisolated public var pendingAutomaticRunStartedAt: Date?
    @NSManaged nonisolated public var selectedDifficultyTitleId: Int64
    @NSManaged nonisolated public var selectedLabyrinthId: Int64

}

extension PartyEntity : Identifiable {

}

extension PlayerStateEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<PlayerStateEntity> {
        return NSFetchRequest<PlayerStateEntity>(entityName: "PlayerStateEntity")
    }

    @NSManaged nonisolated public var autoReviveDefeatedCharacters: Bool
    @NSManaged nonisolated public var gold: Int64
    @NSManaged nonisolated public var lastBackgroundedAt: Date?
    @NSManaged nonisolated public var nextCharacterId: Int64

}

extension PlayerStateEntity : Identifiable {

}

extension LabyrinthProgressEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<LabyrinthProgressEntity> {
        return NSFetchRequest<LabyrinthProgressEntity>(entityName: "LabyrinthProgressEntity")
    }

    @NSManaged nonisolated public var highestUnlockedDifficultyTitleId: Int64
    @NSManaged nonisolated public var labyrinthId: Int64

}

extension LabyrinthProgressEntity : Identifiable {

}

extension RunSessionBattleActionEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionBattleActionEntity> {
        return NSFetchRequest<RunSessionBattleActionEntity>(entityName: "RunSessionBattleActionEntity")
    }

    @NSManaged nonisolated public var actionIndex: Int64
    @NSManaged nonisolated public var actionKindRawValue: String?
    @NSManaged nonisolated public var actionRefValue: Int64
    @NSManaged nonisolated public var actorCombatantIDRawValue: String?
    @NSManaged nonisolated public var hasActionRef: Bool
    @NSManaged nonisolated public var isCritical: Bool
    @NSManaged nonisolated public var targetCombatantIDsRawValue: String?
    @NSManaged nonisolated public var results: NSSet?
    @NSManaged nonisolated public var turn: RunSessionBattleTurnEntity?

}

// MARK: Generated accessors for results
extension RunSessionBattleActionEntity {

    @objc(addResultsObject:)
    @NSManaged nonisolated public func addToResults(_ value: RunSessionBattleResultEntity)

    @objc(removeResultsObject:)
    @NSManaged nonisolated public func removeFromResults(_ value: RunSessionBattleResultEntity)

    @objc(addResults:)
    @NSManaged nonisolated public func addToResults(_ values: NSSet)

    @objc(removeResults:)
    @NSManaged nonisolated public func removeFromResults(_ values: NSSet)

}

extension RunSessionBattleActionEntity : Identifiable {

}

extension RunSessionBattleCombatantEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionBattleCombatantEntity> {
        return NSFetchRequest<RunSessionBattleCombatantEntity>(entityName: "RunSessionBattleCombatantEntity")
    }

    @NSManaged nonisolated public var combatantIDRawValue: String?
    @NSManaged nonisolated public var combatantIndex: Int64
    @NSManaged nonisolated public var formationIndex: Int64
    @NSManaged nonisolated public var imageAssetID: String?
    @NSManaged nonisolated public var initialHP: Int64
    @NSManaged nonisolated public var level: Int64
    @NSManaged nonisolated public var maxHP: Int64
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var remainingHP: Int64
    @NSManaged nonisolated public var sideRawValue: String?
    @NSManaged nonisolated public var battleLog: RunSessionBattleLogEntity?

}

extension RunSessionBattleCombatantEntity : Identifiable {

}

extension RunSessionBattleLogEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionBattleLogEntity> {
        return NSFetchRequest<RunSessionBattleLogEntity>(entityName: "RunSessionBattleLogEntity")
    }

    @NSManaged nonisolated public var battleNumber: Int64
    @NSManaged nonisolated public var floorNumber: Int64
    @NSManaged nonisolated public var logIndex: Int64
    @NSManaged nonisolated public var resultRawValue: String?
    @NSManaged nonisolated public var combatants: NSSet?
    @NSManaged nonisolated public var runSession: RunSessionEntity?
    @NSManaged nonisolated public var turns: NSSet?

}

// MARK: Generated accessors for combatants
extension RunSessionBattleLogEntity {

    @objc(addCombatantsObject:)
    @NSManaged nonisolated public func addToCombatants(_ value: RunSessionBattleCombatantEntity)

    @objc(removeCombatantsObject:)
    @NSManaged nonisolated public func removeFromCombatants(_ value: RunSessionBattleCombatantEntity)

    @objc(addCombatants:)
    @NSManaged nonisolated public func addToCombatants(_ values: NSSet)

    @objc(removeCombatants:)
    @NSManaged nonisolated public func removeFromCombatants(_ values: NSSet)

}

// MARK: Generated accessors for turns
extension RunSessionBattleLogEntity {

    @objc(addTurnsObject:)
    @NSManaged nonisolated public func addToTurns(_ value: RunSessionBattleTurnEntity)

    @objc(removeTurnsObject:)
    @NSManaged nonisolated public func removeFromTurns(_ value: RunSessionBattleTurnEntity)

    @objc(addTurns:)
    @NSManaged nonisolated public func addToTurns(_ values: NSSet)

    @objc(removeTurns:)
    @NSManaged nonisolated public func removeFromTurns(_ values: NSSet)

}

extension RunSessionBattleLogEntity : Identifiable {

}

extension RunSessionBattleResultEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionBattleResultEntity> {
        return NSFetchRequest<RunSessionBattleResultEntity>(entityName: "RunSessionBattleResultEntity")
    }

    @NSManaged nonisolated public var actionResultIndex: Int64
    @NSManaged nonisolated public var hasStatusId: Bool
    @NSManaged nonisolated public var hasValue: Bool
    @NSManaged nonisolated public var isDefeated: Bool
    @NSManaged nonisolated public var isGuarded: Bool
    @NSManaged nonisolated public var isRevived: Bool
    @NSManaged nonisolated public var resultKindRawValue: String?
    @NSManaged nonisolated public var statusIdValue: Int64
    @NSManaged nonisolated public var targetCombatantIDRawValue: String?
    @NSManaged nonisolated public var valueValue: Int64
    @NSManaged nonisolated public var action: RunSessionBattleActionEntity?

}

extension RunSessionBattleResultEntity : Identifiable {

}

extension RunSessionBattleTurnEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionBattleTurnEntity> {
        return NSFetchRequest<RunSessionBattleTurnEntity>(entityName: "RunSessionBattleTurnEntity")
    }

    @NSManaged nonisolated public var turnIndex: Int64
    @NSManaged nonisolated public var turnNumber: Int64
    @NSManaged nonisolated public var actions: NSSet?
    @NSManaged nonisolated public var battleLog: RunSessionBattleLogEntity?

}

// MARK: Generated accessors for actions
extension RunSessionBattleTurnEntity {

    @objc(addActionsObject:)
    @NSManaged nonisolated public func addToActions(_ value: RunSessionBattleActionEntity)

    @objc(removeActionsObject:)
    @NSManaged nonisolated public func removeFromActions(_ value: RunSessionBattleActionEntity)

    @objc(addActions:)
    @NSManaged nonisolated public func addToActions(_ values: NSSet)

    @objc(removeActions:)
    @NSManaged nonisolated public func removeFromActions(_ values: NSSet)

}

extension RunSessionBattleTurnEntity : Identifiable {

}

extension RunSessionDropRewardEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionDropRewardEntity> {
        return NSFetchRequest<RunSessionDropRewardEntity>(entityName: "RunSessionDropRewardEntity")
    }

    @NSManaged nonisolated public var itemIDRawValue: String?
    @NSManaged nonisolated public var sourceBattleNumber: Int64
    @NSManaged nonisolated public var sourceFloorNumber: Int64
    @NSManaged nonisolated public var runSession: RunSessionEntity?

}

extension RunSessionDropRewardEntity : Identifiable {

}

extension RunSessionEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionEntity> {
        return NSFetchRequest<RunSessionEntity>(entityName: "RunSessionEntity")
    }

    @NSManaged nonisolated public var completedAt: Date?
    @NSManaged nonisolated public var completedBattleCount: Int64
    @NSManaged nonisolated public var completionReasonRawValue: String?
    @NSManaged nonisolated public var goldBuffer: Int64
    @NSManaged nonisolated public var labyrinthId: Int64
    @NSManaged nonisolated public var latestBattleFloorNumber: Int64
    @NSManaged nonisolated public var latestBattleNumber: Int64
    @NSManaged nonisolated public var latestBattleOutcomeRawValue: String?
    @NSManaged nonisolated public var partyAverageLuck: Double
    @NSManaged nonisolated public var partyId: Int64
    @NSManaged nonisolated public var partyRunId: Int64
    @NSManaged nonisolated public var rareDropMultiplier: Double
    @NSManaged nonisolated public var rewardsApplied: Bool
    @NSManaged nonisolated public var rootSeedSigned: Int64
    @NSManaged nonisolated public var selectedDifficultyTitleId: Int64
    @NSManaged nonisolated public var titleDropMultiplier: Double
    @NSManaged nonisolated public var startedAt: Date?
    @NSManaged nonisolated public var targetFloorNumber: Int64
    @NSManaged nonisolated public var goldMultiplier: Double
    @NSManaged nonisolated public var battleLogs: NSSet?
    @NSManaged nonisolated public var dropRewards: NSSet?
    @NSManaged nonisolated public var experienceRewards: NSSet?
    @NSManaged nonisolated public var members: NSSet?

}

// MARK: Generated accessors for battleLogs
extension RunSessionEntity {

    @objc(addBattleLogsObject:)
    @NSManaged nonisolated public func addToBattleLogs(_ value: RunSessionBattleLogEntity)

    @objc(removeBattleLogsObject:)
    @NSManaged nonisolated public func removeFromBattleLogs(_ value: RunSessionBattleLogEntity)

    @objc(addBattleLogs:)
    @NSManaged nonisolated public func addToBattleLogs(_ values: NSSet)

    @objc(removeBattleLogs:)
    @NSManaged nonisolated public func removeFromBattleLogs(_ values: NSSet)

}

// MARK: Generated accessors for dropRewards
extension RunSessionEntity {

    @objc(addDropRewardsObject:)
    @NSManaged nonisolated public func addToDropRewards(_ value: RunSessionDropRewardEntity)

    @objc(removeDropRewardsObject:)
    @NSManaged nonisolated public func removeFromDropRewards(_ value: RunSessionDropRewardEntity)

    @objc(addDropRewards:)
    @NSManaged nonisolated public func addToDropRewards(_ values: NSSet)

    @objc(removeDropRewards:)
    @NSManaged nonisolated public func removeFromDropRewards(_ values: NSSet)

}

// MARK: Generated accessors for experienceRewards
extension RunSessionEntity {

    @objc(addExperienceRewardsObject:)
    @NSManaged nonisolated public func addToExperienceRewards(_ value: RunSessionExperienceRewardEntity)

    @objc(removeExperienceRewardsObject:)
    @NSManaged nonisolated public func removeFromExperienceRewards(_ value: RunSessionExperienceRewardEntity)

    @objc(addExperienceRewards:)
    @NSManaged nonisolated public func addToExperienceRewards(_ values: NSSet)

    @objc(removeExperienceRewards:)
    @NSManaged nonisolated public func removeFromExperienceRewards(_ values: NSSet)

}

// MARK: Generated accessors for members
extension RunSessionEntity {

    @objc(addMembersObject:)
    @NSManaged nonisolated public func addToMembers(_ value: RunSessionMemberEntity)

    @objc(removeMembersObject:)
    @NSManaged nonisolated public func removeFromMembers(_ value: RunSessionMemberEntity)

    @objc(addMembers:)
    @NSManaged nonisolated public func addToMembers(_ values: NSSet)

    @objc(removeMembers:)
    @NSManaged nonisolated public func removeFromMembers(_ values: NSSet)

}

extension RunSessionEntity : Identifiable {

}

extension RunSessionExperienceRewardEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionExperienceRewardEntity> {
        return NSFetchRequest<RunSessionExperienceRewardEntity>(entityName: "RunSessionExperienceRewardEntity")
    }

    @NSManaged nonisolated public var characterId: Int64
    @NSManaged nonisolated public var experience: Int64
    @NSManaged nonisolated public var runSession: RunSessionEntity?

}

extension RunSessionExperienceRewardEntity : Identifiable {

}

extension RunSessionMemberEntity {

    @nonobjc nonisolated public class func fetchRequest() -> NSFetchRequest<RunSessionMemberEntity> {
        return NSFetchRequest<RunSessionMemberEntity>(entityName: "RunSessionMemberEntity")
    }

    @NSManaged nonisolated public var actionPriorityRawValue: String?
    @NSManaged nonisolated public var attackRate: Int64
    @NSManaged nonisolated public var attackSpellRate: Int64
    @NSManaged nonisolated public var aptitudeId: Int64
    @NSManaged nonisolated public var breathRate: Int64
    @NSManaged nonisolated public var characterId: Int64
    @NSManaged nonisolated public var currentHP: Int64
    @NSManaged nonisolated public var currentJobId: Int64
    @NSManaged nonisolated public var equippedItemStacksRawValue: String?
    @NSManaged nonisolated public var experience: Int64
    @NSManaged nonisolated public var experienceMultiplier: Double
    @NSManaged nonisolated public var formationIndex: Int64
    @NSManaged nonisolated public var level: Int64
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var portraitVariant: Int64
    @NSManaged nonisolated public var previousJobId: Int64
    @NSManaged nonisolated public var raceId: Int64
    @NSManaged nonisolated public var recoverySpellRate: Int64
    @NSManaged nonisolated public var runSession: RunSessionEntity?

}

extension RunSessionMemberEntity : Identifiable {

}
