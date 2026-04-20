// Verifies deterministic battle resolution across damage formulas, target selection, interrupts,
// rewards, and stateful combat effects.
// This suite is intentionally broad because the battle resolver composes many rule families, and a
// small change in one area can silently regress seemingly unrelated combat behavior.

import CoreData
import Foundation
import Testing
@testable import Umbra

@Suite(.serialized)
@MainActor
struct UmbraBattleTests {
    // Damage multiplier and baseline attack-resolution coverage.
    @Test
    func meleeWeaponDamageUsesMeleeDamageMultiplier() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 1),
            jobId: 1,
            level: 1,
            skillIds: [],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            battleDerivedStats: makeBattleDerivedStats(meleeDamageMultiplier: 2.0),
            isUnarmed: false,
            weaponRangeClass: .melee
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attack))
        let expected = expectedPhysicalDamage(
            attacker: allyStatus,
            defender: enemyStatus,
            formationMultiplier: 1.0,
            weaponMultiplier: 2.0
        )
        #expect(damage == expected)
    }

    @Test
    func rangedWeaponDamageUsesRangedDamageMultiplier() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 1),
            jobId: 1,
            level: 1,
            skillIds: [],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            battleDerivedStats: makeBattleDerivedStats(rangedDamageMultiplier: 2.0),
            isUnarmed: false,
            hasMeleeWeapon: false,
            hasRangedWeapon: true,
            weaponRangeClass: .ranged
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [makePartyBattleMember(id: 1, name: "狩人", status: allyStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attack))
        let expected = expectedPhysicalDamage(
            attacker: allyStatus,
            defender: enemyStatus,
            formationMultiplier: 0.70,
            weaponMultiplier: 2.0
        )
        #expect(damage == expected)
    }

    @Test
    func mixedWeaponsApplyBothFormationMultipliers() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 1),
            jobId: 1,
            level: 1,
            skillIds: [],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            isUnarmed: false,
            hasMeleeWeapon: true,
            hasRangedWeapon: true,
            weaponRangeClass: .ranged
        )
        let defendingStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 1,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let defendOnly = makeAutoBattleSettings(
            breath: 0,
            attack: 0,
            recoverySpell: 0,
            attackSpell: 0,
            priority: [.attack, .breath, .recoverySpell, .attackSpell]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "前衛1", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 2, name: "前衛2", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 3, name: "中衛1", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 4, name: "中衛2", status: defendingStatus, autoBattleSettings: defendOnly),
                    makePartyBattleMember(id: 5, name: "後衛", status: allyStatus)
                ],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attack))
        let expected = expectedPhysicalDamage(
            attacker: allyStatus,
            defender: enemyStatus,
            formationMultiplier: 0.70,
            weaponMultiplier: 1.0
        )
        #expect(damage == expected)
    }

    @Test
    func unarmedAttackGetsBonusMultiplier() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1)
        )
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 1),
            jobId: 1,
            level: 1,
            skillIds: [],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            isUnarmed: true,
            weaponRangeClass: .none
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<256,
                partyMembers: [makePartyBattleMember(id: 1, name: "格闘家", status: allyStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attack))
        let expected = expectedPhysicalDamage(
            attacker: allyStatus,
            defender: enemyStatus,
            formationMultiplier: 1.0,
            weaponMultiplier: 1.5
        )
        #expect(damage == expected)
    }

    @Test
    func missedAttackCanStillTriggerCounter() throws {
        let counterSkill = MasterData.Skill(
            id: 1,
            name: "反撃",
            description: "反撃する。",
            effects: [
                MasterData.SkillEffect.interruptGrant(interruptKind: .counter, condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [counterSkill],
            enemyBaseStats: battleBaseStats(vitality: 20, agility: 1),
            enemySkillIds: [counterSkill.id]
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                let firstActionMissed = firstTurn.actions.first?.results.contains(where: { $0.resultKind == .miss }) ?? false
                return firstActionMissed && firstTurn.actions.contains(where: { $0.actionKind == .counter })
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(firstTurn.actions.first?.actionKind == .attack)
        #expect(firstTurn.actions.first?.results.contains(where: { $0.resultKind == .miss }) == true)
        #expect(firstTurn.actions.contains(where: { $0.actionKind == .counter }))
    }

    // Ailment handling and fallback action selection.
    @Test
    func spellSpecificDamageAndResistanceModifiersAffectAttackSpellDamage() throws {
        let fireSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let fireAccessSkill = MasterData.Skill(
            id: 1,
            name: "火球習得",
            description: "火球を習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [fireSpell.id], condition: nil)
            ]
        )
        let fireBoostSkill = MasterData.Skill(
            id: 2,
            name: "火球強化",
            description: "火球を強化する。",
            effects: [
                MasterData.SkillEffect.battleDerivedModifier(target: .spellDamageMultiplier, operation: .mul, value: 1.5, spellIds: [fireSpell.id], condition: nil)
            ]
        )
        let fireResistanceSkill = MasterData.Skill(
            id: 3,
            name: "火球耐性",
            description: "火球を軽減する。",
            effects: [
                MasterData.SkillEffect.battleDerivedModifier(target: .magicResistanceMultiplier, operation: .mul, value: 0.5, spellIds: [fireSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [fireAccessSkill, fireBoostSkill, fireResistanceSkill],
            spells: [fireSpell],
            allyBaseStats: battleBaseStats(vitality: 40, intelligence: 40, agility: 100),
            allyRaceSkillIds: [fireAccessSkill.id, fireBoostSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 20),
            enemySkillIds: [fireResistanceSkill.id]
        )
        let allyCharacter = makeBattleTestCharacter(
            id: 1,
            name: "魔導士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let resolvedAllyStatus = CharacterDerivedStatsCalculator.status(for: allyCharacter, masterData: masterData)
        let allyStatus = try #require(resolvedAllyStatus)
        let resolvedEnemyStatus = CharacterDerivedStatsCalculator.status(
            baseStats: battleCharacterBaseStats(vitality: 20),
            jobId: 1,
            level: 1,
            skillIds: [fireResistanceSkill.id],
            masterData: masterData
        )
        let enemyStatus = try #require(resolvedEnemyStatus)

        #expect(allyStatus.spellDamageMultiplier(for: fireSpell.id) == 1.5)
        #expect(enemyStatus.magicResistanceMultiplier(for: fireSpell.id) == 0.5)

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: allyCharacter, status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let damage = try #require(firstDamageValue(in: result, actionKind: .attackSpell))
        let basePower = Double(max(allyStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
        let damageMultiplier = allyStatus.battleDerivedStats.attackMagicMultiplier
            * allyStatus.battleDerivedStats.spellDamageMultiplier
            * allyStatus.spellDamageMultiplier(for: fireSpell.id)
            * (fireSpell.multiplier ?? 1.0)
        let resistanceMultiplier = enemyStatus.battleDerivedStats.magicResistanceMultiplier
            * enemyStatus.magicResistanceMultiplier(for: fireSpell.id)
        let expected = max(Int((basePower * damageMultiplier * resistanceMultiplier).rounded()), 1)
        #expect(damage == expected)
    }

    @Test
    func sleepSpellAppliesAilmentAndSkipsQueuedAction() throws {
        let sleepSpell = MasterData.Spell(
            id: 1,
            name: "眠り玉",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0,
            statusId: BattleAilment.sleep.rawValue,
            statusChance: 1.0
        )
        let sleepAccessSkill = MasterData.Skill(
            id: 1,
            name: "眠り玉習得",
            description: "眠り玉を習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [sleepSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [sleepAccessSkill],
            spells: [sleepSpell],
            allyRaceSkillIds: [sleepAccessSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 20),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyCharacter = makeBattleTestCharacter(
            id: 1,
            name: "眠術師",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 50,
                physicalDefense: 0,
                magic: 10,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [sleepSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: allyCharacter, status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstTurn.actions.count == 1)
        #expect(
            firstAction.results.contains(where: {
                $0.resultKind == .modifierApplied && $0.statusId == BattleAilment.sleep.rawValue
            })
        )
    }

    @Test
    func sleepCanWearOffAtEndOfTurnAndAllowActionOnNextTurn() throws {
        let sleepSpell = MasterData.Spell(
            id: 1,
            name: "眠り玉",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0,
            statusId: BattleAilment.sleep.rawValue,
            statusChance: 1.0
        )
        let sleepAccessSkill = MasterData.Skill(
            id: 1,
            name: "眠り玉習得",
            description: "眠り玉を習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [sleepSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [sleepAccessSkill],
            spells: [sleepSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, intelligence: 100, agility: 1_000),
            enemySkillIds: [sleepAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 100),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 30,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<16_384,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "剣士",
                        status: allyStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 100,
                            recoverySpell: 0,
                            attackSpell: 0,
                            priority: [.attack, .breath, .recoverySpell, .attackSpell]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                guard result.battleRecord.turns.count >= 2,
                      let firstTurn = result.battleRecord.turns.first,
                      let firstAction = firstTurn.actions.first else {
                    return false
                }

                let laterActions = result.battleRecord.turns.dropFirst().flatMap(\.actions)
                return firstAction.actorId == BattleCombatantID(rawValue: 1)
                    && firstAction.actionKind == .attackSpell
                    && firstAction.targetIds == [BattleCombatantID(rawValue: 1 - 1)]
                    && firstAction.results.contains(where: {
                        $0.targetId == BattleCombatantID(rawValue: 1 - 1)
                            && $0.resultKind == .modifierApplied
                            && $0.statusId == BattleAilment.sleep.rawValue
                    })
                    && firstTurn.actions.count == 1
                    && laterActions.contains(where: {
                        $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                            && $0.actionKind == .attack
                    })
            }
        )

        let laterActions = result.battleRecord.turns.dropFirst().flatMap(\.actions)
        #expect(laterActions.contains(where: {
            $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                && $0.actionKind == .attack
        }))
    }

    @Test
    func battleFallsBackToDefendWhenAllActionCandidatesAreRejected() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let allySettings = makeAutoBattleSettings(
            breath: 0,
            attack: 0,
            recoverySpell: 0,
            attackSpell: 0,
            priority: [.attack, .recoverySpell, .attackSpell, .breath]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "防御役",
                    status: allyStatus,
                    autoBattleSettings: allySettings
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        #expect(result.result == .draw)
        #expect(result.battleRecord.turns.count == 20)
        #expect(
            result.battleRecord.turns.allSatisfy { turn in
                turn.actions.allSatisfy { $0.actionKind == .defend }
            }
        )
    }

    @Test
    func explorationDrawDoesNotGrantRewards() throws {
        let masterData = makeExplorationBattleTestMasterData(
            allyBaseStats: battleBaseStats(vitality: 100, agility: 100),
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            ),
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "引き分け迷宮",
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 1,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 1, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let session = RunSessionRecord(
            partyRunId: 1,
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: 1,
            targetFloorNumber: 1,
            startedAt: Date(timeIntervalSinceReferenceDate: 600_000),
            rootSeed: 0,
            memberSnapshots: [
                makeBattleTestCharacter(
                    id: 1,
                    name: "防御役",
                    currentHP: 100,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.attack, .recoverySpell, .attackSpell, .breath]
                    )
                )
            ],
            memberCharacterIds: [1],
            completedBattleCount: 0,
            currentPartyHPs: [100],
            memberExperienceMultipliers: [1.0],
            progressIntervalMultiplier: 1,
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            partyAverageLuck: 0,
            latestBattleFloorNumber: nil,
            latestBattleNumber: nil,
            latestBattleOutcome: nil,
            battleLogs: [],
            goldBuffer: 0,
            experienceRewards: [],
            dropRewards: [],
            completion: nil
        )
        var cachedStatuses: [Int: ExplorationMemberStatusCacheEntry] = [:]

        let plannedSession = try ExplorationResolver.plan(
            session: session,
            masterData: masterData,
            cachedStatuses: &cachedStatuses
        )

        #expect(plannedSession.completedBattleCount == 1)
        #expect(plannedSession.battleLogs.count == 1)
        #expect(plannedSession.battleLogs.first?.battleRecord.result == .draw)
        #expect(plannedSession.completion?.reason == .draw)
        #expect(plannedSession.goldBuffer == 0)
        #expect(plannedSession.experienceRewards.isEmpty)
        #expect(plannedSession.dropRewards.isEmpty)
    }

    // Recovery targeting, healing amount rules, and deterministic encounter planning.
    @Test
    func recoverySpellTargetsLowestCurrentHPMember() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let healSkill = MasterData.Skill(
            id: 1,
            name: "ヒール習得",
            description: "ヒールを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [healSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [healSkill],
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerCharacter = makeBattleTestCharacter(
            id: 1,
            name: "僧侶",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0,
                priority: [.recoverySpell, .attack, .attackSpell, .breath]
            )
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healSpell.id]
        )
        let firstTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 2,
                name: "前衛A",
                currentHP: 50,
                level: 5,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )
        let secondTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 3,
                name: "前衛B",
                currentHP: 40,
                level: 10,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                PartyBattleMember(character: healerCharacter, status: healerStatus),
                firstTarget,
                secondTarget
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: 3 - 1)])
    }

    @Test
    func recoverySpellBreaksHPTiesByHigherLevel() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let healSkill = MasterData.Skill(
            id: 1,
            name: "ヒール習得",
            description: "ヒールを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [healSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [healSkill],
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerCharacter = makeBattleTestCharacter(
            id: 1,
            name: "僧侶",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0,
                priority: [.recoverySpell, .attack, .attackSpell, .breath]
            )
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healSpell.id]
        )
        let lowerLevelTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 2,
                name: "前衛A",
                currentHP: 40,
                level: 5,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )
        let higherLevelTarget = PartyBattleMember(
            character: makeBattleTestCharacter(
                id: 3,
                name: "前衛B",
                currentHP: 40,
                level: 10,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .recoverySpell, .attackSpell, .breath]
                )
            ),
            status: makeBattleTestStatus(
                battleStats: CharacterBattleStats(
                    maxHP: 100,
                    physicalAttack: 0,
                    physicalDefense: 0,
                    magic: 0,
                    magicDefense: 0,
                    healing: 0,
                    accuracy: 0,
                    evasion: 0,
                    attackCount: 1,
                    criticalRate: 0,
                    breathPower: 0
                )
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                PartyBattleMember(character: healerCharacter, status: healerStatus),
                lowerLevelTarget,
                higherLevelTarget
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: 3 - 1)])
    }

    @Test
    func recoverySpellUsesPartyHealingModifier() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let healingSupportSkill = MasterData.Skill(
            id: 2,
            name: "魔力支配",
            description: "味方全体の回復威力を30%上げる。",
            effects: [
                MasterData.SkillEffect.partyModifier(target: .allyHealingMultiplier, operation: .pctAdd, value: 0.3, condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [healingSupportSkill],
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 20,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            skillIds: [healingSupportSkill.id],
            spellIds: [healSpell.id]
        )
        let targetStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<512,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "結界師",
                        status: healerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "前衛", status: targetStatus, currentHP: 1)
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actionKind == .recoverySpell
            }
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: 2 - 1)])
        #expect(firstAction.results.first?.value == 26)
    }

    @Test
    func recoverySpellAmountIgnoresSpellMultiplierPerSpec() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "強化ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 2.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healSpell.id]
        )
        let injuredStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "僧侶",
                    status: healerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛", status: injuredStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.results.first?.value == 30)
        #expect(result.combatants.first(where: { $0.id == BattleCombatantID(rawValue: 2 - 1) })?.remainingHP == 31)
    }

    @Test
    func encounterPlanningScalesEnemyLevelAndAllowsDuplicatesUpToCap() throws {
        let hardTitle = MasterData.Title(
            id: 2,
            key: "hard",
            name: "高難度",
            positiveMultiplier: 1.6,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )
        let masterData = makeExplorationBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1),
            titles: [
                MasterData.Title(
                    id: 1,
                    key: "untitled",
                    name: "無名",
                    positiveMultiplier: 1.0,
                    negativeMultiplier: 1.0,
                    dropWeight: 1
                ),
                hardTitle
            ],
            labyrinths: [
                MasterData.Labyrinth(
                    id: 1,
                    name: "重複迷宮",
                    progressIntervalSeconds: 1,
                    floors: [
                        MasterData.Floor(
                            id: 1,
                            floorNumber: 1,
                            battleCount: 1,
                            enemyCount: 3,
                            encounters: [MasterData.Encounter(enemyId: 1, level: 3, weight: 1)],
                            fixedBattle: nil
                        )
                    ]
                )
            ]
        )
        let session = RunSessionRecord(
            partyRunId: 1,
            partyId: 1,
            labyrinthId: 1,
            selectedDifficultyTitleId: hardTitle.id,
            targetFloorNumber: 1,
            startedAt: Date(timeIntervalSinceReferenceDate: 610_000),
            rootSeed: 0,
            memberSnapshots: [
                makeBattleTestCharacter(
                    id: 1,
                    name: "探索者",
                    currentHP: 100,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 100,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.breath, .attack, .recoverySpell, .attackSpell]
                    )
                )
            ],
            memberCharacterIds: [1],
            completedBattleCount: 0,
            currentPartyHPs: [100],
            memberExperienceMultipliers: [1.0],
            progressIntervalMultiplier: 1,
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            partyAverageLuck: 0,
            latestBattleFloorNumber: nil,
            latestBattleNumber: nil,
            latestBattleOutcome: nil,
            battleLogs: [],
            goldBuffer: 0,
            experienceRewards: [],
            dropRewards: [],
            completion: nil
        )
        var cachedStatuses: [Int: ExplorationMemberStatusCacheEntry] = [:]

        let plannedSession = try ExplorationResolver.plan(
            session: session,
            masterData: masterData,
            cachedStatuses: &cachedStatuses
        )
        let enemySnapshots = plannedSession.battleLogs.first?.combatants.filter { $0.side == .enemy } ?? []

        #expect(enemySnapshots.count == 3)
        #expect(enemySnapshots.map(\.name) == ["テスト敵A", "テスト敵B", "テスト敵C"])
        #expect(enemySnapshots.allSatisfy { $0.level == 5 })
    }

    // Reward and drop resolution edge cases.
    @Test
    func superRareRateMultiplierRewardsRemainingHPAndFasterBattles() {
        let runID = RunSessionID(partyId: 1, partyRunId: 1)
        let result = SingleBattleResult(
            context: BattleContext(
                runId: runID,
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            battleRecord: BattleRecord(
                runId: runID,
                floorNumber: 1,
                battleNumber: 1,
                result: .victory,
                turns: [
                    BattleTurnRecord(turnNumber: 1, actions: []),
                    BattleTurnRecord(turnNumber: 2, actions: []),
                    BattleTurnRecord(turnNumber: 3, actions: []),
                    BattleTurnRecord(turnNumber: 4, actions: []),
                    BattleTurnRecord(turnNumber: 5, actions: [])
                ]
            ),
            combatants: [
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: 1 - 1),
                    name: "前衛",
                    side: .ally,
                    imageReference: nil,
                    level: 1,
                    initialHP: 100,
                    maxHP: 100,
                    remainingHP: 50,
                    formationIndex: 0
                ),
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: 2 - 1),
                    name: "後衛",
                    side: .ally,
                    imageReference: nil,
                    level: 1,
                    initialHP: 100,
                    maxHP: 100,
                    remainingHP: 25,
                    formationIndex: 1
                )
            ]
        )

        #expect(ExplorationResolver.superRareRateMultiplier(for: result) == 1.75)
    }

    @Test
    func titleRollCountMultipliesBaseLuckAndSkillByEnemyTitle() {
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 3,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 25,
            defaultTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            ),
            enemyTitle: MasterData.Title(
                id: 2,
                key: "eerie",
                name: "妖しい",
                positiveMultiplier: 1.5874,
                negativeMultiplier: 1.0,
                dropWeight: 1
            )
        )

        #expect(ExplorationResolver.titleRollCount(rewardContext: rewardContext) == 11)
    }

    @Test
    func resolveRewardsGuaranteesMinimumExperienceOfOnePerSurvivor() {
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [1, 2, 3],
            memberExperienceMultipliers: [1, 1, 1],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 0,
            defaultTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            ),
            enemyTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            )
        )
        let masterData = MasterData(
            metadata: MasterData.Metadata(generator: "test"),
            races: [],
            jobs: [],
            aptitudes: [],
            items: [],
            titles: [rewardContext.defaultTitle],
            superRares: [],
            skills: [],
            spells: [],
            recruitNames: MasterData.RecruitNames(
                male: [],
                female: [],
                unisex: []
            ),
            enemies: [
                MasterData.Enemy(
                    id: 1,
                    name: "微経験値敵",
                    imageAssetName: nil,
                    enemyRace: .monster,
                    jobId: 1,
                    baseStats: battleBaseStats(),
                    goldBaseValue: 0,
                    experienceBaseValue: 1,
                    skillIds: [],
                    rareDropItemIds: [],
                    actionRates: MasterData.ActionRates(
                        breath: 0,
                        attack: 1,
                        recoverySpell: 0,
                        attackSpell: 0
                    ),
                    actionPriority: [.attack, .breath, .recoverySpell, .attackSpell]
                )
            ],
            labyrinths: []
        )
        let result = SingleBattleResult(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            battleRecord: BattleRecord(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                floorNumber: 1,
                battleNumber: 1,
                result: .victory,
                turns: [BattleTurnRecord(turnNumber: 1, actions: [])]
            ),
            combatants: [
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: 1 - 1),
                    name: "前衛",
                    side: .ally,
                    imageReference: nil,
                    level: 1,
                    initialHP: 10,
                    maxHP: 10,
                    remainingHP: 10,
                    formationIndex: 0
                ),
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: 2 - 1),
                    name: "中衛",
                    side: .ally,
                    imageReference: nil,
                    level: 1,
                    initialHP: 10,
                    maxHP: 10,
                    remainingHP: 10,
                    formationIndex: 1
                ),
                BattleCombatantSnapshot(
                    id: BattleCombatantID(rawValue: 3 - 1),
                    name: "後衛",
                    side: .ally,
                    imageReference: nil,
                    level: 1,
                    initialHP: 10,
                    maxHP: 10,
                    remainingHP: 10,
                    formationIndex: 2
                )
            ]
        )

        let rewards = ExplorationResolver.resolveRewards(
            rewardContext: rewardContext,
            enemySeeds: [BattleEnemySeed(enemyId: 1, level: 1)],
            result: result,
            floorNumber: 1,
            battleNumber: 1,
            rootSeed: 0,
            masterData: masterData
        )

        #expect(rewards.experienceRewards == [
            ExplorationExperienceReward(characterId: 1, experience: 1),
            ExplorationExperienceReward(characterId: 2, experience: 1),
            ExplorationExperienceReward(characterId: 3, experience: 1)
        ])
    }

    @Test
    func resolveTitleCanReturnTitleLowerThanUntitled() {
        let untitledTitle = MasterData.Title(
            id: 1,
            key: "untitled",
            name: "無名",
            positiveMultiplier: 1.0,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )
        let roughTitle = MasterData.Title(
            id: 2,
            key: "rough",
            name: "粗末な",
            positiveMultiplier: 0.5,
            negativeMultiplier: 2.0,
            dropWeight: 1
        )
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 0,
            defaultTitle: untitledTitle,
            enemyTitle: untitledTitle
        )

        let title = ExplorationResolver.resolveTitle(
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            dropIndex: 0,
            rewardContext: rewardContext,
            titles: [roughTitle],
            rootSeed: 0
        )

        #expect(title.id == roughTitle.id)
    }

    @Test
    func normalDropTierRollCountUsesExponentialThresholds() {
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 1) == 1)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 10) == 1)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 11) == 2)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 20) == 2)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 21) == 3)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 40) == 3)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 41) == 4)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 80) == 4)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 81) == 5)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 160) == 5)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 161) == 6)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 320) == 6)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 321) == 7)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 640) == 7)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 641) == 8)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 1_280) == 8)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 1_281) == 9)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 2_560) == 9)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 2_561) == 10)
        #expect(ExplorationResolver.normalDropTierRollCount(enemyLevel: 99_999) == 10)
    }

    @Test
    func normalDropTierKeepsBestResultWhenEnemyLevelAddsRolls() {
        for seed in 0..<128 {
            let singleRollTier = ExplorationResolver.resolveNormalDropTier(
                enemyLevel: 10,
                floorNumber: 1,
                battleNumber: 1,
                enemyIndex: 0,
                rootSeed: UInt64(seed)
            )
            let doubleRollTier = ExplorationResolver.resolveNormalDropTier(
                enemyLevel: 11,
                floorNumber: 1,
                battleNumber: 1,
                enemyIndex: 0,
                rootSeed: UInt64(seed)
            )
            let tripleRollTier = ExplorationResolver.resolveNormalDropTier(
                enemyLevel: 21,
                floorNumber: 1,
                battleNumber: 1,
                enemyIndex: 0,
                rootSeed: UInt64(seed)
            )

            #expect((singleRollTier ?? 0) <= (doubleRollTier ?? 0))
            #expect((doubleRollTier ?? 0) <= (tripleRollTier ?? 0))
        }
    }

    @Test
    func normalDropJewelizeCanSelectNonNormalJewelRarity() {
        let defaultItem = MasterData.Item(
            id: 1,
            name: "テストソード",
            category: .sword,
            rarity: .normal,
            basePrice: 100,
            nativeBaseStats: MasterData.BaseStats(
                vitality: 0,
                strength: 0,
                mind: 0,
                intelligence: 0,
                agility: 0,
                luck: 0
            ),
            nativeBattleStats: MasterData.BattleStats(
                maxHP: 0,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 0,
                criticalRate: 0,
                breathPower: 0
            ),
            skillIds: [],
            rangeClass: .melee,
            normalDropTier: 1
        )
        let rareJewel = MasterData.Item(
            id: 2,
            name: "テストレア宝石",
            category: .jewel,
            rarity: .rare,
            basePrice: 100,
            nativeBaseStats: MasterData.BaseStats(
                vitality: 0,
                strength: 0,
                mind: 0,
                intelligence: 0,
                agility: 0,
                luck: 0
            ),
            nativeBattleStats: MasterData.BattleStats(
                maxHP: 0,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 0,
                criticalRate: 0,
                breathPower: 0
            ),
            skillIds: [],
            rangeClass: .none,
            normalDropTier: 0
        )
        let title = MasterData.Title(
            id: 1,
            key: "untitled",
            name: "無名",
            positiveMultiplier: 1.0,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 1,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 1,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 0,
            defaultTitle: title,
            enemyTitle: title
        )

        let item = ExplorationResolver.normalDropBaseItem(
            from: defaultItem,
            tier: 1,
            rewardContext: rewardContext,
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            rootSeed: 0,
            itemTable: [
                defaultItem.id: defaultItem,
                rareJewel.id: rareJewel
            ]
        )

        #expect(item.id == rareJewel.id)
        #expect(item.rarity == .rare)
    }

    @Test
    func rareDropRateIncludesPartyLuckBaseRate() {
        let rewardContext = ExplorationResolver.RewardContext(
            memberCharacterIds: [],
            memberExperienceMultipliers: [],
            goldMultiplier: 1,
            rareDropMultiplier: 10,
            titleRollCountModifier: 0,
            normalDropJewelizeChance: 0,
            goldPenaltyPerDamageTaken: 0,
            goldGainPctAddOnNormalKill: 0,
            partyAverageLuck: 25,
            defaultTitle: MasterData.Title(
                id: 1,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            ),
            enemyTitle: MasterData.Title(
                id: 2,
                key: "untitled",
                name: "無名",
                positiveMultiplier: 1.0,
                negativeMultiplier: 1.0,
                dropWeight: 1
            )
        )

        let expectedRate = (0.001 + cbrt(25.0) / 1_000) * 10 * 1.2
        let actualRate = ExplorationResolver.rareDropRate(enemyLevel: 27, rewardContext: rewardContext)

        #expect(abs(actualRate - expectedRate) < 0.000_000_001)
    }

    @Test
    func superRareResolutionUsesBattlePerformanceMultiplier() {
        let masterData = debugItemGenerationMasterData()
        let title = MasterData.Title(
            id: 1,
            key: "untitled",
            name: "無名",
            positiveMultiplier: 1.0,
            negativeMultiplier: 1.0,
            dropWeight: 1
        )

        let withoutBonus = ExplorationResolver.resolveSuperRareId(
            title: title,
            superRareRateMultiplier: 0,
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            dropIndex: 0,
            rootSeed: 0,
            masterData: masterData
        )
        let guaranteed = ExplorationResolver.resolveSuperRareId(
            title: title,
            superRareRateMultiplier: 1_000_000,
            floorNumber: 1,
            battleNumber: 1,
            enemyIndex: 0,
            dropIndex: 0,
            rootSeed: 0,
            masterData: masterData
        )

        #expect(withoutBonus == 0)
        #expect(guaranteed == 1)
    }

    // Defensive stance, spell-target selection, and same-battle spell usage rules.
    @Test
    func defendingHalvesPhysicalAttackDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.defend, .attack])
        let attackResult = try #require(firstTurn.actions.last?.results.first)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.physicalAttack - enemyStatus.battleStats.physicalDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )
        #expect(attackResult.value == expectedDamage)
        #expect(attackResult.flags.contains(.guarded))
    }

    @Test
    func defendingHalvesBreathDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 20
            ),
            canUseBreath: true
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "竜人",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 100,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.breath, .attack, .recoverySpell, .attackSpell]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.defend, .breath])
        let breathResult = try #require(firstTurn.actions.last?.results.first)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.breathPower - enemyStatus.battleStats.physicalDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )
        #expect(breathResult.value == expectedDamage)
        #expect(breathResult.flags.contains(.guarded))
    }

    @Test
    func defendingHalvesAttackSpellDamage() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.defend, .attackSpell])
        let spellResult = try #require(firstTurn.actions.last?.results.first)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )
        #expect(spellResult.value == expectedDamage)
        #expect(spellResult.flags.contains(.guarded))
    }

    @Test
    func attackSpellTargetsDistinctEnemiesWithoutDuplicates() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "連鎖火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 2,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.targetIds.count == 2)
        #expect(Set(firstAction.targetIds).count == 2)
    }

    @Test
    func attackSpellTargetsAllLivingEnemiesWhenTargetCountExceedsLivingCount() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "大火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 3,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.targetIds.count == 2)
        #expect(Set(firstAction.targetIds).count == 2)
    }

    @Test
    func criticalAttackSpellCanRepeatWithoutConsumingSecondCharge() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "未来火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 100,
                breathPower: 0
            ),
            spellIds: [attackSpell.id],
            actionRuleValuesByTarget: [
                .attackSpellCanCritical: [1],
                .repeatAttackSpellOnCritical: [1]
            ]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "予見者",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                let attackSpells = result.battleRecord.turns.flatMap(\.actions).filter {
                    $0.actorId == BattleCombatantID(rawValue: 1 - 1) && $0.actionKind == .attackSpell
                }
                return attackSpells.count >= 2
            }
        )

        let attackSpells = result.battleRecord.turns.flatMap(\.actions).filter {
            $0.actorId == BattleCombatantID(rawValue: 1 - 1) && $0.actionKind == .attackSpell
        }
        #expect(attackSpells.count >= 2)
    }

    @Test
    func sameSpellIsUsedAtMostOncePerBattle() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let attackSpellSkill = MasterData.Skill(
            id: 1,
            name: "火球習得",
            description: "火球を習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [attackSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [attackSpellSkill],
            spells: [attackSpell],
            allyRaceSkillIds: [attackSpellSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyCharacter = makeBattleTestCharacter(
            id: 1,
            name: "魔術師",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 1,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: allyCharacter, status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let allyActions = result.battleRecord.turns
            .flatMap(\.actions)
            .filter { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }

        #expect(allyActions.filter { $0.actionKind == .attackSpell }.count == 1)
        #expect(allyActions.dropFirst().allSatisfy { $0.actionKind == .defend })
    }

    // Determinism, naming, and action-order randomization rules.
    @Test
    func battleResolutionIsDeterministicForSameInput() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 20)
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let context = BattleContext(
            runId: RunSessionID(partyId: 1, partyRunId: 1),
            rootSeed: 42,
            floorNumber: 1,
            battleNumber: 1
        )
        let partyMembers = [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)]
        let enemies = [BattleEnemySeed(enemyId: 1, level: 1)]

        let first = try SingleBattleResolver.resolve(
            context: context,
            partyMembers: partyMembers,
            enemies: enemies,
            masterData: masterData
        )
        let second = try SingleBattleResolver.resolve(
            context: context,
            partyMembers: partyMembers,
            enemies: enemies,
            masterData: masterData
        )

        #expect(first == second)
    }

    @Test
    func duplicateEnemyNamesReceiveAlphabeticSuffixes() throws {
        let baseMasterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 20)
        )
        let templateEnemy = try #require(baseMasterData.enemies.first)
        let masterData = MasterData(
            metadata: baseMasterData.metadata,
            races: baseMasterData.races,
            jobs: baseMasterData.jobs,
            aptitudes: baseMasterData.aptitudes,
            items: baseMasterData.items,
            titles: baseMasterData.titles,
            superRares: baseMasterData.superRares,
            skills: baseMasterData.skills,
            spells: baseMasterData.spells,
            recruitNames: baseMasterData.recruitNames,
            enemies: [
                MasterData.Enemy(
                    id: 1,
                    name: "ウルフ",
                    imageAssetName: nil,
                    enemyRace: templateEnemy.enemyRace,
                    jobId: templateEnemy.jobId,
                    baseStats: templateEnemy.baseStats,
                    goldBaseValue: templateEnemy.goldBaseValue,
                    experienceBaseValue: templateEnemy.experienceBaseValue,
                    skillIds: templateEnemy.skillIds,
                    rareDropItemIds: templateEnemy.rareDropItemIds,
                    actionRates: templateEnemy.actionRates,
                    actionPriority: templateEnemy.actionPriority
                ),
                MasterData.Enemy(
                    id: 2,
                    name: "ウルフ",
                    imageAssetName: nil,
                    enemyRace: templateEnemy.enemyRace,
                    jobId: templateEnemy.jobId,
                    baseStats: templateEnemy.baseStats,
                    goldBaseValue: templateEnemy.goldBaseValue,
                    experienceBaseValue: templateEnemy.experienceBaseValue,
                    skillIds: templateEnemy.skillIds,
                    rareDropItemIds: templateEnemy.rareDropItemIds,
                    actionRates: templateEnemy.actionRates,
                    actionPriority: templateEnemy.actionPriority
                ),
                MasterData.Enemy(
                    id: 3,
                    name: "スライム",
                    imageAssetName: nil,
                    enemyRace: templateEnemy.enemyRace,
                    jobId: templateEnemy.jobId,
                    baseStats: templateEnemy.baseStats,
                    goldBaseValue: templateEnemy.goldBaseValue,
                    experienceBaseValue: templateEnemy.experienceBaseValue,
                    skillIds: templateEnemy.skillIds,
                    rareDropItemIds: templateEnemy.rareDropItemIds,
                    actionRates: templateEnemy.actionRates,
                    actionPriority: templateEnemy.actionPriority
                )
            ],
            labyrinths: baseMasterData.labyrinths
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 2, level: 1),
                BattleEnemySeed(enemyId: 3, level: 1)
            ],
            masterData: masterData
        )

        #expect(result.combatants.filter { $0.side == .enemy }.map(\.name) == ["ウルフA", "ウルフB", "スライム"])
    }

    @Test
    func skippedQueuedActionStillAdvancesActionNumberForLaterRandoms() throws {
        let sleepSpell = MasterData.Spell(
            id: 1,
            name: "眠り玉",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0,
            statusId: BattleAilment.sleep.rawValue,
            statusChance: 1.0
        )
        let sleepSkill = MasterData.Skill(
            id: 1,
            name: "眠り玉習得",
            description: "眠り玉を習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [sleepSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [sleepSkill],
            spells: [sleepSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, intelligence: 1, agility: 100),
            enemySkillIds: [sleepSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let queuedAllyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 98),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 1,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let slowerAllyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 43),
                rootSeed: 43,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "前衛A",
                    status: queuedAllyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 100,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.attack, .breath, .recoverySpell, .attackSpell]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛B", status: slowerAllyStatus),
                makePartyBattleMember(id: 3, name: "前衛C", status: slowerAllyStatus)
            ],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        let secondAction = try #require(firstTurn.actions.dropFirst().first)
        let expectedTargetIndex = expectedAttackSpellTargetIndex(
            rootSeed: 43,
            actorID: "enemy:1:2",
            spellID: sleepSpell.id,
            candidateCount: 3,
            actionNumber: 3
        )
        let expectedTargetID = BattleCombatantID(rawValue: expectedTargetIndex)

        #expect(firstAction.actorId == BattleCombatantID(rawValue: 3))
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: 1 - 1)])
        #expect(firstTurn.actions.contains(where: { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }) == false)
        #expect(secondAction.actorId == BattleCombatantID(rawValue: 4))
        #expect(secondAction.targetIds == [expectedTargetID])
    }

    @Test
    func higherSpellIDIsPreferredWhenMultipleAttackSpellsAreUsable() throws {
        let lowSpell = MasterData.Spell(
            id: 1,
            name: "小火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let highSpell = MasterData.Spell(
            id: 2,
            name: "大火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [lowSpell, highSpell],
            enemyBaseStats: battleBaseStats(vitality: 100)
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [lowSpell.id, highSpell.id]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<2_048,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "魔導士",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actionKind == .attackSpell
                    && result.battleRecord.turns.first?.actions.first?.actionRef == highSpell.id
            }
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.actionRef == highSpell.id)
    }

    @Test
    func lastAttackSpellIsUsedWhenHigherSpellIDsAreRejected() throws {
        let lowSpell = MasterData.Spell(
            id: 1,
            name: "小火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let highSpell = MasterData.Spell(
            id: 2,
            name: "大火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [lowSpell, highSpell],
            enemyBaseStats: battleBaseStats(vitality: 100)
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [lowSpell.id, highSpell.id]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<2_048,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "魔導士",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actionKind == .attackSpell
                    && result.battleRecord.turns.first?.actions.first?.actionRef == lowSpell.id
            }
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .attackSpell)
        #expect(firstAction.actionRef == lowSpell.id)
    }

    @Test
    func fullHealSpellRestoresTargetToMaxHP() throws {
        let fullHealSpell = MasterData.Spell(
            id: 1,
            name: "フルヒール",
            category: .recovery,
            kind: .fullHeal,
            targetSide: .ally,
            targetCount: 1
        )
        let masterData = makeBattleTestMasterData(
            spells: [fullHealSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 10,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [fullHealSpell.id]
        )
        let injuredStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "僧侶",
                    status: healerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛", status: injuredStatus, currentHP: 40)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(firstAction.actionRef == fullHealSpell.id)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: 2 - 1)])
        #expect(firstAction.results.first?.value == 60)
        #expect(result.combatants.first(where: { $0.id == BattleCombatantID(rawValue: 2 - 1) })?.remainingHP == 100)
    }

    @Test
    func cleanseSpellRemovesSleepAndRecordsRemovedAilment() throws {
        let cleanseSpell = MasterData.Spell(
            id: 1,
            name: "キュア",
            category: .recovery,
            kind: .cleanse,
            targetSide: .ally,
            targetCount: 1
        )
        let sleepSpell = MasterData.Spell(
            id: 2,
            name: "眠り玉",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0,
            statusId: BattleAilment.sleep.rawValue,
            statusChance: 1.0
        )
        let sleepAccessSkill = MasterData.Skill(
            id: 1,
            name: "眠り玉習得",
            description: "眠り玉を習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [sleepSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [sleepAccessSkill],
            spells: [cleanseSpell, sleepSpell],
            enemyBaseStats: battleBaseStats(vitality: 20, intelligence: 20, agility: 1_000),
            enemySkillIds: [sleepAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let healerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 100),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [cleanseSpell.id]
        )
        let victimStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "僧侶",
                        status: healerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "前衛", status: victimStatus)
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.count >= 2
                    && result.battleRecord.turns[0].actions.contains(where: { action in
                        action.actionKind == .attackSpell
                            && action.results.contains(where: {
                                $0.targetId == BattleCombatantID(rawValue: 2 - 1)
                                    && $0.resultKind == .modifierApplied
                                    && $0.statusId == BattleAilment.sleep.rawValue
                            })
                    })
                    && result.battleRecord.turns[1].actions.contains(where: { action in
                        action.actorId == BattleCombatantID(rawValue: 1 - 1)
                            && action.actionKind == .recoverySpell
                            && action.actionRef == cleanseSpell.id
                            && action.results.contains(where: {
                                $0.targetId == BattleCombatantID(rawValue: 2 - 1)
                                    && $0.resultKind == .ailmentRemoved
                                    && $0.statusId == BattleAilment.sleep.rawValue
                            })
                    })
            }
        )

        let secondTurn = try #require(result.battleRecord.turns.dropFirst().first)
        let cleanseAction = try #require(
            secondTurn.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: 1 - 1) })
        )
        #expect(cleanseAction.actionKind == .recoverySpell)
        #expect(cleanseAction.actionRef == cleanseSpell.id)
        #expect(cleanseAction.results.contains(where: {
            $0.targetId == BattleCombatantID(rawValue: 2 - 1)
                && $0.resultKind == .ailmentRemoved
                && $0.statusId == BattleAilment.sleep.rawValue
        }))
    }

    @Test
    func rescueWithSingleTargetRecoveryRevivesOnlyOneDefeatedAlly() throws {
        let singleHealSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let breathSkill = MasterData.Skill(
            id: 2,
            name: "ブレス",
            description: "ブレスを使う。",
            effects: [
                MasterData.SkillEffect.breathAccess
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [breathSkill],
            spells: [singleHealSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [breathSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 100,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            ),
            enemyActionPriority: [.breath, .attack, .recoverySpell, .attackSpell]
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 200,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [singleHealSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "僧侶",
                    status: rescuerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛A", status: victimStatus, currentHP: 1),
                makePartyBattleMember(id: 3, name: "前衛B", status: victimStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescue = try #require(firstTurn.actions.dropFirst().first(where: { $0.actionKind == .rescue }))
        #expect(rescue.actionRef == singleHealSpell.id)
        #expect(rescue.targetIds.count == 1)
        #expect(rescue.results.count == 1)
        #expect(rescue.results.first?.flags.contains(.revived) == true)
        #expect(rescue.results.first?.value == 30)
    }

    @Test
    func criticalAttackSetsActionFlag() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100)
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 100,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: attackerStatus)],
                masterData: masterData
            ) { result in
                result.battleRecord.turns
                    .flatMap(\.actions)
                    .contains(where: { $0.actionKind == .attack && $0.actionFlags.contains(.critical) })
            }
        )

        #expect(
            result.battleRecord.turns
                .flatMap(\.actions)
                .contains(where: { $0.actionKind == .attack && $0.actionFlags.contains(.critical) })
        )
    }

    @Test
    func actionSpeedMultiplierChangesTurnOrder() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let fastStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 10),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            battleDerivedStats: makeBattleDerivedStats(actionSpeedMultiplier: 2.0)
        )
        let slowStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 10),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            battleDerivedStats: makeBattleDerivedStats(actionSpeedMultiplier: 0.5)
        )
        let defendOnly = makeAutoBattleSettings(
            breath: 0,
            attack: 0,
            recoverySpell: 0,
            attackSpell: 0,
            priority: [.attack, .recoverySpell, .attackSpell, .breath]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(id: 1, name: "高速", status: fastStatus, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 2, name: "低速", status: slowStatus, autoBattleSettings: defendOnly)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let fastIndex = try #require(firstTurn.actions.firstIndex(where: { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }))
        let slowIndex = try #require(firstTurn.actions.firstIndex(where: { $0.actorId == BattleCombatantID(rawValue: 2 - 1) }))
        #expect(fastIndex < slowIndex)
    }

    @Test
    func actionOrderTieBreakPrefersHigherLuckWhenScoresMatch() {
        let highLuck = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 20,
            agility: 10,
            formationIndex: 1
        )
        let lowLuck = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 0
        )

        #expect(BattleActionOrderPriorityKey.ordersBefore(highLuck, lowLuck))
        #expect(BattleActionOrderPriorityKey.ordersBefore(lowLuck, highLuck) == false)
    }

    @Test
    func actionOrderTieBreakPrefersHigherAgilityWhenLuckMatches() {
        let fast = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 20,
            formationIndex: 1
        )
        let slow = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 0
        )

        #expect(BattleActionOrderPriorityKey.ordersBefore(fast, slow))
        #expect(BattleActionOrderPriorityKey.ordersBefore(slow, fast) == false)
    }

    @Test
    func actionOrderTieBreakPrefersEarlierFormationWhenLuckAndAgilityMatch() {
        let earlier = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 0
        )
        let later = BattleActionOrderPriorityKey(
            initiativeScore: 10,
            luck: 10,
            agility: 10,
            formationIndex: 1
        )

        #expect(BattleActionOrderPriorityKey.ordersBefore(earlier, later))
        #expect(BattleActionOrderPriorityKey.ordersBefore(later, earlier) == false)
    }

    @Test
    func randomizeNormalActionOrderCanLetSlowActorMoveFirst() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let slowStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            actionRuleValuesByTarget: [.randomizeNormalActionOrder: [1]]
        )
        let fastStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "鈍足", status: slowStatus),
                    makePartyBattleMember(id: 2, name: "俊足", status: fastStatus)
                ],
                masterData: masterData
            ) { result in
                result.battleRecord.turns.first?.actions.first?.actorId == BattleCombatantID(rawValue: 1 - 1)
            }
        )

        #expect(result.battleRecord.turns.first?.actions.first?.actorId == BattleCombatantID(rawValue: 1 - 1))
    }

    // Multi-hit attack flow, carry-over damage, and variance effects.
    @Test
    func physicalAttackTargetsMiddleRankWhenFrontRankIsDefeated() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 20, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let defendOnly = makeAutoBattleSettings(
            breath: 0,
            attack: 0,
            recoverySpell: 0,
            attackSpell: 0,
            priority: [.attack, .recoverySpell, .attackSpell, .breath]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(id: 1, name: "前衛A", status: allyStatus, currentHP: 0, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 2, name: "前衛B", status: allyStatus, currentHP: 0, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 3, name: "中衛", status: allyStatus, autoBattleSettings: defendOnly),
                makePartyBattleMember(id: 4, name: "後衛", status: allyStatus, autoBattleSettings: defendOnly)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)
        #expect(firstAction.actorId == BattleCombatantID(rawValue: 4))
        #expect(firstAction.actionKind == .attack)
        #expect(firstAction.targetIds == [BattleCombatantID(rawValue: 3 - 1)])
    }

    @Test
    func normalAttackHitsRandomAdditionalTarget() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            actionRuleValuesByTarget: [.normalAttackHitsRandomAdditionalTarget: [1]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "豪腕", status: attackerStatus)],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let attack = try #require(result.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }))
        #expect(attack.actionKind == .attack)
        #expect(attack.targetIds.count == 2)
        #expect(Set(attack.targetIds).count == 2)
        #expect(attack.targetIds.contains(BattleCombatantID(rawValue: 1)))
    }

    @Test
    func carryOverRemainingHitsOnKillTransfersToNextEnemy() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 10,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 3,
                criticalRate: 0,
                breathPower: 0
            ),
            actionRuleValuesByTarget: [.carryOverRemainingHitsOnKill: [1]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "連破役", status: attackerStatus)],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let attack = try #require(result.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }))
        let damageResults = attack.results.filter { $0.resultKind == .damage }
        #expect(attack.actionKind == .attack)
        #expect(Set(attack.targetIds) == [
            BattleCombatantID(rawValue: 1),
            BattleCombatantID(rawValue: 2)
        ])
        #expect(damageResults.count == 2)
        #expect(damageResults.contains { $0.flags.contains(.defeated) })
    }

    @Test
    func breathCanQueueNormalAttackFollowUp() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 20
            ),
            canUseBreath: true,
            actionRuleValuesByTarget: [.normalAttackAfterBreath: [1]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "竜息役",
                    status: attackerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 100,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 0,
                        priority: [.breath, .attack, .recoverySpell, .attackSpell]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurnActions = try #require(result.battleRecord.turns.first?.actions)
        let actorActions = firstTurnActions.filter { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }
        #expect(actorActions.map(\.actionKind) == [.breath, .attack])
    }

    @Test
    func multiHitAttackUsesDecayAcrossHits() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let singleHitStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let multiHitStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 3,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let singleHitResult = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "単発役", status: singleHitStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )
        let singleHitDamage = try #require(firstDamageValue(in: singleHitResult, actionKind: .attack))
        let expectedMultiHitDamage = Int((Double(singleHitDamage) * 1.75).rounded())
        let multiHitResult = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "連撃役", status: multiHitStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) == expectedMultiHitDamage
            }
        )

        #expect(firstDamageValue(in: multiHitResult, actionKind: .attack) == expectedMultiHitDamage)
    }

    @Test
    func startTurnSelfDamageAppliesBeforeActionResolution() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 1),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 200,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            combatRuleValuesByTarget: [.startTurnSelfCurrentHPLossPct: [0.5]]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(id: 1, name: "狂戦士", status: attackerStatus)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let attackerSnapshot = try #require(
            result.combatants.first(where: { $0.id == BattleCombatantID(rawValue: 1 - 1) })
        )
        #expect(attackerSnapshot.remainingHP == 50)
    }

    @Test
    func damageVarianceWidthMultiplierCanChangeNormalAttackDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            hitRuleValuesByTarget: [.damageVarianceWidthMultiplier: [2.0]]
        )
        let baselineStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let baselineResult = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [makePartyBattleMember(id: 1, name: "基準", status: baselineStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack) != nil
            }
        )
        let baselineDamage = try #require(firstDamageValue(in: baselineResult, actionKind: .attack))

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<4_096,
                partyMembers: [makePartyBattleMember(id: 1, name: "道化師", status: attackerStatus)],
                masterData: masterData
            ) { result in
                firstDamageValue(in: result, actionKind: .attack).map { $0 != baselineDamage } ?? false
            }
        )

        #expect(firstDamageValue(in: result, actionKind: .attack) != baselineDamage)
    }

    @Test
    func luckyHitCanDoubleNormalAttackDamage() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            hitRuleValuesByTarget: [
                .hitDamageLuckyChance: [1.0],
                .hitDamageLuckyMultiplier: [2.0]
            ]
        )
        let baselineStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let baselineResult = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "基準", status: baselineStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        let baselineDamage = try #require(firstDamageValue(in: baselineResult, actionKind: .attack))

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "道化師", status: attackerStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        #expect(firstDamageValue(in: result, actionKind: .attack) == baselineDamage * 2)
    }

    @Test
    func unluckyHitCanHalveAttackSpellDamage() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id],
            hitRuleValuesByTarget: [
                .hitDamageUnluckyChance: [1.0],
                .hitDamageUnluckyMultiplier: [0.5]
            ]
        )
        let baselineStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )
        let baselineResult = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "基準",
                    status: baselineStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        let baselineDamage = try #require(firstDamageValue(in: baselineResult, actionKind: .attackSpell))

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "道化師",
                    status: casterStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        #expect(firstDamageValue(in: result, actionKind: .attackSpell) == Int((Double(baselineDamage) * 0.5).rounded()))
    }

    @Test
    func unarmedRepeatAttackDoesNotChain() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 0),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            isUnarmed: true,
            weaponRangeClass: .none
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [makePartyBattleMember(id: 1, name: "格闘家", status: attackerStatus)],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                let firstTurnAttacks = firstTurn.actions.filter {
                    $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                        && ($0.actionKind == .attack || $0.actionKind == .unarmedRepeat)
                }
                return firstTurnAttacks.count == 2
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstTurnAttacks = firstTurn.actions.filter {
            $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                && ($0.actionKind == .attack || $0.actionKind == .unarmedRepeat)
        }
        #expect(firstTurnAttacks.count == 2)
        #expect(firstTurnAttacks.map(\.actionKind) == [.attack, .unarmedRepeat])
    }

    @Test
    func spellChargesResetBetweenBattles() throws {
        let attackSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )
        let partyMembers = [
            makePartyBattleMember(
                id: 1,
                name: "魔導士",
                status: casterStatus,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 0,
                    recoverySpell: 0,
                    attackSpell: 100,
                    priority: [.attackSpell, .attack, .recoverySpell, .breath]
                )
            )
        ]

        var resolvedPair: (SingleBattleResult, SingleBattleResult)?
        for seed in 0..<256 {
            let firstBattle = try SingleBattleResolver.resolve(
                context: BattleContext(
                    runId: RunSessionID(partyId: 1, partyRunId: seed + 1),
                    rootSeed: UInt64(seed),
                    floorNumber: 1,
                    battleNumber: 1
                ),
                partyMembers: partyMembers,
                enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
                masterData: masterData
            )
            let secondBattle = try SingleBattleResolver.resolve(
                context: BattleContext(
                    runId: RunSessionID(partyId: 1, partyRunId: seed + 1),
                    rootSeed: UInt64(seed),
                    floorNumber: 1,
                    battleNumber: 2
                ),
                partyMembers: partyMembers,
                enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
                masterData: masterData
            )
            let firstSpellCount = firstBattle.battleRecord.turns
                .flatMap(\.actions)
                .filter { $0.actorId == BattleCombatantID(rawValue: 1 - 1) && $0.actionKind == .attackSpell }
                .count
            let secondSpellCount = secondBattle.battleRecord.turns
                .flatMap(\.actions)
                .filter { $0.actorId == BattleCombatantID(rawValue: 1 - 1) && $0.actionKind == .attackSpell }
                .count
            if firstSpellCount == 1 && secondSpellCount == 1 {
                resolvedPair = (firstBattle, secondBattle)
                break
            }
        }

        let (firstBattle, secondBattle) = try #require(resolvedPair)
        #expect(firstBattle.battleRecord.turns.flatMap(\.actions).contains {
            $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                && $0.actionKind == .attackSpell
                && $0.actionRef == attackSpell.id
        })
        #expect(secondBattle.battleRecord.turns.flatMap(\.actions).contains {
            $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                && $0.actionKind == .attackSpell
                && $0.actionRef == attackSpell.id
        })
    }

    // Interrupt ordering and rescue activation coverage.
    @Test
    func simultaneousInterruptsResolveInPriorityOrder() throws {
        let counterSkill = MasterData.Skill(
            id: 1,
            name: "反撃",
            description: "反撃する。",
            effects: [
                MasterData.SkillEffect.interruptGrant(interruptKind: .counter, condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [counterSkill],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1),
            enemySkillIds: [counterSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            interruptKinds: [.extraAttack]
        )
        let pursuerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 500),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            interruptKinds: [.pursuit]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "剣士", status: attackerStatus),
                    makePartyBattleMember(id: 2, name: "狩人", status: pursuerStatus)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                return Array(firstTurn.actions.prefix(4).map(\.actionKind)) == [
                    .attack,
                    .counter,
                    .extraAttack,
                    .pursuit
                ]
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(4).map(\.actionKind)) == [
            .attack,
            .counter,
            .extraAttack,
            .pursuit
        ])
    }

    @Test
    func multiplePursuersCanTriggerFromSameAttack() throws {
        let masterData = makeBattleTestMasterData(
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let firstPursuerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 600),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            interruptKinds: [.pursuit]
        )
        let secondPursuerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 300),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 5,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            interruptKinds: [.pursuit]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<32_768,
                partyMembers: [
                    makePartyBattleMember(id: 1, name: "剣士", status: attackerStatus),
                    makePartyBattleMember(id: 2, name: "狩人A", status: firstPursuerStatus),
                    makePartyBattleMember(id: 3, name: "狩人B", status: secondPursuerStatus)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first else {
                    return false
                }
                return Array(firstTurn.actions.prefix(3).map(\.actionKind)) == [
                    .attack,
                    .pursuit,
                    .pursuit
                ]
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstThreeActions = Array(firstTurn.actions.prefix(3))
        #expect(firstThreeActions.map(\.actionKind) == [.attack, .pursuit, .pursuit])
        #expect(firstThreeActions[1].actorId == BattleCombatantID(rawValue: 2 - 1))
        #expect(firstThreeActions[2].actorId == BattleCombatantID(rawValue: 3 - 1))
    }

    @Test
    func rescueTriggersWhenEnemyAttackDefeatsAnAlly() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "僧侶",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "前衛", status: victimStatus, currentHP: 1)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first,
                      firstTurn.actions.count >= 2 else {
                    return false
                }
                let attack = firstTurn.actions[0]
                let rescue = firstTurn.actions[1]
                return attack.actionKind == .attack
                    && attack.targetIds == [BattleCombatantID(rawValue: 2 - 1)]
                    && rescue.actionKind == .rescue
                    && rescue.targetIds == [BattleCombatantID(rawValue: 2 - 1)]
                    && rescue.results.first?.flags.contains(.revived) == true
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.attack, .rescue])
        #expect(firstTurn.actions[1].results.first?.value == 30)
    }

    @Test
    func rescueTriggersWhenEnemyCounterDefeatsAnAlly() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let counterSkill = MasterData.Skill(
            id: 2,
            name: "反撃",
            description: "反撃する。",
            effects: [
                MasterData.SkillEffect.interruptGrant(interruptKind: .counter, condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [counterSkill],
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 1),
            enemySkillIds: [counterSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let attackerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 40,
                physicalAttack: 1,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "僧侶",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(id: 2, name: "剣士", status: attackerStatus, currentHP: 1)
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first,
                      firstTurn.actions.count >= 3 else {
                    return false
                }
                let attack = firstTurn.actions[0]
                let counter = firstTurn.actions[1]
                let rescue = firstTurn.actions[2]
                return attack.actionKind == .attack
                    && counter.actionKind == .counter
                    && counter.targetIds == [BattleCombatantID(rawValue: 2 - 1)]
                    && counter.results.first?.flags.contains(.defeated) == true
                    && rescue.actionKind == .rescue
                    && rescue.targetIds == [BattleCombatantID(rawValue: 2 - 1)]
                    && rescue.results.first?.flags.contains(.revived) == true
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        #expect(Array(firstTurn.actions.prefix(3).map(\.actionKind)) == [.attack, .counter, .rescue])
    }

    @Test
    func rescueTriggersWhenEnemyBreathDefeatsMultipleAllies() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let breathSkill = MasterData.Skill(
            id: 2,
            name: "ブレス",
            description: "ブレスを使う。",
            effects: [
                MasterData.SkillEffect.breathAccess
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [breathSkill],
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [breathSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 100,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            ),
            enemyActionPriority: [.breath, .attack, .recoverySpell, .attackSpell]
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "僧侶",
                    status: rescuerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛A", status: victimStatus, currentHP: 1),
                makePartyBattleMember(id: 3, name: "前衛B", status: victimStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescue = try #require(firstTurn.actions.dropFirst().first(where: { $0.actionKind == .rescue }))

        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.breath, .rescue])
        #expect(Set(rescue.targetIds) == Set([
            BattleCombatantID(rawValue: 2 - 1),
            BattleCombatantID(rawValue: 3 - 1)
        ]))
        #expect(rescue.results.allSatisfy { $0.flags.contains(.revived) && $0.value == 30 })
    }

    @Test
    func rescueTriggersWhenEnemyAttackSpellDefeatsMultipleAllies() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let attackSpell = MasterData.Spell(
            id: 2,
            name: "ファイアストーム",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 3,
            multiplier: 1.0
        )
        let attackSpellSkill = MasterData.Skill(
            id: 3,
            name: "ファイアストーム習得",
            description: "ファイアストームを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [attackSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [attackSpellSkill],
            spells: [healAllSpell, attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, intelligence: 100, agility: 1_000),
            enemySkillIds: [attackSpellSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "僧侶",
                    status: rescuerStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 100,
                        attackSpell: 0,
                        priority: [.recoverySpell, .attack, .attackSpell, .breath]
                    )
                ),
                makePartyBattleMember(id: 2, name: "前衛A", status: victimStatus, currentHP: 1),
                makePartyBattleMember(id: 3, name: "前衛B", status: victimStatus, currentHP: 1)
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescue = try #require(firstTurn.actions.dropFirst().first(where: { $0.actionKind == .rescue }))

        #expect(Array(firstTurn.actions.prefix(2).map(\.actionKind)) == [.attackSpell, .rescue])
        #expect(Set(rescue.targetIds) == Set([
            BattleCombatantID(rawValue: 2 - 1),
            BattleCombatantID(rawValue: 3 - 1)
        ]))
        #expect(rescue.results.allSatisfy { $0.flags.contains(.revived) && $0.value == 30 })
    }

    @Test
    func rescueDoesNotTriggerWhenNoAllyIsDefeated() throws {
        let healAllSpell = MasterData.Spell(
            id: 1,
            name: "ヒールオール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healAllSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 1, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healAllSpell.id],
            interruptKinds: [.rescue]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "僧侶", status: rescuerStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        #expect(result.battleRecord.turns.flatMap(\.actions).contains { $0.actionKind == .rescue } == false)
    }

    @Test
    func secondRescueInterruptIsDiscardedAfterFirstRevivesTarget() throws {
        let healSpell = MasterData.Spell(
            id: 1,
            name: "ヒール",
            category: .recovery,
            kind: .heal,
            targetSide: .ally,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [healSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 1_000),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let rescuerStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 30,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [healSpell.id],
            interruptKinds: [.rescue]
        )
        let victimStatus = makeBattleTestStatus(
            battleStats: CharacterBattleStats(
                maxHP: 40,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "前衛",
                        status: victimStatus,
                        currentHP: 1,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 100,
                            recoverySpell: 0,
                            attackSpell: 0,
                            priority: [.attack, .breath, .recoverySpell, .attackSpell]
                        )
                    ),
                    makePartyBattleMember(
                        id: 2,
                        name: "僧侶A",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    ),
                    makePartyBattleMember(
                        id: 3,
                        name: "僧侶B",
                        status: rescuerStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 100,
                            attackSpell: 0,
                            priority: [.recoverySpell, .attack, .attackSpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                guard let firstTurn = result.battleRecord.turns.first,
                      let attack = firstTurn.actions.first else {
                    return false
                }
                let rescues = firstTurn.actions.filter { $0.actionKind == .rescue }
                return attack.actorId == BattleCombatantID(rawValue: 3)
                    && attack.actionKind == .attack
                    && attack.targetIds == [BattleCombatantID(rawValue: 1 - 1)]
                    && rescues.count == 1
                    && rescues[0].targetIds == [BattleCombatantID(rawValue: 1 - 1)]
                    && rescues[0].results.first?.flags.contains(.revived) == true
            }
        )

        let firstTurn = try #require(result.battleRecord.turns.first)
        let rescues = firstTurn.actions.filter { $0.actionKind == .rescue }
        #expect(rescues.count == 1)
        #expect(rescues.first?.results.first?.value == 30)
    }

    @Test
    func rescueValidationRejectsInactiveRescuer() {
        #expect(
            RescueResolutionValidation.survivingDefeatedTargetIndices(
                from: [1],
                aliveStates: [true, false],
                actorCanAct: false
            ) == nil
        )
    }

    @Test
    func sleepDoesNotCarryIntoNextBattle() throws {
        let sleepSpell = MasterData.Spell(
            id: 1,
            name: "眠り玉",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0,
            statusId: BattleAilment.sleep.rawValue,
            statusChance: 1.0
        )
        let sleepAccessSkill = MasterData.Skill(
            id: 1,
            name: "眠り玉習得",
            description: "眠り玉を習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [sleepSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [sleepAccessSkill],
            spells: [sleepSpell],
            enemyBaseStats: battleBaseStats(vitality: 1, intelligence: 100, agility: 95),
            enemySkillIds: [sleepAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100
            ),
            enemyActionPriority: [.attackSpell, .attack, .recoverySpell, .breath]
        )
        let frontlinerStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 100),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 30,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let finisherStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 10),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 30,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )
        let partyMembers = [
            makePartyBattleMember(
                id: 1,
                name: "前衛A",
                status: frontlinerStatus,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 100,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .breath, .recoverySpell, .attackSpell]
                )
            ),
            makePartyBattleMember(
                id: 2,
                name: "前衛B",
                status: finisherStatus,
                autoBattleSettings: makeAutoBattleSettings(
                    breath: 0,
                    attack: 100,
                    recoverySpell: 0,
                    attackSpell: 0,
                    priority: [.attack, .breath, .recoverySpell, .attackSpell]
                )
            )
        ]

        var matchingPair: (SingleBattleResult, SingleBattleResult)?
        for seed in 0..<16_384 {
            let firstBattle = try SingleBattleResolver.resolve(
                context: BattleContext(
                    runId: RunSessionID(partyId: 1, partyRunId: seed + 1),
                    rootSeed: UInt64(seed),
                    floorNumber: 1,
                    battleNumber: 1
                ),
                partyMembers: partyMembers,
                enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
                masterData: masterData
            )
            let secondBattle = try SingleBattleResolver.resolve(
                context: BattleContext(
                    runId: RunSessionID(partyId: 1, partyRunId: seed + 1),
                    rootSeed: UInt64(seed),
                    floorNumber: 1,
                    battleNumber: 2
                ),
                partyMembers: partyMembers,
                enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
                masterData: masterData
            )
            guard let firstBattleFirstTurn = firstBattle.battleRecord.turns.first,
                  let firstBattleFirstAction = firstBattleFirstTurn.actions.first,
                  let secondBattleFirstTurn = secondBattle.battleRecord.turns.first else {
                continue
            }

            let sleepAppliedToFrontliner = firstBattleFirstAction.results.contains(where: {
                $0.targetId == BattleCombatantID(rawValue: 1 - 1)
                    && $0.resultKind == .modifierApplied
                    && $0.statusId == BattleAilment.sleep.rawValue
            })
            let frontlinerActsInSecondBattleOpeningTurn = secondBattleFirstTurn.actions.contains(where: {
                $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                    && $0.actionKind == .attack
            })
            if firstBattleFirstAction.actorId == BattleCombatantID(rawValue: 2)
                && firstBattleFirstAction.actionKind == .attackSpell
                && firstBattleFirstAction.targetIds == [BattleCombatantID(rawValue: 1 - 1)]
                && sleepAppliedToFrontliner
                && frontlinerActsInSecondBattleOpeningTurn {
                matchingPair = (firstBattle, secondBattle)
                break
            }
        }

        let (firstBattle, secondBattle) = try #require(matchingPair)
        let firstBattleFirstAction = try #require(firstBattle.battleRecord.turns.first?.actions.first)
        let secondBattleFirstTurn = try #require(secondBattle.battleRecord.turns.first)

        #expect(firstBattleFirstAction.actionKind == .attackSpell)
        #expect(firstBattleFirstAction.targetIds == [BattleCombatantID(rawValue: 1 - 1)])
        #expect(firstBattleFirstAction.results.contains(where: {
            $0.targetId == BattleCombatantID(rawValue: 1 - 1)
                && $0.resultKind == .modifierApplied
                && $0.statusId == BattleAilment.sleep.rawValue
        }))
        #expect(secondBattleFirstTurn.actions.contains(where: {
            $0.actorId == BattleCombatantID(rawValue: 1 - 1)
                && $0.actionKind == .attack
        }))
    }

    // Exploration-specific rebuild rules and persistent combat modifiers.
    @Test
    func explorationRebuildsPartyStatusWithoutBattleBuffsOrBarriers() throws {
        let attackBuffSpell = MasterData.Spell(
            id: 1,
            name: "攻撃バフ",
            category: .attack,
            kind: .buff,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.5,
            effectTarget: .physicalDamage
        )
        let physicalBarrierSpell = MasterData.Spell(
            id: 2,
            name: "物理バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: .physicalDamageTaken
        )
        let attackBuffSkill = MasterData.Skill(
            id: 1,
            name: "攻撃バフ習得",
            description: "攻撃バフを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [attackBuffSpell.id], condition: nil)
            ]
        )
        let barrierSkill = MasterData.Skill(
            id: 2,
            name: "物理バリア習得",
            description: "物理バリアを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [physicalBarrierSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [attackBuffSkill, barrierSkill],
            spells: [attackBuffSpell, physicalBarrierSpell],
            allyBaseStats: battleBaseStats(vitality: 100, strength: 100, agility: 100),
            allyRaceSkillIds: [attackBuffSkill.id, barrierSkill.id],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let baselineMember = makeBattleTestCharacter(
            id: 1,
            name: "剣士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 100,
                recoverySpell: 0,
                attackSpell: 0,
                priority: [.attack, .attackSpell, .recoverySpell, .breath]
            )
        )
        let baselineStatus = try #require(CharacterDerivedStatsCalculator.status(for: baselineMember, masterData: masterData))

        let buffMember = makeBattleTestCharacter(
            id: 1,
            name: "剣士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 100,
                priority: [.attackSpell, .attack, .recoverySpell, .breath]
            )
        )
        let buffBattle = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: buffMember, status: baselineStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        let barrierMember = makeBattleTestCharacter(
            id: 1,
            name: "剣士",
            currentHP: 100,
            autoBattleSettings: makeAutoBattleSettings(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0,
                priority: [.recoverySpell, .attack, .attackSpell, .breath]
            )
        )
        let barrierBattle = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 1,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [PartyBattleMember(character: barrierMember, status: baselineStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )
        let buffAction = try #require(
            buffBattle.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: 1 - 1) })
        )
        let barrierAction = try #require(
            barrierBattle.battleRecord.turns.first?.actions.first(where: { $0.actorId == BattleCombatantID(rawValue: 1 - 1) })
        )
        var buffCache: [Int: ExplorationMemberStatusCacheEntry] = [:]
        var barrierCache: [Int: ExplorationMemberStatusCacheEntry] = [:]
        let resolvedAfterBuff = try ExplorationResolver.rebuildPartyMembersAfterBattle(
            from: [buffMember],
            currentPartyHPs: buffBattle.partyRemainingHPs,
            masterData: masterData,
            cachedStatuses: &buffCache
        )
        let resolvedAfterBarrier = try ExplorationResolver.rebuildPartyMembersAfterBattle(
            from: [barrierMember],
            currentPartyHPs: barrierBattle.partyRemainingHPs,
            masterData: masterData,
            cachedStatuses: &barrierCache
        )

        #expect(buffAction.actionKind == .attackSpell)
        #expect(buffAction.actionRef == attackBuffSpell.id)
        #expect(buffAction.results.allSatisfy { $0.resultKind == .modifierApplied })
        #expect(barrierAction.actionKind == .recoverySpell)
        #expect(barrierAction.actionRef == physicalBarrierSpell.id)
        #expect(barrierAction.results.allSatisfy { $0.resultKind == .modifierApplied })
        #expect(resolvedAfterBuff.first?.status == baselineStatus)
        #expect(resolvedAfterBarrier.first?.status == baselineStatus)
    }

    @Test
    func attackBuffIncreasesLaterPhysicalAttackDamage() throws {
        let attackBuffSpell = MasterData.Spell(
            id: 1,
            name: "攻撃バフ",
            category: .attack,
            kind: .buff,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.5,
            effectTarget: .physicalDamage
        )
        let masterData = makeBattleTestMasterData(
            spells: [attackBuffSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackBuffSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "剣士",
                    status: allyStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 100,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let allyActions = result.battleRecord.turns
            .flatMap(\.actions)
            .filter { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }
        let firstAttack = try #require(allyActions.first(where: { $0.actionKind == .attack }))

        #expect(allyActions.first?.actionKind == .attackSpell)
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.physicalAttack - enemyStatus.battleStats.physicalDefense, 0))
                    * 1.5
                ).rounded()
            ),
            1
        )

        #expect(firstAttack.results.first?.value == expectedDamage)
    }

    @Test
    func magicBuffIncreasesLaterAttackSpellDamage() throws {
        let damageSpell = MasterData.Spell(
            id: 1,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let magicBuffSpell = MasterData.Spell(
            id: 2,
            name: "魔法バフ",
            category: .attack,
            kind: .buff,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 1.5,
            effectTarget: .magicDamage
        )
        let masterData = makeBattleTestMasterData(
            spells: [damageSpell, magicBuffSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [damageSpell.id, magicBuffSpell.id]
        )

        let result = try #require(
            firstResolvedBattle(
                matchingSeeds: 0..<8_192,
                partyMembers: [
                    makePartyBattleMember(
                        id: 1,
                        name: "魔導士",
                        status: casterStatus,
                        autoBattleSettings: makeAutoBattleSettings(
                            breath: 0,
                            attack: 0,
                            recoverySpell: 0,
                            attackSpell: 100,
                            priority: [.attackSpell, .attack, .recoverySpell, .breath]
                        )
                    )
                ],
                masterData: masterData
            ) { result in
                let allyActions = result.battleRecord.turns
                    .flatMap(\.actions)
                    .filter { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }
                return allyActions.first?.actionKind == .attackSpell
                    && allyActions.first?.actionRef == magicBuffSpell.id
                    && allyActions.contains(where: {
                        $0.actionKind == .attackSpell
                            && $0.actionRef == damageSpell.id
                            && $0.results.contains(where: { $0.resultKind == .damage })
                    })
            }
        )

        let allyActions = result.battleRecord.turns
            .flatMap(\.actions)
            .filter { $0.actorId == BattleCombatantID(rawValue: 1 - 1) }
        let damageAction = try #require(allyActions.first(where: { $0.actionRef == damageSpell.id }))
        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100),
                jobId: 1,
                level: 1,
                skillIds: [],
                masterData: masterData
            )
        )
        let expectedDamage = max(
            Int(
                (
                    Double(max(casterStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
                    * 1.5
                    * (damageSpell.multiplier ?? 1.0)
                ).rounded()
            ),
            1
        )

        #expect(allyActions.first?.actionRef == magicBuffSpell.id)
        #expect(damageAction.results.first?.value == expectedDamage)
    }

    @Test
    func physicalBarrierReducesIncomingPhysicalDamage() throws {
        let physicalBarrierSpell = MasterData.Spell(
            id: 1,
            name: "物理バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: .physicalDamageTaken
        )
        let barrierAccessSkill = MasterData.Skill(
            id: 1,
            name: "物理バリア習得",
            description: "物理バリアを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [physicalBarrierSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [barrierAccessSkill],
            spells: [physicalBarrierSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [barrierAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0
            ),
            enemyActionPriority: [.recoverySpell, .attack, .attackSpell, .breath]
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            )
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "剣士", status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [barrierAccessSkill.id],
                masterData: masterData
            )
        )
        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        let secondAction = try #require(firstTurn.actions.last)
        let expectedDamage = max(
            Int(
                (
                    Double(max(allyStatus.battleStats.physicalAttack - enemyStatus.battleStats.physicalDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )

        #expect(firstAction.actorId == BattleCombatantID(rawValue: 1))
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(secondAction.actorId == BattleCombatantID(rawValue: 1 - 1))
        #expect(secondAction.actionKind == .attack)
        #expect(secondAction.results.first?.value == expectedDamage)
    }

    @Test
    func normalAttackBreaksPhysicalBarrierOnHitAndIgnoresPhysicalDefense() throws {
        let physicalBarrierSpell = MasterData.Spell(
            id: 1,
            name: "物理バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: .physicalDamageTaken
        )
        let barrierAccessSkill = MasterData.Skill(
            id: 1,
            name: "物理バリア習得",
            description: "物理バリアを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [physicalBarrierSpell.id], condition: nil)
            ]
        )
        let masterData = makeBattleTestMasterData(
            skills: [barrierAccessSkill],
            spells: [physicalBarrierSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [barrierAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0
            ),
            enemyActionPriority: [.recoverySpell, .attack, .attackSpell, .breath]
        )
        let allyStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 20,
                physicalDefense: 0,
                magic: 0,
                magicDefense: 0,
                healing: 0,
                accuracy: 1_000,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            actionRuleValuesByTarget: [
                .normalAttackBreakPhysicalBarrierOnHit: [1],
                .normalAttackIgnorePhysicalDefensePct: [0.3]
            ]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [makePartyBattleMember(id: 1, name: "暴君", status: allyStatus)],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [barrierAccessSkill.id],
                masterData: masterData
            )
        )
        let secondAction = try #require(result.battleRecord.turns.first?.actions.last)
        let expectedDamage = max(
            Int(
                (
                    Double(allyStatus.battleStats.physicalAttack)
                    - (Double(enemyStatus.battleStats.physicalDefense) * 0.7)
                ).rounded()
            ),
            1
        )

        #expect(secondAction.actorId == BattleCombatantID(rawValue: 1 - 1))
        #expect(secondAction.actionKind == .attack)
        #expect(secondAction.results.first?.value == expectedDamage)
    }

    @Test
    func magicBarrierReducesIncomingAttackSpellDamage() throws {
        let magicBarrierSpell = MasterData.Spell(
            id: 1,
            name: "魔法バリア",
            category: .recovery,
            kind: .barrier,
            targetSide: .ally,
            targetCount: 0,
            multiplier: 0.5,
            effectTarget: .magicDamageTaken
        )
        let barrierAccessSkill = MasterData.Skill(
            id: 1,
            name: "魔法バリア習得",
            description: "魔法バリアを習得する。",
            effects: [
                MasterData.SkillEffect.magicAccess(operation: .grant, spellIds: [magicBarrierSpell.id], condition: nil)
            ]
        )
        let attackSpell = MasterData.Spell(
            id: 2,
            name: "火球",
            category: .attack,
            kind: .damage,
            targetSide: .enemy,
            targetCount: 1,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            skills: [barrierAccessSkill],
            spells: [magicBarrierSpell, attackSpell],
            enemyBaseStats: battleBaseStats(vitality: 100, agility: 1_000),
            enemySkillIds: [barrierAccessSkill.id],
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 100,
                attackSpell: 0
            ),
            enemyActionPriority: [.recoverySpell, .attack, .attackSpell, .breath]
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [attackSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: casterStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [BattleEnemySeed(enemyId: 1, level: 1)],
            masterData: masterData
        )

        let enemyStatus = try #require(
            CharacterDerivedStatsCalculator.status(
                baseStats: battleCharacterBaseStats(vitality: 100, agility: 1_000),
                jobId: 1,
                level: 1,
                skillIds: [barrierAccessSkill.id],
                masterData: masterData
            )
        )
        let firstTurn = try #require(result.battleRecord.turns.first)
        let firstAction = try #require(firstTurn.actions.first)
        let secondAction = try #require(firstTurn.actions.last)
        let expectedDamage = max(
            Int(
                (
                    Double(max(casterStatus.battleStats.magic - enemyStatus.battleStats.magicDefense, 0))
                    * 0.5
                ).rounded()
            ),
            1
        )

        #expect(firstAction.actorId == BattleCombatantID(rawValue: 1))
        #expect(firstAction.actionKind == .recoverySpell)
        #expect(secondAction.actorId == BattleCombatantID(rawValue: 1 - 1))
        #expect(secondAction.actionKind == .attackSpell)
        #expect(secondAction.results.first?.value == expectedDamage)
    }

    @Test
    func nuclearSpellTargetsAllLivingCombatants() throws {
        let nuclearSpell = MasterData.Spell(
            id: 1,
            name: "核攻撃",
            category: .attack,
            kind: .damage,
            targetSide: .both,
            targetCount: 0,
            multiplier: 1.0
        )
        let masterData = makeBattleTestMasterData(
            spells: [nuclearSpell],
            enemyBaseStats: battleBaseStats(vitality: 100),
            enemyActionRates: MasterData.ActionRates(
                breath: 0,
                attack: 0,
                recoverySpell: 0,
                attackSpell: 0
            )
        )
        let casterStatus = makeBattleTestStatus(
            baseStats: battleCharacterBaseStats(agility: 1_000),
            battleStats: CharacterBattleStats(
                maxHP: 100,
                physicalAttack: 0,
                physicalDefense: 0,
                magic: 20,
                magicDefense: 0,
                healing: 0,
                accuracy: 0,
                evasion: 0,
                attackCount: 1,
                criticalRate: 0,
                breathPower: 0
            ),
            spellIds: [nuclearSpell.id]
        )

        let result = try SingleBattleResolver.resolve(
            context: BattleContext(
                runId: RunSessionID(partyId: 1, partyRunId: 1),
                rootSeed: 0,
                floorNumber: 1,
                battleNumber: 1
            ),
            partyMembers: [
                makePartyBattleMember(
                    id: 1,
                    name: "魔導士",
                    status: casterStatus,
                    autoBattleSettings: makeAutoBattleSettings(
                        breath: 0,
                        attack: 0,
                        recoverySpell: 0,
                        attackSpell: 100,
                        priority: [.attackSpell, .attack, .recoverySpell, .breath]
                    )
                )
            ],
            enemies: [
                BattleEnemySeed(enemyId: 1, level: 1),
                BattleEnemySeed(enemyId: 1, level: 1)
            ],
            masterData: masterData
        )

        let firstAction = try #require(result.battleRecord.turns.first?.actions.first)

        #expect(firstAction.actionKind == .attackSpell)
        #expect(Set(firstAction.targetIds) == Set([
            BattleCombatantID(rawValue: 1 - 1),
            BattleCombatantID(rawValue: 1),
            BattleCombatantID(rawValue: 2)
        ]))
    }

}
