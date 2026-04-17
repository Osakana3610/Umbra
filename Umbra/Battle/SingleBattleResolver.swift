// Resolves one deterministic battle and emits a complete battle log without persistence.

import Foundation

nonisolated struct PartyBattleMember: Sendable {
    let character: CharacterRecord
    let status: CharacterStatus
}

nonisolated enum SingleBattleResolver {
    static func resolve(
        context: BattleContext,
        partyMembers: [PartyBattleMember],
        enemies: [BattleEnemySeed],
        masterData: MasterData
    ) throws -> SingleBattleResult {
        var resolver = try BattleResolutionEngine(
            context: context,
            partyMembers: partyMembers,
            enemies: enemies,
            masterData: masterData
        )
        return try resolver.resolve()
    }
}

nonisolated struct BattleActionOrderPriorityKey: Equatable, Sendable {
    let initiativeScore: Double
    let luck: Int
    let agility: Int
    let formationIndex: Int

    static func ordersBefore(_ lhs: BattleActionOrderPriorityKey, _ rhs: BattleActionOrderPriorityKey) -> Bool {
        if lhs.initiativeScore != rhs.initiativeScore {
            return lhs.initiativeScore > rhs.initiativeScore
        }
        if lhs.luck != rhs.luck {
            return lhs.luck > rhs.luck
        }
        if lhs.agility != rhs.agility {
            return lhs.agility > rhs.agility
        }
        return lhs.formationIndex < rhs.formationIndex
    }
}

nonisolated enum RescueResolutionValidation {
    static func survivingDefeatedTargetIndices(
        from fallenTargetIndices: [Int]?,
        aliveStates: [Bool],
        actorCanAct: Bool
    ) -> [Int]? {
        guard let fallenTargetIndices else {
            return nil
        }

        let stillDefeatedTargets = fallenTargetIndices.filter { targetIndex in
            aliveStates.indices.contains(targetIndex) && !aliveStates[targetIndex]
        }
        guard !stillDefeatedTargets.isEmpty, actorCanAct else {
            return nil
        }
        return stillDefeatedTargets
    }
}

