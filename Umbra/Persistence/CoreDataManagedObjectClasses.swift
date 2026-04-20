// Declares manual Core Data managed object subclasses so the app does not depend on Xcode code generation.

import CoreData
import Foundation

@objc(CharacterEntity)
public class CharacterEntity: NSManagedObject {

}

@objc(CharacterEquippedItemEntity)
public class CharacterEquippedItemEntity: NSManagedObject {

}

@objc(InventoryItemEntity)
public class InventoryItemEntity: NSManagedObject {

}

@objc(ShopItemEntity)
public class ShopItemEntity: NSManagedObject {

}

@objc(PartyEntity)
public class PartyEntity: NSManagedObject {

}

@objc(PlayerStateEntity)
public class PlayerStateEntity: NSManagedObject {

}

@objc(PlayerStateAutoSellItemEntity)
public class PlayerStateAutoSellItemEntity: NSManagedObject {

}

@objc(LabyrinthProgressEntity)
public class LabyrinthProgressEntity: NSManagedObject {

}

@objc(RunSessionBattleActionEntity)
public class RunSessionBattleActionEntity: NSManagedObject {

}

@objc(RunSessionBattleActionTargetEntity)
public class RunSessionBattleActionTargetEntity: NSManagedObject {

}

@objc(RunSessionBattleCombatantEntity)
public class RunSessionBattleCombatantEntity: NSManagedObject {

}

@objc(RunSessionBattleLogEntity)
public class RunSessionBattleLogEntity: NSManagedObject {

}

@objc(RunSessionBattleResultEntity)
public class RunSessionBattleResultEntity: NSManagedObject {

}

@objc(RunSessionBattleTurnEntity)
public class RunSessionBattleTurnEntity: NSManagedObject {

}

@objc(RunSessionDropRewardEntity)
public class RunSessionDropRewardEntity: NSManagedObject {

}

@objc(RunSessionEntity)
public class RunSessionEntity: NSManagedObject {

}

@objc(RunSessionExperienceRewardEntity)
public class RunSessionExperienceRewardEntity: NSManagedObject {

}

@objc(RunSessionMemberEquippedItemEntity)
public class RunSessionMemberEquippedItemEntity: NSManagedObject {

}

@objc(RunSessionMemberEntity)
public class RunSessionMemberEntity: NSManagedObject {

}