nonisolated private struct BattleResolutionEngine {
    private let context: BattleContext
    private let masterData: MasterData
    private let spellLookup: [Int: MasterData.Spell]
    private let skillLookup: [Int: MasterData.Skill]
    private var combatants: [RuntimeCombatant]
    private var turns: [BattleTurnRecord] = []
    private var currentTurn = 0
    private var currentActionNumber = 0
    private var initiativeScores: [Double]
    private var livingCombatantIndices: [Int]
    private var livingAllyIndices: [Int]
    private var livingEnemyIndices: [Int]
    private var livingAllyFrontIndices: [Int]
    private var livingAllyMiddleIndices: [Int]
    private var livingAllyBackIndices: [Int]
    private var livingEnemyFrontIndices: [Int]
    private var livingEnemyMiddleIndices: [Int]
    private var livingEnemyBackIndices: [Int]
    private var allyPartyModifiersByTarget: [String: Double]
    private var enemyPartyModifiersByTarget: [String: Double]

    init(
        context: BattleContext,
        partyMembers: [PartyBattleMember],
        enemies: [BattleEnemySeed],
        masterData: MasterData
    ) throws {
        guard !partyMembers.isEmpty else {
            throw SingleBattleError.emptyParty
        }

        self.context = context
        self.masterData = masterData
        self.spellLookup = Dictionary(uniqueKeysWithValues: masterData.spells.map { ($0.id, $0) })
        self.skillLookup = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        self.combatants = []
        self.initiativeScores = []
        self.livingCombatantIndices = []
        self.livingAllyIndices = []
        self.livingEnemyIndices = []
        self.livingAllyFrontIndices = []
        self.livingAllyMiddleIndices = []
        self.livingAllyBackIndices = []
        self.livingEnemyFrontIndices = []
        self.livingEnemyMiddleIndices = []
        self.livingEnemyBackIndices = []
        self.allyPartyModifiersByTarget = [:]
        self.enemyPartyModifiersByTarget = [:]
        let enemyDisplayNames = Self.makeEnemyDisplayNames(enemies: enemies, masterData: masterData)

        for (formationIndex, character) in partyMembers.enumerated() {
            combatants.append(
                RuntimeCombatant(
                    id: BattleCombatantID(rawValue: "character:\(character.character.characterId)"),
                    name: character.character.name,
                    side: .ally,
                    imageAssetID: masterData.portraitAssetName(for: character.character),
                    level: character.character.level,
                    formationIndex: formationIndex,
                    currentHP: min(max(character.character.currentHP, 0), character.status.maxHP),
                    status: character.status,
                    actionRates: character.character.autoBattleSettings.rates,
                    actionPriority: character.character.autoBattleSettings.priority
                )
            )
        }

        for ((formationIndex, enemySeed), enemyDisplayName) in zip(enemies.enumerated(), enemyDisplayNames) {
            guard let enemy = masterData.enemies.first(where: { $0.id == enemySeed.enemyId }) else {
                throw SingleBattleError.invalidEnemy(enemySeed.enemyId)
            }

            guard let status = CharacterDerivedStatsCalculator.status(
                for: enemy,
                level: enemySeed.level,
                masterData: masterData
            ) else {
                throw SingleBattleError.invalidEnemy(enemy.id)
            }

            combatants.append(
                RuntimeCombatant(
                    id: BattleCombatantID(rawValue: "enemy:\(enemy.id):\(formationIndex + 1)"),
                    name: enemyDisplayName,
                    side: .enemy,
                    imageAssetID: enemy.imageAssetName,
                    level: enemySeed.level,
                    formationIndex: formationIndex,
                    currentHP: status.maxHP,
                    status: status,
                    actionRates: CharacterActionRates(
                        breath: enemy.actionRates.breath,
                        attack: enemy.actionRates.attack,
                        recoverySpell: enemy.actionRates.recoverySpell,
                        attackSpell: enemy.actionRates.attackSpell
                    ),
                    actionPriority: enemy.actionPriority
                )
            )
        }

        self.initiativeScores = Array(repeating: 0, count: combatants.count)
        refreshBattlefieldCaches()
    }

    private mutating func refreshBattlefieldCaches() {
        var livingCombatantIndices: [Int] = []
        var livingAllyIndices: [Int] = []
        var livingEnemyIndices: [Int] = []
        var livingAllyFrontIndices: [Int] = []
        var livingAllyMiddleIndices: [Int] = []
        var livingAllyBackIndices: [Int] = []
        var livingEnemyFrontIndices: [Int] = []
        var livingEnemyMiddleIndices: [Int] = []
        var livingEnemyBackIndices: [Int] = []
        var activeAllySkillIds = Set<Int>()
        var activeEnemySkillIds = Set<Int>()

        for combatantIndex in combatants.indices where combatants[combatantIndex].isAlive {
            let combatant = combatants[combatantIndex]
            livingCombatantIndices.append(combatantIndex)

            switch combatant.side {
            case .ally:
                livingAllyIndices.append(combatantIndex)
                activeAllySkillIds.formUnion(combatant.status.skillIds)
                switch formationRank(for: combatant.formationIndex) {
                case .front:
                    livingAllyFrontIndices.append(combatantIndex)
                case .middle:
                    livingAllyMiddleIndices.append(combatantIndex)
                case .back:
                    livingAllyBackIndices.append(combatantIndex)
                }
            case .enemy:
                livingEnemyIndices.append(combatantIndex)
                activeEnemySkillIds.formUnion(combatant.status.skillIds)
                switch formationRank(for: combatant.formationIndex) {
                case .front:
                    livingEnemyFrontIndices.append(combatantIndex)
                case .middle:
                    livingEnemyMiddleIndices.append(combatantIndex)
                case .back:
                    livingEnemyBackIndices.append(combatantIndex)
                }
            }
        }

        self.livingCombatantIndices = livingCombatantIndices
        self.livingAllyIndices = livingAllyIndices
        self.livingEnemyIndices = livingEnemyIndices
        self.livingAllyFrontIndices = livingAllyFrontIndices
        self.livingAllyMiddleIndices = livingAllyMiddleIndices
        self.livingAllyBackIndices = livingAllyBackIndices
        self.livingEnemyFrontIndices = livingEnemyFrontIndices
        self.livingEnemyMiddleIndices = livingEnemyMiddleIndices
        self.livingEnemyBackIndices = livingEnemyBackIndices
        self.allyPartyModifiersByTarget = partyModifiers(for: activeAllySkillIds)
        self.enemyPartyModifiersByTarget = partyModifiers(for: activeEnemySkillIds)
    }

    private func partyModifiers(for activeSkillIds: Set<Int>) -> [String: Double] {
        var pctAddsByTarget: [String: Double] = [:]
        var multipliersByTarget: [String: Double] = [:]

        for skillId in activeSkillIds {
            guard let skill = skillLookup[skillId] else {
                continue
            }

            for effect in skill.effects {
                guard effect.kind == .partyModifier,
                      let target = effect.target,
                      let value = effect.value else {
                    continue
                }

                switch effect.operation {
                case "pctAdd":
                    pctAddsByTarget[target, default: 0.0] += value
                case "mul", nil:
                    multipliersByTarget[target, default: 1.0] *= value
                default:
                    continue
                }
            }
        }

        var resolved: [String: Double] = [:]
        let targets = Set(pctAddsByTarget.keys).union(multipliersByTarget.keys)
        for target in targets {
            resolved[target] = max(
                (1.0 + pctAddsByTarget[target, default: 0.0]) * multipliersByTarget[target, default: 1.0],
                0.0
            )
        }
        return resolved
    }

    private mutating func setCurrentHP(
        for targetIndex: Int,
        to newValue: Int
    ) {
        let wasAlive = combatants[targetIndex].isAlive
        combatants[targetIndex].currentHP = newValue
        if wasAlive != combatants[targetIndex].isAlive {
            refreshBattlefieldCaches()
        }
    }

    private static func makeEnemyDisplayNames(
        enemies: [BattleEnemySeed],
        masterData: MasterData
    ) -> [String] {
        let names = enemies.map { enemySeed in
            masterData.enemies.first(where: { $0.id == enemySeed.enemyId })?.name ?? ""
        }
        let totalCounts = names.reduce(into: [:]) { counts, name in
            counts[name, default: 0] += 1
        }
        var seenCounts: [String: Int] = [:]

        return names.map { name in
            guard totalCounts[name, default: 0] > 1 else {
                return name
            }

            let nextCount = seenCounts[name, default: 0] + 1
            seenCounts[name] = nextCount
            return "\(name)\(alphabeticSuffix(for: nextCount))"
        }
    }

    private static func alphabeticSuffix(for index: Int) -> String {
        precondition(index > 0)

        var value = index
        var suffix = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            suffix = "\(Character(UnicodeScalar(65 + remainder)!))" + suffix
            value = (value - 1) / 26
        }
        return suffix
    }

    mutating func resolve() throws -> SingleBattleResult {
        var outcome = currentOutcomeIfFinished()

        // A battle is resolved turn-by-turn, but interrupts can still prepend extra actions
        // inside the current turn before the next initiative pass begins.
        while outcome == nil && currentTurn < 20 {
            currentTurn += 1
            resetTurnState()
            applyStartOfTurnEffects()
            outcome = currentOutcomeIfFinished()
            guard outcome == nil else {
                turns.append(BattleTurnRecord(turnNumber: currentTurn, actions: []))
                break
            }

            let turnActions = buildTurnActions()
            var actionQueue = turnActions
            var resolvedActions: [BattleActionRecord] = []

            while !actionQueue.isEmpty {
                let queuedAction = actionQueue.removeFirst()
                currentActionNumber += 1
                guard combatants[queuedAction.actorIndex].canAct else {
                    continue
                }

                if let actionRecord = resolve(queuedAction) {
                    resolvedActions.append(actionRecord.record)
                    if queuedAction.countsAsNormalTurnAction,
                       currentTurn == 1,
                       combatants[queuedAction.actorIndex].canAct,
                       !combatants[queuedAction.actorIndex].hasUsedTurnOneExtraAction,
                       combatants[queuedAction.actorIndex].status.actionRuleMaxValue(
                        for: "extraTurnAfterNormalActionOnTurnOne"
                       ) != nil {
                        combatants[queuedAction.actorIndex].hasUsedTurnOneExtraAction = true
                        actionQueue.insert(selectNormalAction(for: queuedAction.actorIndex), at: 0)
                    }
                    if !actionRecord.generatedInterrupts.isEmpty {
                        // Interrupts are inserted at the head of the queue so they resolve
                        // immediately after the triggering action, matching the battle log order.
                        let sortedInterrupts = sortInterrupts(actionRecord.generatedInterrupts)
                        actionQueue.insert(contentsOf: sortedInterrupts, at: 0)
                    }
                }

                if let immediateOutcome = currentOutcomeIfFinished() {
                    outcome = immediateOutcome
                    actionQueue.removeAll()
                }
            }

            if outcome == nil {
                // Damage-over-time and similar ailment ticks only happen if the battle did not
                // already end from a normal action during this turn.
                resolveEndOfTurnAilments()
            }
            turns.append(BattleTurnRecord(turnNumber: currentTurn, actions: resolvedActions))
            outcome = outcome ?? currentOutcomeIfFinished()
        }

        let finalOutcome = outcome ?? .draw
        if finalOutcome == .victory {
            for index in combatants.indices
            where combatants[index].isAlive
                && combatants[index].status.recoveryRuleMaxValue(for: "healToFullAfterBattle") != nil {
                setCurrentHP(for: index, to: combatants[index].status.maxHP)
            }
        }
        let battleRecord = BattleRecord(
            runId: context.runId,
            floorNumber: context.floorNumber,
            battleNumber: context.battleNumber,
            result: finalOutcome,
            turns: turns
        )

        return SingleBattleResult(
            context: context,
            battleRecord: battleRecord,
            combatants: combatants.map { combatant in
                BattleCombatantSnapshot(
                    id: combatant.id,
                    name: combatant.name,
                    side: combatant.side,
                    imageAssetID: combatant.imageAssetID,
                    level: combatant.level,
                    initialHP: combatant.initialHP,
                    maxHP: combatant.status.maxHP,
                    remainingHP: combatant.currentHP,
                    formationIndex: combatant.formationIndex
                )
            }
        )
    }

    private mutating func resetTurnState() {
        for index in combatants.indices {
            combatants[index].isDefending = false
            // Initiative is recomputed every turn from the current runtime state so speed buffs,
            // ailments, and deaths immediately affect ordering.
            initiativeScores[index] = combatants[index].canAct ? actionOrderScore(for: index) : .leastNonzeroMagnitude
        }
    }

    private mutating func applyStartOfTurnEffects() {
        for index in combatants.indices where combatants[index].isAlive {
            guard let lossRatio = combatants[index].status.combatRuleMaxValue(for: "startTurnSelfCurrentHPLossPct"),
                  lossRatio > 0 else {
                continue
            }
            let damage = max(Int(ceil(Double(combatants[index].currentHP) * lossRatio)), 1)
            _ = applyDamage(
                damage,
                to: index,
                guarded: false,
                purposeSubaction: 0
            )
        }
    }

    private mutating func buildTurnActions() -> [QueuedAction] {
        let actingIndices = combatants.indices.filter { combatants[$0].canAct }
        let orderedIndices = actingIndices.sorted(by: compareCombatantPriority)
        return orderedIndices.map { selectNormalAction(for: $0) }
    }

    private mutating func selectNormalAction(for actorIndex: Int) -> QueuedAction {
        let actor = combatants[actorIndex]

        // Priorities are evaluated in order, but each candidate still rolls against the actor's
        // configured auto-battle rate before it becomes the committed action for the turn.
        for (priorityIndex, actionKind) in actor.actionPriority.enumerated() {
            guard isCandidateExecutable(actionKind, for: actorIndex) else {
                continue
            }

            let probability = probability(for: actionKind, rates: actor.actionRates)
            let roll = uniform(
                turn: currentTurn,
                action: 0,
                subaction: priorityIndex + 1,
                roll: actorIndex + 1,
                purpose: "normalActionRate.\(actor.id.rawValue).\(actionKind.rawValue)"
            )
            guard roll < probability else {
                continue
            }

            switch actionKind {
            case .breath:
                return QueuedAction(actorIndex: actorIndex, recordKind: .breath, countsAsNormalTurnAction: true)
            case .attack:
                return QueuedAction(actorIndex: actorIndex, recordKind: .attack, countsAsNormalTurnAction: true)
            case .recoverySpell:
                if let spellId = selectSpell(
                    for: actorIndex,
                    category: .recovery,
                    purposePrefix: "normalRecoverySpell"
                ) {
                    return QueuedAction(
                        actorIndex: actorIndex,
                        recordKind: .recoverySpell,
                        spellId: spellId,
                        countsAsNormalTurnAction: true
                    )
                }
            case .attackSpell:
                if let spellId = selectSpell(
                    for: actorIndex,
                    category: .attack,
                    purposePrefix: "normalAttackSpell"
                ) {
                    return QueuedAction(
                        actorIndex: actorIndex,
                        recordKind: .attackSpell,
                        spellId: spellId,
                        countsAsNormalTurnAction: true
                    )
                }
            }
        }

        return QueuedAction(actorIndex: actorIndex, recordKind: .defend, countsAsNormalTurnAction: true)
    }

    private mutating func resolve(_ queuedAction: QueuedAction) -> ResolvedAction? {
        switch queuedAction.recordKind {
        case .defend:
            combatants[queuedAction.actorIndex].isDefending = true
            let actorIndex = queuedAction.actorIndex
            var results: [BattleTargetResult] = []
            if let healMultiplier = combatants[actorIndex].status.recoveryRuleMaxValue(for: "defendPartyHealMultiplier") {
                let healAmount = max(
                    Int(
                        (
                            Double(combatants[actorIndex].status.battleStats.healing)
                            * combatants[actorIndex].status.battleDerivedStats.healingMultiplier
                            * actionMultiplier(for: actorIndex, actionKind: .recoverySpell)
                            * livePartyModifier(
                                for: combatants[actorIndex].side,
                                target: "allyHealingMultiplier"
                            )
                            * healMultiplier
                        ).rounded()
                    ),
                    1
                )
                for targetIndex in livingIndices(on: combatants[actorIndex].side) {
                    results.append(applyHeal(healAmount, to: targetIndex))
                }
            }
            if let cleanseCount = combatants[actorIndex].status.recoveryRuleMaxValue(for: "defendPartyCleanseCount") {
                for targetIndex in livingIndices(on: combatants[actorIndex].side) {
                    var remaining = Int(cleanseCount.rounded())
                    while remaining > 0, let ailment = removeAilment(from: targetIndex, actionNumber: currentActionNumber) {
                        results.append(
                            BattleTargetResult(
                                targetId: combatants[targetIndex].id,
                                resultKind: .ailmentRemoved,
                                value: nil,
                                statusId: ailment.rawValue,
                                flags: []
                            )
                        )
                        remaining -= 1
                    }
                }
            }
            if combatants[actorIndex].status.reviveRuleMaxValue(for: "defendReviveOneAlly") != nil {
                let fallenAllies = combatants.indices.filter {
                    combatants[$0].side == combatants[actorIndex].side && !combatants[$0].isAlive
                }
                if let reviveTargetIndex = randomChoice(
                    from: fallenAllies,
                    turn: currentTurn,
                    action: currentActionNumber,
                    subaction: 1,
                    purpose: "defend.revive.\(combatants[actorIndex].id.rawValue)"
                ) {
                    let recoveredHP = max(
                        Int(
                            (
                                Double(combatants[actorIndex].status.battleStats.healing)
                                * combatants[actorIndex].status.battleDerivedStats.healingMultiplier
                                * livePartyModifier(
                                    for: combatants[actorIndex].side,
                                    target: "allyHealingMultiplier"
                                )
                            ).rounded()
                        ),
                        1
                    )
                    results.append(reviveTarget(reviveTargetIndex, recoveredHP: recoveredHP, fullRestore: false))
                }
            }
            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: combatants[actorIndex].id,
                    actionKind: .defend,
                    actionRef: nil,
                    actionFlags: [],
                    targetIds: results.map(\.targetId),
                    results: results
                ),
                generatedInterrupts: []
            )
        case .breath:
            return resolveBreath(queuedAction)
        case .attack:
            return resolveAttack(queuedAction)
        case .unarmedRepeat:
            return resolveAttack(queuedAction)
        case .recoverySpell:
            return resolveRecoverySpell(queuedAction)
        case .attackSpell:
            return resolveAttackSpell(queuedAction)
        case .rescue:
            return resolveRescue(queuedAction)
        case .counter, .extraAttack, .pursuit:
            return resolveAttack(queuedAction)
        }
    }

    private mutating func resolveBreath(_ queuedAction: QueuedAction) -> ResolvedAction? {
        let targetIndices = livingIndices(on: opposingSide(of: combatants[queuedAction.actorIndex].side))
        guard !targetIndices.isEmpty else {
            return nil
        }
        // Breath is a once-per-battle action even if later action selection would otherwise pick
        // it again.
        guard combatants[queuedAction.actorIndex].breathUsesRemaining > 0 else {
            return nil
        }

        combatants[queuedAction.actorIndex].breathUsesRemaining -= 1

        let actor = combatants[queuedAction.actorIndex]
        var results: [BattleTargetResult] = []
        var fallenTargetIndices: [Int] = []
        for (subactionNumber, targetIndex) in targetIndices.enumerated() {
            let guarded = combatants[targetIndex].isDefending
            let damage = damageValue(
                actorIndex: queuedAction.actorIndex,
                basePower: Double(
                    max(
                        actor.status.battleStats.breathPower
                            - combatants[targetIndex].status.battleStats.physicalDefense,
                        0
                    )
                ),
                multiplier: 1.0,
                resistance: combatants[targetIndex].status.battleDerivedStats.breathResistanceMultiplier,
                barrierMultiplier: 1.0,
                guarded: guarded,
                subactionNumber: subactionNumber + 1,
                allowsHitSpecialRules: false
            )
            let targetResult = applyDamage(
                damage,
                to: targetIndex,
                guarded: guarded,
                purposeSubaction: subactionNumber + 1
            )
            results.append(targetResult)
            if targetResult.flags.contains(.defeated) {
                fallenTargetIndices.append(targetIndex)
            }
        }

        var generatedInterrupts = rescueInterruptActions(
            after: queuedAction,
            fallenTargetIndices: fallenTargetIndices
        )
        if combatants[queuedAction.actorIndex].status.actionRuleMaxValue(for: "normalAttackAfterBreath") != nil,
           let followUp = makeFollowUpAttack(actorIndex: queuedAction.actorIndex) {
            generatedInterrupts.append(followUp)
        }

        return ResolvedAction(
            record: BattleActionRecord(
                actorId: actor.id,
                actionKind: .breath,
                actionRef: nil,
                actionFlags: [],
                targetIds: targetIndices.map { combatants[$0].id },
                results: results
            ),
            generatedInterrupts: generatedInterrupts
        )
    }

    private mutating func resolveAttack(_ queuedAction: QueuedAction) -> ResolvedAction? {
        let actorIndex = queuedAction.actorIndex
        let actor = combatants[actorIndex]
        let actionKind = queuedAction.recordKind
        let isNormalAttack = isNormalAttackAction(actionKind)
        let selectedTargetIndices = attackTargetIndices(for: queuedAction)
        guard !selectedTargetIndices.isEmpty else {
            return nil
        }

        let primaryTargetIndex = selectedTargetIndices[0]
        let attackCount = adjustedAttackCount(for: actorIndex, multiplier: queuedAction.attackCountMultiplier)
        let allowsCritical = queuedAction.criticalAllowed
        let isFirstNormalAttack = isNormalAttack && !combatants[actorIndex].hasUsedFirstNormalAttack
        let firstAttackAccuracyPctAdd = isFirstNormalAttack
            ? (combatants[actorIndex].status.actionRuleMaxValue(for: "firstNormalAttackAccuracyPctAdd") ?? 0.0)
            : 0.0
        let criticalRateBonus = max(
            (isNormalAttack ? (combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackCriticalRateAdd") ?? 0.0) : 0.0)
                +
            (attackCount == 1 ? (combatants[actorIndex].status.actionRuleMaxValue(for: "attackCountOneCriticalRateAdd") ?? 0.0) : 0.0)
                + (isLowHP(combatants[actorIndex]) ? (combatants[actorIndex].status.combatRuleMaxValue(for: "lowHPCriticalRateAdd") ?? 0.0) : 0.0)
                + (isLowHP(combatants[primaryTargetIndex]) ? (combatants[actorIndex].status.combatRuleMaxValue(for: "criticalRateAgainstLowHPTargetAdd") ?? 0.0) : 0.0),
            0.0
        )
        let criticalTriggered = allowsCritical
            ? criticalDidTrigger(for: actorIndex, criticalRateBonus: criticalRateBonus)
            : false
        let usesCarryOver = isNormalAttack
            && combatants[actorIndex].status.actionRuleMaxValue(for: "carryOverRemainingHitsOnKill") != nil
        let sharesAttackCountAcrossTargets = usesCarryOver

        if selectedTargetIndices.count > 1 || usesCarryOver {
            var pendingTargetIndices = selectedTargetIndices
            var processedTargetIndices = Set(selectedTargetIndices)
            var remainingHitIndices = Array(0..<attackCount)
            var results: [BattleTargetResult] = []
            var targetIds: [BattleCombatantID] = []
            var fallenTargetIndices: [Int] = []
            var generatedInterrupts: [QueuedAction] = []
            var landedAnyHit = false

            while !pendingTargetIndices.isEmpty
                && (sharesAttackCountAcrossTargets ? !remainingHitIndices.isEmpty : true) {
                let originalTargetIndex = pendingTargetIndices.removeFirst()
                guard combatants.indices.contains(originalTargetIndex),
                      combatants[originalTargetIndex].isAlive else {
                    continue
                }

                let guardedTarget = redirectedPhysicalTarget(
                    originalTargetIndex: originalTargetIndex,
                    attackerIndex: actorIndex
                )
                let targetIndex = guardedTarget.targetIndex
                let targetId = combatants[targetIndex].id
                let targetWasLowHP = isLowHP(combatants[targetIndex])
                let guarded = combatants[targetIndex].isDefending
                var totalDamage = 0
                var combinedFlags: Set<BattleTargetResultFlag> = []
                var landedHitOnTarget = false
                let isPrimaryTarget = originalTargetIndex == primaryTargetIndex
                var hitIndices = sharesAttackCountAcrossTargets
                    ? remainingHitIndices
                    : Array(0..<attackCount)

                while !hitIndices.isEmpty && combatants[targetIndex].isAlive {
                    let hitIndex = hitIndices.removeFirst()
                    guard didHit(
                        attackerIndex: actorIndex,
                        defenderIndex: targetIndex,
                        subactionNumber: hitIndex + 1,
                        isNormalAttack: isNormalAttack,
                        accuracyPctAdd: firstAttackAccuracyPctAdd
                    ) else {
                        continue
                    }

                    landedHitOnTarget = true
                    landedAnyHit = true
                    var multiplier = actor.status.battleDerivedStats.physicalDamageMultiplier
                    multiplier *= formationMultiplier(for: actor)
                    multiplier *= weaponDamageMultiplier(for: actor)
                    multiplier *= queuedAction.attackPowerMultiplier
                    multiplier *= livePartyModifier(
                        for: actor.side,
                        target: "allyPhysicalDamageMultiplier"
                    )
                    if actor.attackBuffActive {
                        multiplier *= 1.5
                    }
                    if criticalTriggered {
                        multiplier *= actor.status.battleDerivedStats.criticalDamageMultiplier
                        if isNormalAttack, formationRank(for: actor.formationIndex) == .back {
                            multiplier *= combatants[actorIndex].status.actionRuleMaxValue(
                                for: "backRowNormalAttackCriticalDamageMultiplier"
                            ) ?? 1.0
                        }
                    }
                    if isNormalAttack {
                        multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackBaseDamageMultiplier") ?? 1.0
                        if combatants[actorIndex].status.hasMeleeWeapon || combatants[actorIndex].status.isUnarmed {
                            multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackMeleeDamageMultiplier") ?? 1.0
                        }
                        if combatants[actorIndex].status.hasRangedWeapon {
                            multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackRangedDamageMultiplier") ?? 1.0
                        }
                        if isFirstNormalAttack {
                            multiplier *= combatants[actorIndex].status.actionRuleMaxValue(
                                for: "firstNormalAttackPhysicalDamageMultiplier"
                            ) ?? 1.0
                        }
                        multiplier *= combatants[actorIndex].nextNormalAttackPhysicalDamageMultiplier
                    }
                    if attackCount == 1 {
                        multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "attackCountOneMeleeDamageMultiplier") ?? 1.0
                        if criticalTriggered {
                            multiplier *= combatants[actorIndex].status.actionRuleMaxValue(
                                for: "attackCountOneCriticalDamageMultiplier"
                            ) ?? 1.0
                        }
                    }
                    if isLowHP(combatants[actorIndex]) {
                        multiplier *= combatants[actorIndex].status.combatRuleMaxValue(for: "lowHPPhysicalDamageMultiplier") ?? 1.0
                        multiplier *= combatants[actorIndex].status.combatRuleMaxValue(for: "lowHPMeleeDamageMultiplier") ?? 1.0
                    }
                    if isLowHP(combatants[targetIndex]) {
                        multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                            for: "criticalDamageMultiplierAgainstLowHPTarget"
                        ) ?? 1.0
                        multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                            for: "lowHPTargetRangedDamageMultiplier"
                        ) ?? 1.0
                    }
                    if !combatants[targetIndex].ailments.isEmpty {
                        multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                            for: "damageMultiplierAgainstAilingTarget"
                        ) ?? 1.0
                    }
                    if combatants[targetIndex].ailments.contains(.petrify) {
                        multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                            for: "damageMultiplierAgainstPetrifiedTarget"
                        ) ?? 1.0
                    }
                    multiplier *= 1.0 + max(combatants[actorIndex].physicalDamagePctAddFromDamageTaken, 0.0)
                    let lostHPTens = max(actor.status.maxHP - combatants[actorIndex].currentHP, 0) / max(actor.status.maxHP / 10, 1)
                    let lostHPPctAdd = Double(lostHPTens) * (combatants[actorIndex].status.combatRuleMaxValue(
                        for: "lostHP10PctToMeleeDamagePctAdd"
                    ) ?? 0.0)
                    multiplier *= 1.0 + lostHPPctAdd
                    let elapsedTurnPctAdd = Double(max(currentTurn - 1, 0)) * (combatants[actorIndex].status.combatRuleMaxValue(
                        for: "elapsedTurnToPhysicalAttackPctAdd"
                    ) ?? 0.0)
                    multiplier *= 1.0 + elapsedTurnPctAdd
                    multiplier *= actionMultiplier(for: actorIndex, actionKind: actionKind)
                    if isNormalAttack {
                        multiplier *= normalAttackAdditionalTargetDamageMultiplier(
                            for: actorIndex,
                            isPrimaryTarget: isPrimaryTarget
                        )
                    }

                    breakPhysicalBarrierOnNormalHitIfNeeded(
                        attackerIndex: actorIndex,
                        targetIndex: targetIndex,
                        isNormalAttack: isNormalAttack
                    )
                    let barrierMultiplier = combatants[targetIndex].physicalBarrierActive ? 0.5 : 1.0
                    let defendDamageTakenMultiplier = guarded
                        ? combatants[targetIndex].status.defenseRuleProduct(for: "defendDamageTakenMultiplier")
                        : 1.0
                    let guardedDamageTakenMultiplier = guardedTarget.didRedirect
                        ? combatants[targetIndex].status.defenseRuleProduct(for: "guardedDamageTakenMultiplier")
                        : 1.0
                    let partyDamageTakenMultiplier = livePartyModifier(
                        for: combatants[targetIndex].side,
                        target: "allyPhysicalDamageTakenMultiplier"
                    )
                    let basePower = physicalBasePower(
                        attackerIndex: actorIndex,
                        targetIndex: targetIndex,
                        hitMultiplier: hitContribution(
                            for: hitIndex,
                            attackerIndex: actorIndex,
                            isNormalAttack: isNormalAttack
                        ),
                        isNormalAttack: isNormalAttack
                    )
                    let damage = damageValue(
                        actorIndex: actorIndex,
                        basePower: basePower,
                        multiplier: multiplier,
                        resistance: combatants[targetIndex].status.battleDerivedStats.physicalResistanceMultiplier
                            * (isLowHP(combatants[targetIndex])
                                ? (combatants[targetIndex].status.combatRuleMaxValue(for: "lowHPPhysicalResistanceMultiplier") ?? 1.0)
                                : 1.0)
                            * partyDamageTakenMultiplier
                            * guardedDamageTakenMultiplier
                            * defendDamageTakenMultiplier,
                        barrierMultiplier: barrierMultiplier,
                        guarded: guarded,
                        subactionNumber: hitIndex + 1,
                        allowsHitSpecialRules: actionKind == .attack
                    )
                    let damageResult = applyDamage(
                        damage,
                        to: targetIndex,
                        guarded: guarded,
                        purposeSubaction: hitIndex + 1
                    )
                    totalDamage += damageResult.value ?? 0
                    combinedFlags.formUnion(damageResult.flags)
                }
                if sharesAttackCountAcrossTargets {
                    remainingHitIndices = hitIndices
                }

                targetIds.append(targetId)

                if !landedHitOnTarget {
                    results.append(
                        BattleTargetResult(
                            targetId: targetId,
                            resultKind: .miss,
                            value: nil,
                            statusId: nil,
                            flags: []
                        )
                    )
                    if queuedAction.canTriggerInterrupts {
                        generatedInterrupts += interruptActions(
                            after: queuedAction,
                            targetIndex: targetIndex,
                            targetWasDefeated: false
                        )
                    }
                    continue
                }

                let targetResult = BattleTargetResult(
                    targetId: targetId,
                    resultKind: .damage,
                    value: totalDamage,
                    statusId: nil,
                    flags: combinedFlags.sorted(by: { $0.rawValue < $1.rawValue })
                )
                results.append(targetResult)
                if isNormalAttack {
                    combatants[actorIndex].hasUsedFirstNormalAttack = true
                    combatants[actorIndex].nextNormalAttackPhysicalDamageMultiplier = 1.0
                }
                if let lifestealMultiplier = combatants[actorIndex].status.recoveryRuleMaxValue(for: "lifestealMultiplier"),
                   totalDamage > 0 {
                    results.append(
                        applyHeal(
                            max(Int((Double(totalDamage) * lifestealMultiplier).rounded()), 1),
                            to: actorIndex
                        )
                    )
                }
                results.append(contentsOf: applyOnHitAilments(
                    from: actorIndex,
                    to: targetIndex,
                    subactionNumber: 1,
                    includesAttackSpellTriggers: false,
                    includesNormalAttackTriggers: isNormalAttack
                ))
                if isNormalAttack,
                   combatants[actorIndex].status.actionRuleMaxValue(for: "restoreRandomAttackSpellUsageOnNormalHit") != nil {
                    restoreOneAttackSpellCharge(for: actorIndex)
                }
                if targetResult.flags.contains(.defeated) {
                    fallenTargetIndices.append(targetIndex)
                    if targetWasLowHP {
                        if let healRatio = combatants[actorIndex].status.recoveryRuleMaxValue(for: "healOnLowHPKillHPRatio") {
                            results.append(
                                applyHeal(
                                    max(Int((Double(combatants[actorIndex].status.maxHP) * healRatio).rounded()), 1),
                                    to: actorIndex
                                )
                            )
                        }
                        if queuedAction.allowsActionRuleFollowUps, isNormalAttack {
                            if combatants[actorIndex].status.actionRuleMaxValue(for: "extraActionOnLowHPKill") != nil,
                               combatants[actorIndex].canAct {
                                generatedInterrupts.append(selectNormalAction(for: actorIndex).asFollowUp())
                            }
                            if combatants[actorIndex].status.actionRuleMaxValue(for: "chainNormalAttackOnLowHPKill") != nil,
                               let nextTargetIndex = selectLowHPTarget(
                                for: combatants[actorIndex].side,
                                excluding: [targetIndex]
                               ),
                               let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: nextTargetIndex) {
                                generatedInterrupts.append(followUp)
                            }
                        }
                    }
                    if usesCarryOver && remainingHitIndices.isEmpty == false && pendingTargetIndices.isEmpty {
                        let nextTargetIndex = selectPhysicalTarget(
                            for: actor.side,
                            purpose: "attackTarget.carryOver.\(actor.id.rawValue).\(actionKind.rawValue)",
                            actionNumber: currentActionNumber,
                            excluding: processedTargetIndices
                        )
                        if let nextTargetIndex {
                            pendingTargetIndices.append(nextTargetIndex)
                            processedTargetIndices.insert(nextTargetIndex)
                        }
                    }
                }
                if queuedAction.canTriggerInterrupts {
                    generatedInterrupts += interruptActions(
                        after: queuedAction,
                        targetIndex: targetIndex,
                        targetWasDefeated: targetResult.flags.contains(.defeated)
                    )
                }
            }

            if queuedAction.allowsActionRuleFollowUps,
               isNormalAttack,
               !landedAnyHit {
                if combatants[actorIndex].status.actionRuleMaxValue(for: "repeatNormalAttackOnEvade") != nil,
                   let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: primaryTargetIndex) {
                    generatedInterrupts.append(followUp)
                } else if let chance = combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackOnEvadeChance") {
                    let roll = uniform(
                        turn: currentTurn,
                        action: currentActionNumber,
                        subaction: 97,
                        roll: actorIndex + 1,
                        purpose: "followup.evade.\(combatants[actorIndex].id.rawValue)"
                    )
                    if roll < chance,
                       let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: primaryTargetIndex) {
                        generatedInterrupts.append(followUp)
                    }
                }
            }
            if queuedAction.allowsActionRuleFollowUps,
               isNormalAttack,
               criticalTriggered {
                let followUpTargetIndex = combatants.indices.contains(primaryTargetIndex) && combatants[primaryTargetIndex].isAlive
                    ? primaryTargetIndex
                    : nil
                if combatants[actorIndex].status.actionRuleMaxValue(for: "repeatNormalAttackOnCritical") != nil,
                   let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: followUpTargetIndex) {
                    generatedInterrupts.append(followUp)
                }
            }

            generatedInterrupts = rescueInterruptActions(
                after: queuedAction,
                fallenTargetIndices: fallenTargetIndices
            ) + generatedInterrupts

            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actor.id,
                    actionKind: actionKind,
                    actionRef: nil,
                    actionFlags: criticalTriggered ? [BattleActionFlag.critical] : [],
                    targetIds: targetIds,
                    results: results
                ),
                generatedInterrupts: generatedInterrupts
            )
        }

        let guardedTarget = redirectedPhysicalTarget(
            originalTargetIndex: primaryTargetIndex,
            attackerIndex: actorIndex
        )
        let targetIndex = guardedTarget.targetIndex
        var hitMultiplier = 0.0
        var currentTargetAlive = combatants[targetIndex].isAlive

        // Multi-hit attacks decay each additional hit's contribution so extra swings matter,
        // but the first confirmed hit still carries the largest share of the damage.
        for hitIndex in 0..<attackCount where currentTargetAlive {
            if didHit(
                attackerIndex: actorIndex,
                defenderIndex: targetIndex,
                subactionNumber: hitIndex + 1,
                isNormalAttack: isNormalAttack,
                accuracyPctAdd: firstAttackAccuracyPctAdd
            ) {
                hitMultiplier += hitContribution(
                    for: hitIndex,
                    attackerIndex: actorIndex,
                    isNormalAttack: isNormalAttack
                )
            }
            currentTargetAlive = combatants[targetIndex].isAlive
        }

        let targetId = combatants[targetIndex].id
        let actionFlags = criticalTriggered ? [BattleActionFlag.critical] : []

        if hitMultiplier == 0 {
            let generatedInterrupts = (queuedAction.canTriggerInterrupts
                ? interruptActions(
                    after: queuedAction,
                    targetIndex: targetIndex,
                    targetWasDefeated: false
                )
                : [])
            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actor.id,
                    actionKind: actionKind,
                    actionRef: nil,
                    actionFlags: actionFlags,
                    targetIds: [targetId],
                    results: [
                        BattleTargetResult(
                            targetId: targetId,
                            resultKind: .miss,
                            value: nil,
                            statusId: nil,
                            flags: []
                        )
                    ]
                ),
                generatedInterrupts: generatedInterrupts
            )
        }

        let target = combatants[targetIndex]
        let targetWasLowHP = isLowHP(target)
        let guarded = target.isDefending
        var multiplier = actor.status.battleDerivedStats.physicalDamageMultiplier
        // Physical damage is assembled from actor-side bonuses first and only then reduced by
        // target-side resistance and guard state inside `damageValue`.
        multiplier *= formationMultiplier(for: actor)
        multiplier *= weaponDamageMultiplier(for: actor)
        multiplier *= queuedAction.attackPowerMultiplier
        multiplier *= livePartyModifier(
            for: actor.side,
            target: "allyPhysicalDamageMultiplier"
        )
        if actor.attackBuffActive {
            multiplier *= 1.5
        }
        if criticalTriggered {
            multiplier *= actor.status.battleDerivedStats.criticalDamageMultiplier
            if isNormalAttack, formationRank(for: actor.formationIndex) == .back {
                multiplier *= combatants[actorIndex].status.actionRuleMaxValue(
                    for: "backRowNormalAttackCriticalDamageMultiplier"
                ) ?? 1.0
            }
        }
        if isNormalAttack {
            multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackBaseDamageMultiplier") ?? 1.0
            if combatants[actorIndex].status.hasMeleeWeapon || combatants[actorIndex].status.isUnarmed {
                multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackMeleeDamageMultiplier") ?? 1.0
            }
            if combatants[actorIndex].status.hasRangedWeapon {
                multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackRangedDamageMultiplier") ?? 1.0
            }
            if isFirstNormalAttack {
                multiplier *= combatants[actorIndex].status.actionRuleMaxValue(
                    for: "firstNormalAttackPhysicalDamageMultiplier"
                ) ?? 1.0
            }
            multiplier *= combatants[actorIndex].nextNormalAttackPhysicalDamageMultiplier
        }
        if attackCount == 1 {
            multiplier *= combatants[actorIndex].status.actionRuleMaxValue(for: "attackCountOneMeleeDamageMultiplier") ?? 1.0
            if criticalTriggered {
                multiplier *= combatants[actorIndex].status.actionRuleMaxValue(
                    for: "attackCountOneCriticalDamageMultiplier"
                ) ?? 1.0
            }
        }
        if isLowHP(combatants[actorIndex]) {
            multiplier *= combatants[actorIndex].status.combatRuleMaxValue(for: "lowHPPhysicalDamageMultiplier") ?? 1.0
            multiplier *= combatants[actorIndex].status.combatRuleMaxValue(for: "lowHPMeleeDamageMultiplier") ?? 1.0
        }
        if isLowHP(target) {
            multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                for: "criticalDamageMultiplierAgainstLowHPTarget"
            ) ?? 1.0
            multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                for: "lowHPTargetRangedDamageMultiplier"
            ) ?? 1.0
        }
        if !target.ailments.isEmpty {
            multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                for: "damageMultiplierAgainstAilingTarget"
            ) ?? 1.0
        }
        if target.ailments.contains(.petrify) {
            multiplier *= combatants[actorIndex].status.combatRuleMaxValue(
                for: "damageMultiplierAgainstPetrifiedTarget"
            ) ?? 1.0
        }
        multiplier *= 1.0 + max(combatants[actorIndex].physicalDamagePctAddFromDamageTaken, 0.0)
        let lostHPTens = max(actor.status.maxHP - combatants[actorIndex].currentHP, 0) / max(actor.status.maxHP / 10, 1)
        let lostHPPctAdd = Double(lostHPTens) * (combatants[actorIndex].status.combatRuleMaxValue(
            for: "lostHP10PctToMeleeDamagePctAdd"
        ) ?? 0.0)
        multiplier *= 1.0 + lostHPPctAdd
        let elapsedTurnPctAdd = Double(max(currentTurn - 1, 0)) * (combatants[actorIndex].status.combatRuleMaxValue(
            for: "elapsedTurnToPhysicalAttackPctAdd"
        ) ?? 0.0)
        multiplier *= 1.0 + elapsedTurnPctAdd
        multiplier *= actionMultiplier(for: actorIndex, actionKind: actionKind)

        breakPhysicalBarrierOnNormalHitIfNeeded(
            attackerIndex: actorIndex,
            targetIndex: targetIndex,
            isNormalAttack: isNormalAttack
        )
        let barrierMultiplier = combatants[targetIndex].physicalBarrierActive ? 0.5 : 1.0
        let defendDamageTakenMultiplier = guarded
            ? target.status.defenseRuleProduct(for: "defendDamageTakenMultiplier")
            : 1.0
        let guardedDamageTakenMultiplier = guardedTarget.didRedirect
            ? target.status.defenseRuleProduct(for: "guardedDamageTakenMultiplier")
            : 1.0
        let partyDamageTakenMultiplier = livePartyModifier(
            for: target.side,
            target: "allyPhysicalDamageTakenMultiplier"
        )
        let basePower = physicalBasePower(
            attackerIndex: actorIndex,
            targetIndex: targetIndex,
            hitMultiplier: hitMultiplier,
            isNormalAttack: isNormalAttack
        )
        let damage = damageValue(
            actorIndex: actorIndex,
            basePower: basePower,
            multiplier: multiplier,
            resistance: target.status.battleDerivedStats.physicalResistanceMultiplier
                * (isLowHP(target)
                    ? (target.status.combatRuleMaxValue(for: "lowHPPhysicalResistanceMultiplier") ?? 1.0)
                    : 1.0)
                * partyDamageTakenMultiplier
                * guardedDamageTakenMultiplier
                * defendDamageTakenMultiplier,
            barrierMultiplier: barrierMultiplier,
            guarded: guarded,
            subactionNumber: 1,
            allowsHitSpecialRules: actionKind == .attack
        )
        let targetResult = applyDamage(
            damage,
            to: targetIndex,
            guarded: guarded,
            purposeSubaction: 1
        )
        if isNormalAttack {
            combatants[actorIndex].hasUsedFirstNormalAttack = true
            combatants[actorIndex].nextNormalAttackPhysicalDamageMultiplier = 1.0
        }

        var generatedInterrupts: [QueuedAction] = []
        generatedInterrupts = rescueInterruptActions(
            after: queuedAction,
            fallenTargetIndices: targetResult.flags.contains(.defeated) ? [targetIndex] : []
        )
        if queuedAction.canTriggerInterrupts {
            generatedInterrupts += interruptActions(
                after: queuedAction,
                targetIndex: targetIndex,
                targetWasDefeated: targetResult.flags.contains(.defeated)
            )
        }
        if queuedAction.allowsActionRuleFollowUps,
           isNormalAttack,
           hitMultiplier == 0 {
            if combatants[actorIndex].status.actionRuleMaxValue(for: "repeatNormalAttackOnEvade") != nil,
               let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: targetIndex) {
                generatedInterrupts.append(followUp)
            } else if let chance = combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackOnEvadeChance") {
                let roll = uniform(
                    turn: currentTurn,
                    action: currentActionNumber,
                    subaction: 97,
                    roll: actorIndex + 1,
                    purpose: "followup.evade.\(combatants[actorIndex].id.rawValue)"
                )
                if roll < chance,
                   let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: targetIndex) {
                    generatedInterrupts.append(followUp)
                }
            }
        }

        var results = [targetResult]
        if targetResult.resultKind == .damage {
            if let lifestealMultiplier = combatants[actorIndex].status.recoveryRuleMaxValue(for: "lifestealMultiplier"),
               targetResult.value ?? 0 > 0 {
                results.append(
                    applyHeal(
                        max(Int((Double(targetResult.value ?? 0) * lifestealMultiplier).rounded()), 1),
                        to: actorIndex
                    )
                )
            }
            results.append(contentsOf: applyOnHitAilments(
                from: actorIndex,
                to: targetIndex,
                subactionNumber: 1,
                includesAttackSpellTriggers: false,
                includesNormalAttackTriggers: isNormalAttack
            ))
            if isNormalAttack,
               combatants[actorIndex].status.actionRuleMaxValue(for: "restoreRandomAttackSpellUsageOnNormalHit") != nil {
                restoreOneAttackSpellCharge(for: actorIndex)
            }
            if targetResult.flags.contains(.defeated), targetWasLowHP {
                if let healRatio = combatants[actorIndex].status.recoveryRuleMaxValue(for: "healOnLowHPKillHPRatio") {
                    results.append(
                        applyHeal(
                            max(Int((Double(combatants[actorIndex].status.maxHP) * healRatio).rounded()), 1),
                            to: actorIndex
                        )
                    )
                }
                if queuedAction.allowsActionRuleFollowUps, isNormalAttack {
                    if combatants[actorIndex].status.actionRuleMaxValue(for: "extraActionOnLowHPKill") != nil,
                       combatants[actorIndex].canAct {
                        generatedInterrupts.append(selectNormalAction(for: actorIndex).asFollowUp())
                    }
                    if combatants[actorIndex].status.actionRuleMaxValue(for: "chainNormalAttackOnLowHPKill") != nil,
                       let nextTargetIndex = selectLowHPTarget(
                        for: combatants[actorIndex].side,
                        excluding: [targetIndex]
                       ),
                       let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: nextTargetIndex) {
                        generatedInterrupts.append(followUp)
                    }
                }
            }
            if queuedAction.allowsActionRuleFollowUps,
               isNormalAttack,
               criticalTriggered,
               combatants[actorIndex].status.actionRuleMaxValue(for: "repeatNormalAttackOnCritical") != nil,
               let followUp = makeFollowUpAttack(actorIndex: actorIndex, targetIndex: targetIndex) {
                generatedInterrupts.append(followUp)
            }
        }

        return ResolvedAction(
            record: BattleActionRecord(
                actorId: actor.id,
                actionKind: actionKind,
                actionRef: nil,
                actionFlags: actionFlags,
                targetIds: [targetId],
                results: results
            ),
            generatedInterrupts: generatedInterrupts
        )
    }

    private mutating func resolveRecoverySpell(_ queuedAction: QueuedAction) -> ResolvedAction? {
        guard let spellId = queuedAction.spellId,
              let spell = spellLookup[spellId] else {
            return nil
        }
        guard consumeSpell(spellId, for: queuedAction.actorIndex) else {
            return nil
        }

        let actorIndex = queuedAction.actorIndex
        let actorId = combatants[actorIndex].id

        // Recovery spells split into HP restoration, full restore, barrier application, and
        // ailment removal, but all branches still emit the same recovery-spell log shape.
        switch spell.kind {
        case .heal:
            let targetIndices = spell.targetCount == 0
                ? livingIndices(on: combatants[actorIndex].side)
                : healTargetIndices(for: actorIndex, actionNumber: currentActionNumber)
            guard !targetIndices.isEmpty else {
                return nil
            }

            let healValue = max(
                Int(
                    (
                        Double(combatants[actorIndex].status.battleStats.healing)
                        * combatants[actorIndex].status.battleDerivedStats.healingMultiplier
                        * actionMultiplier(for: actorIndex, actionKind: .recoverySpell)
                        * livePartyModifier(
                            for: combatants[actorIndex].side,
                            target: "allyHealingMultiplier"
                        )
                    ).rounded()
                ),
                1
            )
            var results: [BattleTargetResult] = []
            for targetIndex in targetIndices {
                let missingHP = max(combatants[targetIndex].status.maxHP - combatants[targetIndex].currentHP, 0)
                let healResult = applyHeal(healValue, to: targetIndex)
                results.append(healResult)
                if let barrierRatio = combatants[actorIndex].status.recoveryRuleMaxValue(
                    for: "recoverySpellBarrierByMaxHPRatio"
                ) {
                    let barrierAmount = max(
                        Int((Double(combatants[targetIndex].status.maxHP) * barrierRatio).rounded()),
                        1
                    )
                    combatants[targetIndex].extraHPBarrier += barrierAmount
                    results.append(
                        BattleTargetResult(
                            targetId: combatants[targetIndex].id,
                            resultKind: .modifierApplied,
                            value: barrierAmount,
                            statusId: nil,
                            flags: []
                        )
                    )
                }
                if let overhealMultiplier = combatants[actorIndex].status.recoveryRuleMaxValue(
                    for: "overhealToBarrierMultiplier"
                ) {
                    let scaledHeal = max(
                        Int((Double(healValue) * currentRecoveryMultiplier(for: targetIndex)).rounded()),
                        1
                    )
                    let overheal = max(scaledHeal - missingHP, 0)
                    if overheal > 0 {
                        let barrierAmount = max(Int((Double(overheal) * overhealMultiplier).rounded()), 1)
                        combatants[targetIndex].extraHPBarrier += barrierAmount
                        results.append(
                            BattleTargetResult(
                                targetId: combatants[targetIndex].id,
                                resultKind: .modifierApplied,
                                value: barrierAmount,
                                statusId: nil,
                                flags: []
                            )
                        )
                    }
                }
            }

            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actorId,
                    actionKind: .recoverySpell,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: targetIndices.map { combatants[$0].id },
                    results: results
                ),
                generatedInterrupts: []
            )
        case .fullHeal:
            let targetIndices = healTargetIndices(for: actorIndex, actionNumber: currentActionNumber)
            guard let targetIndex = targetIndices.first else {
                return nil
            }
            let result = applyHeal(combatants[targetIndex].status.maxHP, to: targetIndex, fullRestore: true)
            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actorId,
                    actionKind: .recoverySpell,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: [combatants[targetIndex].id],
                    results: [result]
                ),
                generatedInterrupts: []
            )
        case .barrier:
            let targetIndices = livingIndices(on: combatants[actorIndex].side)
            guard !targetIndices.isEmpty else {
                return nil
            }

            let isPhysicalBarrier = spell.effectTarget == "physicalDamageTaken"
            for targetIndex in targetIndices {
                if isPhysicalBarrier {
                    combatants[targetIndex].physicalBarrierActive = true
                } else {
                    combatants[targetIndex].magicBarrierActive = true
                }
            }

            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actorId,
                    actionKind: .recoverySpell,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: targetIndices.map { combatants[$0].id },
                    results: targetIndices.map { targetIndex in
                        BattleTargetResult(
                            targetId: combatants[targetIndex].id,
                            resultKind: .modifierApplied,
                            value: nil,
                            statusId: nil,
                            flags: []
                        )
                    }
                ),
                generatedInterrupts: []
            )
        case .cleanse:
            guard let targetIndex = cleanseTargetIndex(for: actorIndex, actionNumber: currentActionNumber) else {
                return nil
            }
            guard let removedAilment = removeAilment(from: targetIndex, actionNumber: currentActionNumber) else {
                return nil
            }
            var results = [
                BattleTargetResult(
                    targetId: combatants[targetIndex].id,
                    resultKind: .ailmentRemoved,
                    value: nil,
                    statusId: removedAilment.rawValue,
                    flags: []
                )
            ]
            if let extraHealMultiplier = combatants[actorIndex].status.recoveryRuleMaxValue(
                for: "cleanseExtraHealMultiplier"
            ) {
                let extraHeal = max(
                    Int(
                        (
                            Double(combatants[actorIndex].status.battleStats.healing)
                            * combatants[actorIndex].status.battleDerivedStats.healingMultiplier
                            * extraHealMultiplier
                            * livePartyModifier(
                                for: combatants[actorIndex].side,
                                target: "allyHealingMultiplier"
                            )
                        ).rounded()
                    ),
                    1
                )
                results.append(applyHeal(extraHeal, to: targetIndex))
            }
            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actorId,
                    actionKind: .recoverySpell,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: [combatants[targetIndex].id],
                    results: results
                ),
                generatedInterrupts: []
            )
        case .damage, .buff:
            return nil
        }
    }

    private mutating func resolveAttackSpell(_ queuedAction: QueuedAction) -> ResolvedAction? {
        guard let spellId = queuedAction.spellId,
              let spell = spellLookup[spellId] else {
            return nil
        }
        guard !queuedAction.consumesSpellCharge || consumeSpell(spellId, for: queuedAction.actorIndex) else {
            return nil
        }

        let actorIndex = queuedAction.actorIndex
        let actorId = combatants[actorIndex].id

        switch spell.kind {
        case .damage:
            let targetIndices = attackSpellTargets(
                for: spell,
                actorIndex: actorIndex,
                actionNumber: currentActionNumber,
                fixedTargetIndices: queuedAction.fixedTargetIndices
            )
            guard !targetIndices.isEmpty else {
                return nil
            }

            let actor = combatants[actorIndex]
            let targetedAilingEnemy = targetIndices.contains { !combatants[$0].ailments.isEmpty }
            let spellCriticalTriggered = actor.status.actionRuleMaxValue(for: "attackSpellCanCritical") != nil
                ? criticalDidTrigger(for: actorIndex)
                : false
            var fallenTargetIndices: [Int] = []
            let results = targetIndices.enumerated().flatMap { offset, targetIndex in
                let target = combatants[targetIndex]
                let guarded = target.isDefending
                // Spell damage is assembled from actor-side bonuses first, then reduced by the
                // target's spell-specific resistance, active barrier, and guard state.
                let multiplier = actor.status.battleDerivedStats.attackMagicMultiplier
                    * actor.status.battleDerivedStats.spellDamageMultiplier
                    * actor.status.spellDamageMultiplier(for: spell.id)
                    * (1.0 + Double(actor.attackSpellHitCount) * (actor.status.combatRuleMaxValue(
                        for: "attackSpellDamagePctAddPerHit"
                    ) ?? 0.0))
                    * livePartyModifier(
                        for: actor.side,
                        target: "allyMagicDamageMultiplier"
                    )
                    * (actor.magicBuffActive ? 1.5 : 1.0)
                    * (spell.multiplier ?? 1.0)
                    * actionMultiplier(for: actorIndex, actionKind: .attackSpell)
                    * (!target.ailments.isEmpty
                        ? (actor.status.combatRuleMaxValue(for: "damageMultiplierAgainstAilingTarget") ?? 1.0)
                        : 1.0)
                    * (target.ailments.contains(.petrify)
                        ? (actor.status.combatRuleMaxValue(for: "damageMultiplierAgainstPetrifiedTarget") ?? 1.0)
                        : 1.0)
                    * (spellCriticalTriggered ? actor.status.battleDerivedStats.criticalDamageMultiplier : 1.0)
                let barrierMultiplier = target.magicBarrierActive
                    ? (target.status.defenseRuleMaxValue(for: "magicBarrierDamageTakenMultiplier") ?? 0.5)
                    : 1.0
                let damage = damageValue(
                    actorIndex: actorIndex,
                    basePower: Double(
                        max(actor.status.battleStats.magic - target.status.battleStats.magicDefense, 0)
                    ),
                    multiplier: multiplier,
                    resistance: target.status.battleDerivedStats.magicResistanceMultiplier
                        * target.status.magicResistanceMultiplier(for: spell.id),
                    barrierMultiplier: barrierMultiplier
                        * livePartyModifier(
                            for: target.side,
                            target: "allyMagicDamageTakenMultiplier"
                        ),
                    guarded: guarded,
                    subactionNumber: offset + 1,
                    allowsHitSpecialRules: true
                )
                let damageResult = applyDamage(
                    damage,
                    to: targetIndex,
                    guarded: guarded,
                    purposeSubaction: offset + 1
                )
                if damageResult.resultKind == .damage, (damageResult.value ?? 0) > 0 {
                    combatants[actorIndex].attackSpellHitCount += 1
                }
                if damageResult.flags.contains(.defeated) {
                    fallenTargetIndices.append(targetIndex)
                }
                var targetResults = [damageResult]
                // Secondary ailment checks happen after damage so the battle log records the hit
                // result first and rescue triggers see the post-damage alive state.
                if let ailmentResult = applySpellAilmentIfNeeded(
                    spell,
                    from: actorIndex,
                    to: targetIndex,
                    subactionNumber: offset + 1
                ) {
                    targetResults.append(ailmentResult)
                }
                targetResults.append(contentsOf: applyOnHitAilments(
                    from: actorIndex,
                    to: targetIndex,
                    subactionNumber: offset + 1,
                    includesAttackSpellTriggers: true,
                    includesNormalAttackTriggers: false
                ))
                return targetResults
            }

            var generatedInterrupts = rescueInterruptActions(
                after: queuedAction,
                fallenTargetIndices: fallenTargetIndices
            )
            if queuedAction.allowsActionRuleFollowUps {
                if spellCriticalTriggered,
                   actor.status.actionRuleMaxValue(for: "repeatAttackSpellOnCritical") != nil {
                    generatedInterrupts.append(
                        QueuedAction(
                            actorIndex: actorIndex,
                            recordKind: .attackSpell,
                            spellId: spellId,
                            fixedTargetIndices: targetIndices,
                            canTriggerInterrupts: false,
                            countsAsNormalTurnAction: false,
                            consumesSpellCharge: false,
                            allowsActionRuleFollowUps: false
                        )
                    )
                }
                if targetedAilingEnemy,
                   actor.status.actionRuleMaxValue(for: "repeatAttackSpellOnAilingTarget") != nil {
                    generatedInterrupts.append(
                        QueuedAction(
                            actorIndex: actorIndex,
                            recordKind: .attackSpell,
                            spellId: spellId,
                            fixedTargetIndices: targetIndices,
                            canTriggerInterrupts: false,
                            countsAsNormalTurnAction: false,
                            consumesSpellCharge: false,
                            allowsActionRuleFollowUps: false
                        )
                    )
                }
            }

            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actorId,
                    actionKind: .attackSpell,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: targetIndices.map { combatants[$0].id },
                    results: results
                ),
                generatedInterrupts: generatedInterrupts
            )
        case .buff:
            let targetIndices = livingIndices(on: combatants[actorIndex].side)
            guard !targetIndices.isEmpty else {
                return nil
            }

            let boostsPhysical = spell.effectTarget == "physicalDamage"
            for targetIndex in targetIndices {
                if boostsPhysical {
                    combatants[targetIndex].attackBuffActive = true
                } else {
                    combatants[targetIndex].magicBuffActive = true
                }
            }

            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actorId,
                    actionKind: .attackSpell,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: targetIndices.map { combatants[$0].id },
                    results: targetIndices.map { targetIndex in
                        BattleTargetResult(
                            targetId: combatants[targetIndex].id,
                            resultKind: .modifierApplied,
                            value: nil,
                            statusId: nil,
                            flags: []
                        )
                    }
                ),
                generatedInterrupts: []
            )
        case .heal, .cleanse, .barrier, .fullHeal:
            return nil
        }
    }

    private mutating func resolveRescue(_ queuedAction: QueuedAction) -> ResolvedAction? {
        guard let stillDefeatedTargets = RescueResolutionValidation.survivingDefeatedTargetIndices(
            from: queuedAction.fixedTargetIndices,
            aliveStates: combatants.map(\.isAlive),
            actorCanAct: combatants[queuedAction.actorIndex].canAct
        ) else {
            return nil
        }

        guard let spellId = selectRescueSpell(for: queuedAction.actorIndex),
              let spell = spellLookup[spellId],
              consumeSpell(spellId, for: queuedAction.actorIndex) else {
            return nil
        }

        if spell.kind == .heal && spell.targetCount == 0 {
            // Party-targeted rescue heals every still-valid defeated ally instead of re-rolling
            // a single target after the interrupt has already been scheduled.
            let healValue = max(
                Int(
                    (
                        Double(combatants[queuedAction.actorIndex].status.battleStats.healing)
                        * combatants[queuedAction.actorIndex].status.battleDerivedStats.healingMultiplier
                        * livePartyModifier(
                            for: combatants[queuedAction.actorIndex].side,
                            target: "allyHealingMultiplier"
                        )
                    ).rounded()
                ),
                1
            )
            let results = stillDefeatedTargets.map { targetIndex in
                reviveTarget(targetIndex, recoveredHP: healValue, fullRestore: false)
            }
            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: combatants[queuedAction.actorIndex].id,
                    actionKind: .rescue,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: stillDefeatedTargets.map { combatants[$0].id },
                    results: results
                ),
                generatedInterrupts: []
            )
        }

        guard let targetIndex = randomChoice(
            from: stillDefeatedTargets,
            turn: currentTurn,
            action: currentActionNumber,
            subaction: 1,
            purpose: "rescueTarget.\(combatants[queuedAction.actorIndex].id.rawValue)"
        ) else {
            return nil
        }

        let fullRestore = spell.kind == .fullHeal
        let recoveredHP = fullRestore
            ? combatants[targetIndex].status.maxHP
            : max(
                Int(
                    (
                        Double(combatants[queuedAction.actorIndex].status.battleStats.healing)
                        * combatants[queuedAction.actorIndex].status.battleDerivedStats.healingMultiplier
                        * livePartyModifier(
                            for: combatants[queuedAction.actorIndex].side,
                            target: "allyHealingMultiplier"
                        )
                    ).rounded()
                ),
                1
            )
        let result = reviveTarget(targetIndex, recoveredHP: recoveredHP, fullRestore: fullRestore)
        return ResolvedAction(
            record: BattleActionRecord(
                actorId: combatants[queuedAction.actorIndex].id,
                actionKind: .rescue,
                actionRef: spellId,
                actionFlags: [],
                targetIds: [combatants[targetIndex].id],
                results: [result]
            ),
            generatedInterrupts: []
        )
    }

    private mutating func rescueInterruptActions(
        after queuedAction: QueuedAction,
        fallenTargetIndices: [Int]
    ) -> [QueuedAction] {
        // Rescue is only offered for newly defeated allies that are still valid by the time the
        // interrupt queue is built, which keeps chained interrupts deterministic.
        let rescueTargets = sanitizedRescueTargetIndices(
            after: queuedAction,
            fallenTargetIndices: fallenTargetIndices
        )
        guard !rescueTargets.isEmpty else {
            return []
        }

        let targetSide = combatants[rescueTargets[0]].side
        let rescueHolders = combatants.indices.filter { index in
            combatants[index].side == targetSide
                && combatants[index].canAct
                && combatants[index].status.interruptKinds.contains(.rescue)
                && selectRescueSpell(for: index) != nil
        }

        return rescueHolders.compactMap { rescuerIndex in
            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: rescuerIndex + 1,
                purpose: "interrupt.rescue.\(combatants[rescuerIndex].id.rawValue)"
            )
            guard roll < probability(for: .recoverySpell, rates: combatants[rescuerIndex].actionRates) else {
                return nil
            }
            return QueuedAction(
                actorIndex: rescuerIndex,
                recordKind: .rescue,
                fixedTargetIndices: rescueTargets,
                criticalAllowed: false,
                canTriggerInterrupts: false
            )
        }
    }

    private func sanitizedRescueTargetIndices(
        after queuedAction: QueuedAction,
        fallenTargetIndices: [Int]
    ) -> [Int] {
        // Enemies can trigger ally rescue; player-side defeats do not create mirror rescue logic.
        guard combatants[queuedAction.actorIndex].side == .enemy else {
            return []
        }

        switch queuedAction.recordKind {
        case .attack, .unarmedRepeat, .counter, .extraAttack, .pursuit, .breath, .attackSpell:
            break
        case .recoverySpell, .defend, .rescue:
            return []
        }

        var rescueTargets: [Int] = []
        for targetIndex in fallenTargetIndices {
            guard !targetIndex.isOutOfBounds(in: combatants),
                  combatants[targetIndex].side == .ally,
                  !rescueTargets.contains(targetIndex) else {
                continue
            }
            rescueTargets.append(targetIndex)
        }
        return rescueTargets
    }

    private mutating func interruptActions(
        after queuedAction: QueuedAction,
        targetIndex: Int,
        targetWasDefeated: Bool
    ) -> [QueuedAction] {
        let actorIndex = queuedAction.actorIndex
        var queuedInterrupts: [QueuedAction] = []

        // Counter and extra-attack are evaluated separately so both can trigger from one hit,
        // but each follow-up action is marked as non-recursive to prevent infinite chains.
        if combatants[targetIndex].canAct && combatants[targetIndex].status.interruptKinds.contains(.counter) {
            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: targetIndex + 1,
                purpose: "interrupt.counter.\(combatants[targetIndex].id.rawValue)"
            )
            if roll < 0.3 {
                queuedInterrupts.append(
                    QueuedAction(
                        actorIndex: targetIndex,
                        recordKind: .counter,
                        attackPowerMultiplier: 0.5,
                        attackCountMultiplier: 0.3,
                        criticalAllowed: false,
                        canTriggerInterrupts: false
                    )
                )
            }
        }

        if combatants[actorIndex].canAct && combatants[actorIndex].status.interruptKinds.contains(.extraAttack) {
            let chance = combatants[actorIndex].status.actionRuleMaxValue(for: "extraAttackChance") ?? 0.3
            let damageMultiplier = combatants[actorIndex].status.actionRuleMaxValue(
                for: "extraAttackDamageMultiplier"
            ) ?? 0.5
            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: actorIndex + 1,
                purpose: "interrupt.extraAttack.\(combatants[actorIndex].id.rawValue)"
            )
            if roll < chance {
                queuedInterrupts.append(
                    QueuedAction(
                        actorIndex: actorIndex,
                        recordKind: .extraAttack,
                        attackPowerMultiplier: damageMultiplier,
                        attackCountMultiplier: damageMultiplier,
                        criticalAllowed: false,
                        canTriggerInterrupts: false
                    )
                )
            }
        }

        if combatants[actorIndex].canAct,
           combatants[actorIndex].status.isUnarmed,
           !targetWasDefeated {
            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: actorIndex + 1,
                purpose: "interrupt.unarmedRepeat.\(combatants[actorIndex].id.rawValue)"
            )
            if roll < 0.3 {
                queuedInterrupts.append(
                    QueuedAction(
                        actorIndex: actorIndex,
                        recordKind: .unarmedRepeat,
                        criticalAllowed: true,
                        canTriggerInterrupts: false
                    )
                )
            }
        }

        for pursuingAllyIndex in pursuitCandidates(excluding: actorIndex) {
            let chance = max(
                combatants[pursuingAllyIndex].status.actionRuleMaxValue(for: "pursuitChance") ?? 0.3,
                isLowHP(combatants[targetIndex])
                    ? (combatants[pursuingAllyIndex].status.actionRuleMaxValue(
                        for: "pursuitAgainstLowHPTargetChance"
                    ) ?? 0.0)
                    : 0.0
            )
            let damageMultiplier = combatants[pursuingAllyIndex].status.actionRuleMaxValue(
                for: "pursuitDamageMultiplier"
            ) ?? 0.5
            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: pursuingAllyIndex + 1,
                purpose: "interrupt.pursuit.\(combatants[pursuingAllyIndex].id.rawValue)"
            )
            if roll < chance {
                queuedInterrupts.append(
                    QueuedAction(
                        actorIndex: pursuingAllyIndex,
                        recordKind: .pursuit,
                        attackPowerMultiplier: damageMultiplier,
                        attackCountMultiplier: damageMultiplier,
                        criticalAllowed: false,
                        canTriggerInterrupts: false
                    )
                )
            }
        }

        return queuedInterrupts
    }

    private mutating func resolveEndOfTurnAilments() {
        for index in combatants.indices where combatants[index].ailments.contains(.sleep) {
            let roll = uniform(
                turn: currentTurn,
                action: 99,
                subaction: 1,
                roll: index + 1,
                purpose: "ailment.sleep.recover.\(combatants[index].id.rawValue)"
            )
            if roll < 0.3 {
                combatants[index].ailments.remove(.sleep)
            }
        }

        for index in combatants.indices where !combatants[index].isAlive {
            guard let reviveChance = combatants[index].status.reviveRuleMaxValue(for: "endTurnReviveChance"),
                  let reviveHPRatio = combatants[index].status.reviveRuleMaxValue(for: "endTurnReviveHPRatio") else {
                continue
            }
            let roll = uniform(
                turn: currentTurn,
                action: 100,
                subaction: 1,
                roll: index + 1,
                purpose: "revive.endTurn.\(combatants[index].id.rawValue)"
            )
            guard roll < reviveChance else {
                continue
            }
            setCurrentHP(
                for: index,
                to: max(
                    1,
                    Int((Double(combatants[index].status.maxHP) * reviveHPRatio).rounded())
                )
            )
        }
    }

    private func currentOutcomeIfFinished() -> BattleOutcome? {
        let livingAllies = !livingAllyIndices.isEmpty
        let livingEnemies = !livingEnemyIndices.isEmpty

        switch (livingAllies, livingEnemies) {
        case (true, true):
            return nil
        case (true, false):
            return .victory
        case (false, true):
            return .defeat
        case (false, false):
            return .draw
        }
    }

    private func actionOrderScore(for combatantIndex: Int) -> Double {
        if usesRandomizedNormalActionOrder() {
            return uniform(
                turn: currentTurn,
                action: 0,
                subaction: 0,
                roll: combatantIndex + 1,
                purpose: "initiative.random.\(combatants[combatantIndex].id.rawValue)"
            )
        }
        let actor = combatants[combatantIndex]
        let u1 = uniform(
            turn: currentTurn,
            action: 0,
            subaction: 1,
            roll: combatantIndex + 1,
            purpose: "initiative.u1.\(actor.id.rawValue)"
        )
        let u2 = uniform(
            turn: currentTurn,
            action: 0,
            subaction: 1,
            roll: combatantIndex + 101,
            purpose: "initiative.u2.\(actor.id.rawValue)"
        )
        let luckBias = biasedLuck(actor.status.baseStats.luck)
        let biasedRoll = (1 - luckBias) * u1 + luckBias * max(u1, u2)
        let randomAdjustment = (biasedRoll - 0.5) * 14
        var actionSpeed = Double(actor.status.baseStats.agility)
            * actor.status.battleDerivedStats.actionSpeedMultiplier
        if currentTurn == 1 {
            actionSpeed *= actor.status.combatRuleMaxValue(for: "turnOneActionSpeedMultiplier") ?? 1.0
        }
        return actionSpeed + randomAdjustment
    }

    private func isLowHP(_ combatant: RuntimeCombatant) -> Bool {
        combatant.currentHP * 2 < combatant.status.maxHP
    }

    private func currentRecoveryMultiplier(for targetIndex: Int) -> Double {
        let target = combatants[targetIndex]
        var multiplier = target.status.recoveryRuleProduct(for: "receivedHealingMultiplier")
        if isLowHP(target) {
            multiplier *= target.status.recoveryRuleProduct(for: "lowHPReceivedHealingMultiplier")
        }
        return multiplier
    }

    private func actionMultiplier(for actorIndex: Int, actionKind: BattleLogActionKind) -> Double {
        let actor = combatants[actorIndex]
        let adaptationMultiplier = actor.status.combatRuleMaxValue(for: "highestOffenseActionMultiplier") ?? 1.0
        let physicalValue = actor.status.battleStats.physicalAttack
        let magicalValue = actor.status.battleStats.magic
        let healingValue = actor.status.battleStats.healing
        switch actionKind {
        case .attack, .unarmedRepeat, .counter, .extraAttack, .pursuit:
            return physicalValue >= magicalValue && physicalValue >= healingValue
                ? adaptationMultiplier
                : 1.0
        case .attackSpell:
            return magicalValue >= physicalValue && magicalValue >= healingValue
                ? adaptationMultiplier
                : 1.0
        case .recoverySpell, .rescue:
            return healingValue >= physicalValue && healingValue >= magicalValue
                ? adaptationMultiplier
                : 1.0
        case .breath, .defend:
            return 1.0
        }
    }

    private func compareCombatantPriority(_ lhs: Int, _ rhs: Int) -> Bool {
        BattleActionOrderPriorityKey.ordersBefore(priorityKey(for: lhs), priorityKey(for: rhs))
    }

    private func sortInterrupts(_ actions: [QueuedAction]) -> [QueuedAction] {
        actions.sorted { lhs, rhs in
            if lhs.interruptPriority != rhs.interruptPriority {
                return lhs.interruptPriority < rhs.interruptPriority
            }
            return compareCombatantPriority(lhs.actorIndex, rhs.actorIndex)
        }
    }

    private func isNormalAttackAction(_ actionKind: BattleLogActionKind) -> Bool {
        actionKind == .attack
    }

    private func hitContribution(
        for hitIndex: Int,
        attackerIndex: Int,
        isNormalAttack: Bool
    ) -> Double {
        guard hitIndex > 0 else {
            return 1.0
        }
        guard isNormalAttack else {
            return pow(0.5, Double(hitIndex))
        }

        let falloffBase = combatants[attackerIndex].status.multiHitFalloffModifier
        guard falloffBase > 0 else {
            return 1.0
        }
        return pow(falloffBase, Double(hitIndex))
    }

    private func livePartyModifier(
        for side: BattleSide,
        target: String
    ) -> Double {
        switch side {
        case .ally:
            return allyPartyModifiersByTarget[target] ?? 1.0
        case .enemy:
            return enemyPartyModifiersByTarget[target] ?? 1.0
        }
    }

    private func redirectedPhysicalTarget(
        originalTargetIndex: Int,
        attackerIndex: Int
    ) -> (targetIndex: Int, didRedirect: Bool) {
        let originalTarget = combatants[originalTargetIndex]
        let guardians = combatants.indices
            .filter {
                $0 != originalTargetIndex
                    && combatants[$0].side == originalTarget.side
                    && combatants[$0].isAlive
                    && combatants[$0].status.actionRuleMaxValue(for: "guardPhysicalActionChance") != nil
            }
            .sorted(by: compareCombatantPriority)

        for guardianIndex in guardians {
            let chance = combatants[guardianIndex].status.actionRuleMaxValue(
                for: "guardPhysicalActionChance"
            ) ?? 0.0
            guard chance > 0 else {
                continue
            }

            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: guardianIndex + 1,
                purpose: "guard.redirect.\(combatants[attackerIndex].id.rawValue).\(combatants[guardianIndex].id.rawValue)"
            )
            if roll < chance {
                return (guardianIndex, true)
            }
        }

        return (originalTargetIndex, false)
    }

    private mutating func applyOnHitAilments(
        from actorIndex: Int,
        to targetIndex: Int,
        subactionNumber: Int,
        includesAttackSpellTriggers: Bool,
        includesNormalAttackTriggers: Bool
    ) -> [BattleTargetResult] {
        var results: [BattleTargetResult] = []
        let inflictionMultiplier = combatants[actorIndex].status.combatRuleProduct(
            for: "ailmentInflictionChanceMultiplier"
        )
        let statusIds = combatants[actorIndex].status.onHitAilmentChanceByStatusID.keys.sorted()

        for statusId in statusIds {
            let baseChance = combatants[actorIndex].status.onHitAilmentChanceByStatusID[statusId, default: 0.0]
            if let result = applyAilmentIfNeeded(
                statusId: statusId,
                chance: min(baseChance * inflictionMultiplier, 1.0),
                from: actorIndex,
                to: targetIndex,
                subactionNumber: subactionNumber,
                purposeKey: "skill.\(statusId)"
            ) {
                results.append(result)
            }
        }

        if includesNormalAttackTriggers,
           let chance = combatants[actorIndex].status.contactAilmentChanceByStatusID[BattleAilment.sleep.rawValue],
           let result = applyAilmentIfNeeded(
               statusId: BattleAilment.sleep.rawValue,
               chance: min(chance * inflictionMultiplier, 1.0),
               from: actorIndex,
               to: targetIndex,
               subactionNumber: subactionNumber,
               purposeKey: "special.sleep"
           ) {
            results.append(result)
        }

        if includesAttackSpellTriggers,
           let chance = combatants[actorIndex].status.contactAilmentChanceByStatusID[BattleAilment.sleep.rawValue],
           let result = applyAilmentIfNeeded(
               statusId: BattleAilment.sleep.rawValue,
               chance: min(chance * inflictionMultiplier, 1.0),
               from: actorIndex,
               to: targetIndex,
               subactionNumber: subactionNumber,
               purposeKey: "special.sleep"
           ) {
            results.append(result)
        }

        if includesNormalAttackTriggers,
           let chance = combatants[actorIndex].status.contactAilmentChanceByStatusID[BattleAilment.petrify.rawValue],
           let result = applyAilmentIfNeeded(
               statusId: BattleAilment.petrify.rawValue,
               chance: min(chance * inflictionMultiplier, 1.0),
               from: actorIndex,
               to: targetIndex,
               subactionNumber: subactionNumber,
               purposeKey: "special.petrify"
           ) {
            results.append(result)
        }

        if includesAttackSpellTriggers,
           let chance = combatants[actorIndex].status.contactAilmentChanceByStatusID[BattleAilment.petrify.rawValue],
           let result = applyAilmentIfNeeded(
               statusId: BattleAilment.petrify.rawValue,
               chance: min(chance * inflictionMultiplier, 1.0),
               from: actorIndex,
               to: targetIndex,
               subactionNumber: subactionNumber,
               purposeKey: "special.petrify"
           ) {
            results.append(result)
        }

        return results
    }

    private mutating func applyAilmentIfNeeded(
        statusId: Int,
        chance: Double,
        from actorIndex: Int,
        to targetIndex: Int,
        subactionNumber: Int,
        purposeKey: String
    ) -> BattleTargetResult? {
        guard chance > 0,
              let ailment = BattleAilment(rawValue: statusId),
              combatants[targetIndex].isAlive,
              !combatants[targetIndex].ailments.contains(ailment) else {
            return nil
        }

        let roll = uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 7 + statusId,
            purpose: "status.apply.\(purposeKey).\(combatants[actorIndex].id.rawValue).\(combatants[targetIndex].id.rawValue)"
        )
        guard roll < chance else {
            return nil
        }

        combatants[targetIndex].ailments.insert(ailment)
        return BattleTargetResult(
            targetId: combatants[targetIndex].id,
            resultKind: .modifierApplied,
            value: nil,
            statusId: ailment.rawValue,
            flags: []
        )
    }

    private func didHit(
        attackerIndex: Int,
        defenderIndex: Int,
        subactionNumber: Int,
        isNormalAttack: Bool,
        accuracyPctAdd: Double = 0.0
    ) -> Bool {
        let attacker = combatants[attackerIndex]
        let defender = combatants[defenderIndex]
        let u1 = uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 1,
            purpose: "hit.u1.\(attacker.id.rawValue).\(defender.id.rawValue)"
        )
        let u2 = uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 2,
            purpose: "hit.u2.\(attacker.id.rawValue).\(defender.id.rawValue)"
        )
        let u3 = uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 3,
            purpose: "evasion.u1.\(attacker.id.rawValue).\(defender.id.rawValue)"
        )
        let u4 = uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 4,
            purpose: "evasion.u2.\(attacker.id.rawValue).\(defender.id.rawValue)"
        )

        // Luck biases each side toward the better of two rolls, then the resulting accuracy gap is
        // clamped so deterministic battles still preserve a minimum miss and hit chance.
        let hitLuckBias = biasedLuck(attacker.status.baseStats.luck)
        let evadeLuckBias = biasedLuck(defender.status.baseStats.luck)
        let hitRoll = (1 - hitLuckBias) * u1 + hitLuckBias * max(u1, u2)
        let evadeRoll = (1 - evadeLuckBias) * u3 + evadeLuckBias * max(u3, u4)
        // Luck only nudges each side by a bounded percentage; the final hit rate still comes from
        // the relative weight between accuracy and evasion rather than a flat additive gap.
        let volatility = 0.2
        let rolledAccuracy = Double(attacker.status.battleStats.accuracy)
            * (1.0 + accuracyPctAdd)
            * (1 + volatility * (hitRoll - 0.5))
        let rolledEvasion = Double(defender.status.battleStats.evasion)
            * (1 + volatility * (evadeRoll - 0.5))
        let rawHitRate = rolledAccuracy / max(rolledAccuracy + rolledEvasion, 0.0001)
        let hitFloor = isNormalAttack
            ? combatants[attackerIndex].status.hitRateFloor
            : 0.10
        let hitRate = min(max(rawHitRate, hitFloor), 0.90)
        return uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 5,
            purpose: "hit.judge.\(attacker.id.rawValue).\(defender.id.rawValue)"
        ) < hitRate
    }

    private func criticalDidTrigger(for attackerIndex: Int, criticalRateBonus: Double = 0.0) -> Bool {
        let attacker = combatants[attackerIndex]
        let rawRate = attacker.status.isUnarmed
            ? Double(attacker.status.battleStats.criticalRate) * 1.5
            : Double(attacker.status.battleStats.criticalRate)
        let criticalRate = min(rawRate + criticalRateBonus, 75) / 100
        return uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: 1,
            roll: attackerIndex + 1,
            purpose: "critical.\(attacker.id.rawValue)"
        ) < criticalRate
    }

    private mutating func restoreOneAttackSpellCharge(for actorIndex: Int) {
        let candidates = combatants[actorIndex].status.spellIds
            .compactMap { spellLookup[$0] }
            .filter { $0.category == .attack }
            .map(\.id)
            .sorted(by: >)
        guard let spellId = randomChoice(
            from: candidates,
            turn: currentTurn,
            action: currentActionNumber,
            subaction: 98,
            purpose: "spell.restore.\(combatants[actorIndex].id.rawValue)"
        ) else {
            return
        }
        combatants[actorIndex].spellCharges[spellId, default: 0] += 1
    }

    private func damageValue(
        actorIndex: Int,
        basePower: Double,
        multiplier: Double,
        resistance: Double,
        barrierMultiplier: Double,
        guarded: Bool,
        subactionNumber: Int,
        allowsHitSpecialRules: Bool
    ) -> Int {
        let guardedMultiplier = guarded ? 0.5 : 1.0
        var value = Int(
            (basePower * multiplier * resistance * barrierMultiplier * guardedMultiplier)
                .rounded()
        )
        value = max(value, 1)

        if let varianceMultiplier = damageVarianceMultiplier(
            for: actorIndex,
            subactionNumber: subactionNumber
        ) {
            value = max(Int((Double(value) * varianceMultiplier).rounded()), 1)
        }

        guard allowsHitSpecialRules else {
            return value
        }

        if damageLuckyDidTrigger(for: actorIndex, subactionNumber: subactionNumber) {
            value = max(
                Int(
                    (
                        Double(value)
                        * (combatants[actorIndex].status.hitRuleMaxValue(for: "hitDamageLuckyMultiplier") ?? 1.0)
                    ).rounded()
                ),
                1
            )
        }
        if damageUnluckyDidTrigger(for: actorIndex, subactionNumber: subactionNumber) {
            value = max(
                Int(
                    (
                        Double(value)
                        * (combatants[actorIndex].status.hitRuleMaxValue(for: "hitDamageUnluckyMultiplier") ?? 1.0)
                    ).rounded()
                ),
                1
            )
        }
        return value
    }

    private func damageVarianceMultiplier(
        for actorIndex: Int,
        subactionNumber: Int
    ) -> Double? {
        guard let widthScale = combatants[actorIndex].status.hitRuleMaxValue(
            for: "damageVarianceWidthMultiplier"
        ) else {
            return nil
        }
        let halfWidth = max(widthScale, 1.0) * 0.1
        let roll = uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 81,
            purpose: "damage.variance.\(combatants[actorIndex].id.rawValue)"
        )
        return 1.0 + ((roll * 2.0) - 1.0) * halfWidth
    }

    private func damageLuckyDidTrigger(
        for actorIndex: Int,
        subactionNumber: Int
    ) -> Bool {
        guard let chance = combatants[actorIndex].status.hitRuleMaxValue(for: "hitDamageLuckyChance"),
              chance > 0 else {
            return false
        }
        return uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 82,
            purpose: "damage.lucky.\(combatants[actorIndex].id.rawValue)"
        ) < chance
    }

    private func damageUnluckyDidTrigger(
        for actorIndex: Int,
        subactionNumber: Int
    ) -> Bool {
        guard let chance = combatants[actorIndex].status.hitRuleMaxValue(for: "hitDamageUnluckyChance"),
              chance > 0 else {
            return false
        }
        return uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 83,
            purpose: "damage.unlucky.\(combatants[actorIndex].id.rawValue)"
        ) < chance
    }

    private func normalAttackIgnorePhysicalDefensePct(for actorIndex: Int) -> Double {
        min(
            max(
                combatants[actorIndex].status.actionRuleMaxValue(for: "normalAttackIgnorePhysicalDefensePct") ?? 0.0,
                0.0
            ),
            1.0
        )
    }

    private func normalAttackAdditionalTargetDamageMultiplier(
        for actorIndex: Int,
        isPrimaryTarget: Bool
    ) -> Double {
        guard !isPrimaryTarget else {
            return 1.0
        }
        return combatants[actorIndex].status.actionRuleMaxValue(
            for: "normalAttackAdditionalTargetDamageMultiplier"
        ) ?? 1.0
    }

    private func physicalBasePower(
        attackerIndex: Int,
        targetIndex: Int,
        hitMultiplier: Double,
        isNormalAttack: Bool
    ) -> Double {
        let ignoredPhysicalDefensePct = isNormalAttack
            ? normalAttackIgnorePhysicalDefensePct(for: attackerIndex)
            : 0.0
        let effectivePhysicalDefense = Double(combatants[targetIndex].status.battleStats.physicalDefense)
            * (1.0 - ignoredPhysicalDefensePct)
        return max(
            Double(combatants[attackerIndex].status.battleStats.physicalAttack) - effectivePhysicalDefense,
            0
        ) * hitMultiplier
    }

    private mutating func breakPhysicalBarrierOnNormalHitIfNeeded(
        attackerIndex: Int,
        targetIndex: Int,
        isNormalAttack: Bool
    ) {
        guard isNormalAttack,
              combatants[attackerIndex].status.actionRuleMaxValue(for: "normalAttackBreakPhysicalBarrierOnHit") != nil,
              combatants[targetIndex].physicalBarrierActive else {
            return
        }
        combatants[targetIndex].physicalBarrierActive = false
    }

    private mutating func applyDamage(
        _ value: Int,
        to targetIndex: Int,
        guarded: Bool,
        purposeSubaction: Int
    ) -> BattleTargetResult {
        let wasAlive = combatants[targetIndex].isAlive
        var remainingDamage = value
        if combatants[targetIndex].extraHPBarrier > 0 {
            let absorbed = min(combatants[targetIndex].extraHPBarrier, remainingDamage)
            combatants[targetIndex].extraHPBarrier -= absorbed
            remainingDamage -= absorbed
        }
        combatants[targetIndex].currentHP = max(combatants[targetIndex].currentHP - remainingDamage, 0)
        if wasAlive && remainingDamage > 0 {
            combatants[targetIndex].physicalDamagePctAddFromDamageTaken += combatants[targetIndex].status.combatRuleProduct(
                for: "physicalDamagePctAddOnDamageTaken"
            ) - 1.0
            let nextAttackMultiplier = combatants[targetIndex].status.combatRuleMaxValue(
                for: "nextNormalAttackPhysicalDamageMultiplierAfterTakingDamage"
            ) ?? 1.0
            combatants[targetIndex].nextNormalAttackPhysicalDamageMultiplier = max(
                combatants[targetIndex].nextNormalAttackPhysicalDamageMultiplier,
                nextAttackMultiplier
            )
        }
        var flags: [BattleTargetResultFlag] = guarded ? [.guarded] : []
        if wasAlive && !combatants[targetIndex].isAlive {
            if !combatants[targetIndex].hasUsedSurviveFirstDefeat,
               combatants[targetIndex].status.reviveRuleMaxValue(for: "surviveFirstDefeatAtHP1") != nil {
                combatants[targetIndex].currentHP = 1
                combatants[targetIndex].hasUsedSurviveFirstDefeat = true
            } else if !combatants[targetIndex].hasUsedReviveOnceOnFirstDefeat,
                      let ratio = combatants[targetIndex].status.reviveRuleMaxValue(
                        for: "reviveOnceOnFirstDefeatHPRatio"
                      ) {
                combatants[targetIndex].currentHP = max(
                    1,
                    Int((Double(combatants[targetIndex].status.maxHP) * ratio).rounded())
                )
                combatants[targetIndex].hasUsedReviveOnceOnFirstDefeat = true
                flags.append(.revived)
            } else {
                flags.append(.defeated)
            }
        }
        if wasAlive != combatants[targetIndex].isAlive {
            refreshBattlefieldCaches()
        }

        return BattleTargetResult(
            targetId: combatants[targetIndex].id,
            resultKind: .damage,
            value: value,
            statusId: nil,
            flags: flags.sorted(by: { $0.rawValue < $1.rawValue })
        )
    }

    private mutating func applyHeal(
        _ value: Int,
        to targetIndex: Int,
        fullRestore: Bool = false
    ) -> BattleTargetResult {
        let originalHP = combatants[targetIndex].currentHP
        let scaledValue = max(
            Int((Double(value) * currentRecoveryMultiplier(for: targetIndex)).rounded()),
            1
        )
        let restoredHP = fullRestore
            ? combatants[targetIndex].status.maxHP
            : min(combatants[targetIndex].currentHP + scaledValue, combatants[targetIndex].status.maxHP)
        setCurrentHP(for: targetIndex, to: restoredHP)
        return BattleTargetResult(
            targetId: combatants[targetIndex].id,
            resultKind: .heal,
            value: restoredHP - originalHP,
            statusId: nil,
            flags: []
        )
    }

    private mutating func reviveTarget(
        _ targetIndex: Int,
        recoveredHP: Int,
        fullRestore: Bool
    ) -> BattleTargetResult {
        let restoredHP = fullRestore
            ? combatants[targetIndex].status.maxHP
            : max(1, min(recoveredHP, combatants[targetIndex].status.maxHP))
        setCurrentHP(for: targetIndex, to: restoredHP)
        return BattleTargetResult(
            targetId: combatants[targetIndex].id,
            resultKind: .heal,
            value: restoredHP,
            statusId: nil,
            flags: [.revived]
        )
    }

    private mutating func applySpellAilmentIfNeeded(
        _ spell: MasterData.Spell,
        from actorIndex: Int,
        to targetIndex: Int,
        subactionNumber: Int
    ) -> BattleTargetResult? {
        guard let statusId = spell.statusId,
              let statusChance = spell.statusChance,
              let ailment = BattleAilment(rawValue: statusId),
              combatants[targetIndex].isAlive,
              !combatants[targetIndex].ailments.contains(ailment) else {
            return nil
        }

        let roll = uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 6,
            purpose: "status.apply.\(combatants[actorIndex].id.rawValue).spell.\(spell.id).\(combatants[targetIndex].id.rawValue)"
        )
        let chance = min(
            statusChance * combatants[actorIndex].status.combatRuleProduct(
                for: "ailmentInflictionChanceMultiplier"
            ),
            1.0
        )
        guard roll < chance else {
            return nil
        }

        combatants[targetIndex].ailments.insert(ailment)
        return BattleTargetResult(
            targetId: combatants[targetIndex].id,
            resultKind: .modifierApplied,
            value: nil,
            statusId: ailment.rawValue,
            flags: []
        )
    }

    private mutating func removeAilment(
        from targetIndex: Int,
        actionNumber: Int
    ) -> BattleAilment? {
        let ailments = combatants[targetIndex].ailments.sorted { $0.rawValue < $1.rawValue }
        guard let ailment = randomChoice(
            from: ailments,
            turn: currentTurn,
            action: actionNumber,
            subaction: 1,
            purpose: "cleanse.choice.\(combatants[targetIndex].id.rawValue)"
        ) else {
            return nil
        }
        combatants[targetIndex].ailments.remove(ailment)
        return ailment
    }

    private func formationMultiplier(for combatant: RuntimeCombatant) -> Double {
        let rank = formationRank(for: combatant.formationIndex)
        var multiplier = 1.0

        if combatant.status.isUnarmed || combatant.status.hasMeleeWeapon {
            multiplier *= meleeFormationMultiplier(for: rank)
        }

        if combatant.status.hasRangedWeapon {
            multiplier *= rangedFormationMultiplier(for: rank)
        }

        return multiplier
    }

    private func weaponDamageMultiplier(for combatant: RuntimeCombatant) -> Double {
        if combatant.status.isUnarmed {
            return combatant.status.battleDerivedStats.meleeDamageMultiplier * 1.5
        }

        switch combatant.status.weaponRangeClass {
        case .ranged:
            return combatant.status.battleDerivedStats.rangedDamageMultiplier
        case .none, .melee:
            return combatant.status.battleDerivedStats.meleeDamageMultiplier
        }
    }

    private func formationRank(for formationIndex: Int) -> FormationRank {
        switch formationIndex {
        case 0, 1:
            .front
        case 2, 3:
            .middle
        default:
            .back
        }
    }

    private func meleeFormationMultiplier(for rank: FormationRank) -> Double {
        switch rank {
        case .front:
            1.00
        case .middle:
            0.85
        case .back:
            0.70
        }
    }

    private func rangedFormationMultiplier(for rank: FormationRank) -> Double {
        switch rank {
        case .front:
            0.70
        case .middle:
            0.85
        case .back:
            1.00
        }
    }

    private func adjustedAttackCount(for combatantIndex: Int, multiplier: Double) -> Int {
        let rawCount = Double(combatants[combatantIndex].status.battleStats.attackCount) * multiplier
        return max(Int(rawCount.rounded()), 1)
    }

    private func isCandidateExecutable(_ actionKind: BattleActionKind, for actorIndex: Int) -> Bool {
        switch actionKind {
        case .breath:
            combatants[actorIndex].status.canUseBreath
                && combatants[actorIndex].breathUsesRemaining > 0
                && !livingIndices(on: opposingSide(of: combatants[actorIndex].side)).isEmpty
        case .attack:
            !livingIndices(on: opposingSide(of: combatants[actorIndex].side)).isEmpty
        case .recoverySpell:
            selectSpell(for: actorIndex, category: .recovery, purposePrefix: "availabilityRecovery") != nil
        case .attackSpell:
            selectSpell(for: actorIndex, category: .attack, purposePrefix: "availabilityAttack") != nil
        }
    }

    private func selectSpell(
        for actorIndex: Int,
        category: SpellCategory,
        purposePrefix: String
    ) -> Int? {
        let usableSpells = combatants[actorIndex].status.spellIds
            .sorted(by: >)
            .compactMap { spellLookup[$0] }
            .filter { $0.category == category && isSpellUsable($0, for: actorIndex) }

        guard !usableSpells.isEmpty else {
            return nil
        }
        if usableSpells.count == 1 {
            return usableSpells[0].id
        }

        for (offset, spell) in usableSpells.dropLast().enumerated() {
            let roll = uniform(
                turn: currentTurn,
                action: 0,
                subaction: offset + 1,
                roll: actorIndex + 1,
                purpose: "\(purposePrefix).\(combatants[actorIndex].id.rawValue).spell.\(spell.id)"
            )
            if roll < 0.5 {
                return spell.id
            }
        }

        return usableSpells.last?.id
    }

    private func isSpellUsable(_ spell: MasterData.Spell, for actorIndex: Int) -> Bool {
        guard combatants[actorIndex].spellCharges[spell.id, default: 0] > 0 else {
            return false
        }

        switch spell.kind {
        case .damage:
            return switch spell.targetSide {
            case .enemy:
                !livingIndices(on: opposingSide(of: combatants[actorIndex].side)).isEmpty
            case .ally:
                !livingIndices(on: combatants[actorIndex].side).isEmpty
            case .both:
                !livingIndices().isEmpty
            }
        case .heal, .fullHeal:
            return hasInjuredHealingTarget(on: combatants[actorIndex].side)
        case .cleanse:
            return cleanseTargetIndex(for: actorIndex, actionNumber: currentActionNumber) != nil
        case .barrier, .buff:
            return !livingIndices(on: combatants[actorIndex].side).isEmpty
        }
    }

    private func hasInjuredHealingTarget(on side: BattleSide) -> Bool {
        combatants.contains {
            $0.side == side && $0.isAlive && $0.currentHP * 2 <= $0.status.maxHP
        }
    }

    private func probability(for actionKind: BattleActionKind, rates: CharacterActionRates) -> Double {
        switch actionKind {
        case .breath:
            Double(rates.breath) / 100
        case .attack:
            Double(rates.attack) / 100
        case .recoverySpell:
            Double(rates.recoverySpell) / 100
        case .attackSpell:
            Double(rates.attackSpell) / 100
        }
    }

    private mutating func consumeSpell(_ spellId: Int, for combatantIndex: Int) -> Bool {
        let currentCharges = combatants[combatantIndex].spellCharges[spellId, default: 0]
        guard currentCharges > 0 else {
            return false
        }
        combatants[combatantIndex].spellCharges[spellId] = currentCharges - 1
        return true
    }

    private func selectRescueSpell(for combatantIndex: Int) -> Int? {
        let usableRescueSpells = combatants[combatantIndex].status.spellIds
            .sorted(by: >)
            .filter { spellId in
                guard let spell = spellLookup[spellId],
                      combatants[combatantIndex].spellCharges[spellId, default: 0] > 0 else {
                    return false
                }
                return spell.category == .recovery
                    && (spell.kind == .heal || spell.kind == .fullHeal)
            }

        if let healAllSpellId = usableRescueSpells.first(where: {
            spellLookup[$0]?.kind == .heal && spellLookup[$0]?.targetCount == 0
        }) {
            return healAllSpellId
        }
        return usableRescueSpells.first
    }

    private func healTargetIndices(for actorIndex: Int, actionNumber: Int) -> [Int] {
        let candidates = combatants.indices.filter {
            combatants[$0].side == combatants[actorIndex].side
                && combatants[$0].isAlive
                && combatants[$0].currentHP * 2 <= combatants[$0].status.maxHP
        }
        guard !candidates.isEmpty else {
            return []
        }

        let minimumHP = candidates.map { combatants[$0].currentHP }.min() ?? 0
        let lowestHPIndices = candidates.filter { combatants[$0].currentHP == minimumHP }
        let highestLevel = lowestHPIndices.map { combatants[$0].level }.max() ?? 0
        let highestLevelIndices = lowestHPIndices.filter { combatants[$0].level == highestLevel }
        guard let chosen = randomChoice(
            from: highestLevelIndices,
            turn: currentTurn,
            action: actionNumber,
            subaction: 1,
            purpose: "healingTargetSelection.\(combatants[actorIndex].id.rawValue)"
        ) else {
            return []
        }
        return [chosen]
    }

    private func cleanseTargetIndex(for actorIndex: Int, actionNumber: Int) -> Int? {
        let candidates = combatants.indices.filter {
            combatants[$0].side == combatants[actorIndex].side
                && combatants[$0].isAlive
                && !combatants[$0].ailments.isEmpty
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let minimumHP = candidates.map { combatants[$0].currentHP }.min() ?? 0
        let lowestHPIndices = candidates.filter { combatants[$0].currentHP == minimumHP }
        let highestLevel = lowestHPIndices.map { combatants[$0].level }.max() ?? 0
        let highestLevelIndices = lowestHPIndices.filter { combatants[$0].level == highestLevel }
        return randomChoice(
            from: highestLevelIndices,
            turn: currentTurn,
            action: actionNumber,
            subaction: 1,
            purpose: "healingTargetSelection.\(combatants[actorIndex].id.rawValue)"
        )
    }

    private mutating func attackSpellTargets(
        for spell: MasterData.Spell,
        actorIndex: Int,
        actionNumber: Int,
        fixedTargetIndices: [Int]? = nil
    ) -> [Int] {
        if let fixedTargetIndices {
            return fixedTargetIndices.filter { combatants.indices.contains($0) && combatants[$0].isAlive }
        }
        switch spell.targetSide {
        case .both:
            return livingIndices()
        case .ally:
            return livingIndices(on: combatants[actorIndex].side)
        case .enemy:
            let opposingIndices = livingIndices(on: opposingSide(of: combatants[actorIndex].side))
            guard spell.targetCount > 0, spell.targetCount < opposingIndices.count else {
                return opposingIndices
            }

            var remaining = opposingIndices
            var selected: [Int] = []
            for selectionIndex in 0..<spell.targetCount {
                guard let chosen = randomChoice(
                    from: remaining,
                    turn: currentTurn,
                    action: actionNumber,
                    subaction: selectionIndex + 1,
                    purpose: "attackSpellTargets.\(combatants[actorIndex].id.rawValue).spell.\(spell.id)"
                ) else {
                    break
                }
                selected.append(chosen)
                remaining.removeAll { $0 == chosen }
            }
            return selected
        }
    }

    private func selectPhysicalTargetGroup(
        for actingSide: BattleSide,
        purpose: String,
        actionNumber: Int,
        excluding excludedIndices: Set<Int> = []
    ) -> [Int]? {
        let candidateGroups = [
            livingIndices(on: opposingSide(of: actingSide), rank: .front),
            livingIndices(on: opposingSide(of: actingSide), rank: .middle),
            livingIndices(on: opposingSide(of: actingSide), rank: .back)
        ].map { group in
            group.filter { !excludedIndices.contains($0) }
        }
        let groups = candidateGroups.filter { !$0.isEmpty }
        guard !groups.isEmpty else {
            return nil
        }

        for (groupIndex, group) in groups.dropLast().enumerated() {
            let choiceRange = group.count + 1
            let roll = integer(
                upperBound: choiceRange,
                turn: currentTurn,
                action: actionNumber,
                subaction: groupIndex + 1,
                roll: 1,
                purpose: "\(purpose).group.\(groupIndex + 1)"
            )
            if roll < group.count {
                return group
            }
        }

        return groups.last
    }

    private func selectPhysicalTarget(
        for actingSide: BattleSide,
        purpose: String,
        actionNumber: Int,
        excluding excludedIndices: Set<Int> = []
    ) -> Int? {
        guard let group = selectPhysicalTargetGroup(
            for: actingSide,
            purpose: purpose,
            actionNumber: actionNumber,
            excluding: excludedIndices
        ) else {
            return nil
        }

        return randomChoice(
            from: group,
            turn: currentTurn,
            action: actionNumber,
            subaction: group.count,
            purpose: "\(purpose).fallback"
        )
    }

    private func adjacentPhysicalTarget(
        to targetIndex: Int,
        excluding excludedIndices: Set<Int> = [],
        purpose: String,
        actionNumber: Int
    ) -> Int? {
        let target = combatants[targetIndex]
        let candidates = combatants.indices
            .filter {
                $0 != targetIndex
                    && !excludedIndices.contains($0)
                    && combatants[$0].side == target.side
                    && combatants[$0].isAlive
                    && abs(combatants[$0].formationIndex - target.formationIndex) == 1
            }
            .sorted { combatants[$0].formationIndex < combatants[$1].formationIndex }
        return randomChoice(
            from: candidates,
            turn: currentTurn,
            action: actionNumber,
            subaction: 95,
            purpose: purpose
        )
    }

    private func randomAdditionalPhysicalTarget(
        to targetIndex: Int,
        excluding excludedIndices: Set<Int> = [],
        purpose: String,
        actionNumber: Int
    ) -> Int? {
        let target = combatants[targetIndex]
        let candidates = combatants.indices.filter {
            $0 != targetIndex
                && !excludedIndices.contains($0)
                && combatants[$0].side == target.side
                && combatants[$0].isAlive
        }
        return randomChoice(
            from: candidates,
            turn: currentTurn,
            action: actionNumber,
            subaction: 94,
            purpose: purpose
        )
    }

    private func attackTargetIndices(for queuedAction: QueuedAction) -> [Int] {
        if let fixedTargetIndices = queuedAction.fixedTargetIndices {
            return fixedTargetIndices.filter { combatants.indices.contains($0) && combatants[$0].isAlive }
        }

        let actor = combatants[queuedAction.actorIndex]
        let isNormalAttack = isNormalAttackAction(queuedAction.recordKind)
        let purpose = "attackTarget.\(actor.id.rawValue).\(queuedAction.recordKind.rawValue)"
        if isNormalAttack,
           let chance = actor.status.actionRuleMaxValue(for: "normalAttackTargetingAllEnemiesChance"),
           uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: 94,
            roll: queuedAction.actorIndex + 1,
            purpose: "\(purpose).allEnemiesChance"
           ) < chance {
            return livingIndices(on: opposingSide(of: actor.side))
        }
        if actor.status.actionRuleMaxValue(for: "normalAttackTargetingAllEnemies") != nil {
            return livingIndices(on: opposingSide(of: actor.side))
        }
        if actor.status.actionRuleMaxValue(for: "normalAttackTargetingFrontRowAll") != nil {
            let targetSide = opposingSide(of: actor.side)
            let frontRow = livingIndices(on: targetSide, rank: .front)
            if !frontRow.isEmpty {
                return frontRow
            }
            let middleRow = livingIndices(on: targetSide, rank: .middle)
            if !middleRow.isEmpty {
                return middleRow
            }
            return livingIndices(on: targetSide, rank: .back)
        }
        guard let primaryTargetIndex = selectPhysicalTarget(
            for: actor.side,
            purpose: purpose,
            actionNumber: currentActionNumber
        ) else {
            return []
        }
        var targetIndices = [primaryTargetIndex]
        if isNormalAttack,
           actor.status.actionRuleMaxValue(for: "normalAttackHitsRandomAdditionalTarget") != nil,
           let additionalTargetIndex = randomAdditionalPhysicalTarget(
            to: primaryTargetIndex,
            excluding: [primaryTargetIndex],
            purpose: "\(purpose).additional",
            actionNumber: currentActionNumber
           ) {
            targetIndices.append(additionalTargetIndex)
        } else if actor.status.actionRuleMaxValue(for: "normalAttackHitsAdjacentTarget") != nil,
           let adjacentTargetIndex = adjacentPhysicalTarget(
            to: primaryTargetIndex,
            excluding: [primaryTargetIndex],
            purpose: "\(purpose).adjacent",
            actionNumber: currentActionNumber
           ) {
            targetIndices.append(adjacentTargetIndex)
        }
        return targetIndices
    }

    private func pursuitCandidates(excluding actorIndex: Int) -> [Int] {
        let actorSide = combatants[actorIndex].side
        return combatants.indices
            .filter {
                $0 != actorIndex
                    && combatants[$0].side == actorSide
                    && combatants[$0].status.interruptKinds.contains(.pursuit)
                    && combatants[$0].canAct
            }
            .sorted(by: compareCombatantPriority)
    }

    private func selectLowHPTarget(
        for actingSide: BattleSide,
        excluding excludedIndices: Set<Int> = []
    ) -> Int? {
        let candidates = livingIndices(on: opposingSide(of: actingSide))
            .filter { !excludedIndices.contains($0) && isLowHP(combatants[$0]) }
        return randomChoice(
            from: candidates,
            turn: currentTurn,
            action: currentActionNumber,
            subaction: 96,
            purpose: "attackTarget.lowHP.\(actingSide.rawValue)"
        )
    }

    private func makeFollowUpAttack(
        actorIndex: Int,
        targetIndex: Int? = nil
    ) -> QueuedAction? {
        if let targetIndex,
           !(combatants.indices.contains(targetIndex) && combatants[targetIndex].isAlive) {
            return nil
        }
        return QueuedAction(
            actorIndex: actorIndex,
            recordKind: .attack,
            fixedTargetIndices: targetIndex.map { [$0] },
            countsAsNormalTurnAction: false,
            consumesSpellCharge: true,
            allowsActionRuleFollowUps: false
        )
    }

    private func usesRandomizedNormalActionOrder() -> Bool {
        combatants.indices.contains {
            combatants[$0].isAlive
                && combatants[$0].status.actionRuleMaxValue(for: "randomizeNormalActionOrder") != nil
        }
    }

    private func livingIndices() -> [Int] {
        livingCombatantIndices
    }

    private func livingIndices(on side: BattleSide) -> [Int] {
        switch side {
        case .ally:
            livingAllyIndices
        case .enemy:
            livingEnemyIndices
        }
    }

    private func livingIndices(on side: BattleSide, rank: FormationRank) -> [Int] {
        switch (side, rank) {
        case (.ally, .front):
            livingAllyFrontIndices
        case (.ally, .middle):
            livingAllyMiddleIndices
        case (.ally, .back):
            livingAllyBackIndices
        case (.enemy, .front):
            livingEnemyFrontIndices
        case (.enemy, .middle):
            livingEnemyMiddleIndices
        case (.enemy, .back):
            livingEnemyBackIndices
        }
    }

    private func opposingSide(of side: BattleSide) -> BattleSide {
        switch side {
        case .ally:
            .enemy
        case .enemy:
            .ally
        }
    }

    private func biasedLuck(_ luck: Int) -> Double {
        let luckValue = Double(max(luck, 0))
        return luckValue / (luckValue + 100)
    }

    private func uniform(
        turn: Int,
        action: Int,
        subaction: Int,
        roll: Int,
        purpose: String
    ) -> Double {
        let randomValue = BattleDeterministicRandom.uniform(
            rootSeed: context.rootSeed,
            floorNumber: context.floorNumber,
            battleNumber: context.battleNumber,
            turnNumber: turn,
            actionNumber: action,
            subactionNumber: subaction,
            rollNumber: roll,
            purpose: purpose
        )
        return randomValue
    }

    private func integer(
        upperBound: Int,
        turn: Int,
        action: Int,
        subaction: Int,
        roll: Int,
        purpose: String
    ) -> Int {
        guard upperBound > 0 else {
            return 0
        }
        return Int((uniform(
            turn: turn,
            action: action,
            subaction: subaction,
            roll: roll,
            purpose: purpose
        ) * Double(upperBound)).rounded(.down))
    }

    private func randomChoice<T>(
        from values: [T],
        turn: Int,
        action: Int,
        subaction: Int,
        purpose: String
    ) -> T? {
        guard !values.isEmpty else {
            return nil
        }
        let index = min(
            integer(
                upperBound: values.count,
                turn: turn,
                action: action,
                subaction: subaction,
                roll: 1,
                purpose: purpose
            ),
            values.count - 1
        )
        return values[index]
    }

    private func priorityKey(for combatantIndex: Int) -> BattleActionOrderPriorityKey {
        let combatant = combatants[combatantIndex]
        return BattleActionOrderPriorityKey(
            initiativeScore: initiativeScores[combatantIndex],
            luck: combatant.status.baseStats.luck,
            agility: combatant.status.baseStats.agility,
            formationIndex: combatant.formationIndex
        )
    }
}

nonisolated private struct RuntimeCombatant {
    let id: BattleCombatantID
    let name: String
    let side: BattleSide
    let imageAssetID: String?
    let level: Int
    let formationIndex: Int
    let initialHP: Int
    var currentHP: Int
    let status: CharacterStatus
    let actionRates: CharacterActionRates
    let actionPriority: [BattleActionKind]
    var spellCharges: [Int: Int]
    var ailments: Set<BattleAilment> = []
    var isDefending = false
    var attackBuffActive = false
    var magicBuffActive = false
    var physicalBarrierActive = false
    var magicBarrierActive = false
    var extraHPBarrier = 0
    var breathUsesRemaining: Int
    var attackSpellHitCount = 0
    var physicalDamagePctAddFromDamageTaken = 0.0
    var nextNormalAttackPhysicalDamageMultiplier = 1.0
    var hasUsedFirstNormalAttack = false
    var hasUsedReviveOnceOnFirstDefeat = false
    var hasUsedSurviveFirstDefeat = false
    var hasUsedTurnOneExtraAction = false

    init(
        id: BattleCombatantID,
        name: String,
        side: BattleSide,
        imageAssetID: String?,
        level: Int,
        formationIndex: Int,
        currentHP: Int,
        status: CharacterStatus,
        actionRates: CharacterActionRates,
        actionPriority: [BattleActionKind]
    ) {
        self.id = id
        self.name = name
        self.side = side
        self.imageAssetID = imageAssetID
        self.level = level
        self.formationIndex = formationIndex
        self.initialHP = currentHP
        self.currentHP = currentHP
        self.status = status
        self.actionRates = actionRates
        self.actionPriority = actionPriority
        self.spellCharges = Dictionary(uniqueKeysWithValues: status.spellIds.map { ($0, 1) })
        self.breathUsesRemaining = max(
            Int(status.actionRuleMaxValue(for: "breathRepeatCount") ?? 1),
            1
        )
    }

    var isAlive: Bool {
        currentHP > 0
    }

    var canAct: Bool {
        isAlive && !ailments.contains(.sleep)
    }
}

nonisolated private struct QueuedAction {
    let actorIndex: Int
    let recordKind: BattleLogActionKind
    var spellId: Int? = nil
    var fixedTargetIndices: [Int]? = nil
    var attackPowerMultiplier = 1.0
    var attackCountMultiplier = 1.0
    var criticalAllowed = true
    var canTriggerInterrupts = true
    var countsAsNormalTurnAction = false
    var consumesSpellCharge = true
    var allowsActionRuleFollowUps = true

    var interruptPriority: Int {
        switch recordKind {
        case .rescue:
            0
        case .counter:
            1
        case .extraAttack, .attack, .unarmedRepeat:
            2
        case .pursuit:
            3
        case .breath, .recoverySpell, .attackSpell, .defend:
            99
        }
    }

    func asFollowUp() -> QueuedAction {
        var action = self
        action.countsAsNormalTurnAction = false
        action.allowsActionRuleFollowUps = false
        return action
    }
}

nonisolated private struct ResolvedAction {
    let record: BattleActionRecord
    let generatedInterrupts: [QueuedAction]
}

nonisolated private enum FormationRank {
    case front
    case middle
    case back
}

nonisolated private enum BattleDeterministicRandom {
    static func uniform(
        rootSeed: UInt64,
        floorNumber: Int,
        battleNumber: Int,
        turnNumber: Int,
        actionNumber: Int,
        subactionNumber: Int,
        rollNumber: Int,
        purpose: String
    ) -> Double {
        var state = rootSeed
        state = mix(state ^ UInt64(bitPattern: Int64(floorNumber)))
        state = mix(state ^ UInt64(bitPattern: Int64(battleNumber)))
        state = mix(state ^ UInt64(bitPattern: Int64(turnNumber)))
        state = mix(state ^ UInt64(bitPattern: Int64(actionNumber)))
        state = mix(state ^ UInt64(bitPattern: Int64(subactionNumber)))
        state = mix(state ^ UInt64(bitPattern: Int64(rollNumber)))
        state = mix(state ^ stringHash(purpose))
        return Double(state >> 11) / Double(1 << 53)
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    private static func stringHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

nonisolated private extension Int {
    func isOutOfBounds<T>(in array: [T]) -> Bool {
        self < 0 || self >= array.count
    }
}
