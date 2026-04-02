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

nonisolated private struct BattleResolutionEngine {
    private let context: BattleContext
    private let masterData: MasterData
    private let spellLookup: [Int: MasterData.Spell]
    private var combatants: [RuntimeCombatant]
    private var turns: [BattleTurnRecord] = []
    private var currentTurn = 0
    private var currentActionNumber = 0
    private var initiativeScores: [Double]

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
        self.combatants = []
        self.initiativeScores = []

        for (formationIndex, character) in partyMembers.enumerated() {
            combatants.append(
                RuntimeCombatant(
                    id: BattleCombatantID(rawValue: "character:\(character.character.characterId)"),
                    name: character.character.name,
                    side: .ally,
                    imageAssetID: character.character.portraitAssetName,
                    level: character.character.level,
                    formationIndex: formationIndex,
                    currentHP: min(max(character.character.currentHP, 0), character.status.maxHP),
                    status: character.status,
                    actionRates: character.character.autoBattleSettings.rates,
                    actionPriority: character.character.autoBattleSettings.priority
                )
            )
        }

        for (formationIndex, enemySeed) in enemies.enumerated() {
            guard let enemy = masterData.enemies.first(where: { $0.id == enemySeed.enemyId }) else {
                throw SingleBattleError.invalidEnemy(enemySeed.enemyId)
            }

            let baseStats = CharacterBaseStats(
                vitality: enemy.baseStats.vitality,
                strength: enemy.baseStats.strength,
                mind: enemy.baseStats.mind,
                intelligence: enemy.baseStats.intelligence,
                agility: enemy.baseStats.agility,
                luck: enemy.baseStats.luck
            )
            guard let status = CharacterDerivedStatsCalculator.status(
                baseStats: baseStats,
                jobId: enemy.jobId,
                level: enemySeed.level,
                skillIds: enemy.skillIds,
                masterData: masterData
            ) else {
                throw SingleBattleError.invalidEnemy(enemy.id)
            }

            combatants.append(
                RuntimeCombatant(
                    id: BattleCombatantID(rawValue: "enemy:\(enemy.id):\(formationIndex + 1)"),
                    name: enemy.name,
                    side: .enemy,
                    imageAssetID: nil,
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
    }

    mutating func resolve() throws -> SingleBattleResult {
        var outcome = currentOutcomeIfFinished()

        while outcome == nil && currentTurn < 20 {
            currentTurn += 1
            resetTurnState()

            let turnActions = buildTurnActions()
            var actionQueue = turnActions
            var resolvedActions: [BattleActionRecord] = []

            while !actionQueue.isEmpty {
                let queuedAction = actionQueue.removeFirst()
                guard combatants[queuedAction.actorIndex].canAct else {
                    continue
                }

                currentActionNumber += 1
                if let actionRecord = resolve(queuedAction) {
                    resolvedActions.append(actionRecord.record)
                    if !actionRecord.generatedInterrupts.isEmpty {
                        let sortedInterrupts = sortInterrupts(actionRecord.generatedInterrupts)
                        actionQueue.insert(contentsOf: sortedInterrupts, at: 0)
                    }
                }

                if let immediateOutcome = currentOutcomeIfFinished() {
                    outcome = immediateOutcome
                    actionQueue.removeAll()
                }
            }

            resolveEndOfTurnAilments()
            turns.append(BattleTurnRecord(turnNumber: currentTurn, actions: resolvedActions))
            outcome = outcome ?? currentOutcomeIfFinished()
        }

        let finalOutcome = outcome ?? .draw
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
            initiativeScores[index] = combatants[index].canAct ? actionOrderScore(for: index) : .leastNonzeroMagnitude
        }
    }

    private mutating func buildTurnActions() -> [QueuedAction] {
        let actingIndices = combatants.indices.filter { combatants[$0].canAct }
        let orderedIndices = actingIndices.sorted(by: compareCombatantPriority)
        return orderedIndices.map { selectNormalAction(for: $0) }
    }

    private mutating func selectNormalAction(for actorIndex: Int) -> QueuedAction {
        let actor = combatants[actorIndex]

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
                return QueuedAction(actorIndex: actorIndex, recordKind: .breath)
            case .attack:
                return QueuedAction(actorIndex: actorIndex, recordKind: .attack)
            case .recoverySpell:
                if let spellId = selectSpell(
                    for: actorIndex,
                    category: .recovery,
                    purposePrefix: "normalRecoverySpell"
                ) {
                    return QueuedAction(
                        actorIndex: actorIndex,
                        recordKind: .recoverySpell,
                        spellId: spellId
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
                        spellId: spellId
                    )
                }
            }
        }

        return QueuedAction(actorIndex: actorIndex, recordKind: .defend)
    }

    private mutating func resolve(_ queuedAction: QueuedAction) -> ResolvedAction? {
        switch queuedAction.recordKind {
        case .defend:
            combatants[queuedAction.actorIndex].isDefending = true
            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: combatants[queuedAction.actorIndex].id,
                    actionKind: .defend,
                    actionRef: nil,
                    actionFlags: [],
                    targetIds: [],
                    results: []
                ),
                generatedInterrupts: []
            )
        case .breath:
            return resolveBreath(queuedAction)
        case .attack:
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

        let actor = combatants[queuedAction.actorIndex]
        var results: [BattleTargetResult] = []
        for (subactionNumber, targetIndex) in targetIndices.enumerated() {
            let guarded = combatants[targetIndex].isDefending
            let damage = damageValue(
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
                guarded: guarded
            )
            let targetResult = applyDamage(
                damage,
                to: targetIndex,
                guarded: guarded,
                purposeSubaction: subactionNumber + 1
            )
            results.append(targetResult)
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
            generatedInterrupts: []
        )
    }

    private mutating func resolveAttack(_ queuedAction: QueuedAction) -> ResolvedAction? {
        guard let targetIndex = selectPhysicalTarget(
            for: combatants[queuedAction.actorIndex].side,
            purpose: "attackTarget.\(combatants[queuedAction.actorIndex].id.rawValue).\(queuedAction.recordKind.rawValue)",
            actionNumber: currentActionNumber
        ) else {
            return nil
        }

        let actorIndex = queuedAction.actorIndex
        let actor = combatants[actorIndex]
        let actionKind = queuedAction.recordKind
        let attackCount = adjustedAttackCount(for: actorIndex, multiplier: queuedAction.attackCountMultiplier)
        let allowsCritical = queuedAction.criticalAllowed
        let criticalTriggered = allowsCritical ? criticalDidTrigger(for: actorIndex) : false
        var hitMultiplier = 0.0
        var currentTargetAlive = combatants[targetIndex].isAlive

        for hitIndex in 0..<attackCount where currentTargetAlive {
            if didHit(attackerIndex: actorIndex, defenderIndex: targetIndex, subactionNumber: hitIndex + 1) {
                hitMultiplier += pow(0.5, Double(hitIndex))
            }
            currentTargetAlive = combatants[targetIndex].isAlive
        }

        let targetId = combatants[targetIndex].id
        let actionFlags = criticalTriggered ? [BattleActionFlag.critical] : []

        if hitMultiplier == 0 {
            let generatedInterrupts = queuedAction.canTriggerInterrupts
                ? interruptActions(
                    after: queuedAction,
                    targetIndex: targetIndex,
                    targetWasDefeated: false
                )
                : []
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
        let guarded = target.isDefending
        var multiplier = actor.status.battleDerivedStats.physicalDamageMultiplier
        multiplier *= formationMultiplier(for: actor)
        multiplier *= weaponDamageMultiplier(for: actor)
        multiplier *= queuedAction.attackPowerMultiplier
        if actor.attackBuffActive {
            multiplier *= 1.5
        }
        if criticalTriggered {
            multiplier *= actor.status.battleDerivedStats.criticalDamageMultiplier
        }

        let basePower = Double(max(actor.status.battleStats.physicalAttack - target.status.battleStats.physicalDefense, 0))
            * hitMultiplier
        let damage = damageValue(
            basePower: basePower,
            multiplier: multiplier,
            resistance: target.status.battleDerivedStats.physicalResistanceMultiplier,
            barrierMultiplier: target.physicalBarrierActive ? 0.5 : 1.0,
            guarded: guarded
        )
        let targetResult = applyDamage(
            damage,
            to: targetIndex,
            guarded: guarded,
            purposeSubaction: 1
        )

        var generatedInterrupts: [QueuedAction] = []
        if queuedAction.canTriggerInterrupts {
            generatedInterrupts = interruptActions(
                after: queuedAction,
                targetIndex: targetIndex,
                targetWasDefeated: targetResult.flags.contains(.defeated)
            )
        }

        return ResolvedAction(
            record: BattleActionRecord(
                actorId: actor.id,
                actionKind: actionKind,
                actionRef: nil,
                actionFlags: actionFlags,
                targetIds: [targetId],
                results: [targetResult]
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
                        * combatants[actorIndex].status.battleDerivedStats.magicDamageMultiplier
                        * (spell.multiplier ?? 1.0)
                    ).rounded()
                ),
                1
            )
            let results = targetIndices.map { targetIndex in
                applyHeal(healValue, to: targetIndex)
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
            return ResolvedAction(
                record: BattleActionRecord(
                    actorId: actorId,
                    actionKind: .recoverySpell,
                    actionRef: spellId,
                    actionFlags: [],
                    targetIds: [combatants[targetIndex].id],
                    results: [
                        BattleTargetResult(
                            targetId: combatants[targetIndex].id,
                            resultKind: .ailmentRemoved,
                            value: nil,
                            statusId: removedAilment.rawValue,
                            flags: []
                        )
                    ]
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
        guard consumeSpell(spellId, for: queuedAction.actorIndex) else {
            return nil
        }

        let actorIndex = queuedAction.actorIndex
        let actorId = combatants[actorIndex].id

        switch spell.kind {
        case .damage:
            let targetIndices = attackSpellTargets(
                for: spell,
                actorIndex: actorIndex,
                actionNumber: currentActionNumber
            )
            guard !targetIndices.isEmpty else {
                return nil
            }

            let actor = combatants[actorIndex]
            let results = targetIndices.enumerated().flatMap { offset, targetIndex in
                let target = combatants[targetIndex]
                let guarded = target.isDefending
                let multiplier = actor.status.battleDerivedStats.magicDamageMultiplier
                    * actor.status.battleDerivedStats.spellDamageMultiplier
                    * actor.status.spellDamageMultiplier(for: spell.id)
                    * (actor.magicBuffActive ? 1.5 : 1.0)
                    * (spell.multiplier ?? 1.0)
                let damage = damageValue(
                    basePower: Double(
                        max(actor.status.battleStats.magic - target.status.battleStats.magicDefense, 0)
                    ),
                    multiplier: multiplier,
                    resistance: target.status.battleDerivedStats.magicResistanceMultiplier
                        * target.status.magicResistanceMultiplier(for: spell.id),
                    barrierMultiplier: target.magicBarrierActive ? 0.5 : 1.0,
                    guarded: guarded
                )
                let damageResult = applyDamage(
                    damage,
                    to: targetIndex,
                    guarded: guarded,
                    purposeSubaction: offset + 1
                )
                var targetResults = [damageResult]
                if let ailmentResult = applySpellAilmentIfNeeded(
                    spell,
                    from: actorIndex,
                    to: targetIndex,
                    subactionNumber: offset + 1
                ) {
                    targetResults.append(ailmentResult)
                }
                return targetResults
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
                generatedInterrupts: []
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
        guard let fallenTargetIndices = queuedAction.fixedTargetIndices else {
            return nil
        }
        let stillDefeatedTargets = fallenTargetIndices.filter { !$0.isOutOfBounds(in: combatants) && !combatants[$0].isAlive }
        guard !stillDefeatedTargets.isEmpty,
              combatants[queuedAction.actorIndex].canAct else {
            return nil
        }

        guard let spellId = selectRescueSpell(for: queuedAction.actorIndex),
              let spell = spellLookup[spellId],
              consumeSpell(spellId, for: queuedAction.actorIndex) else {
            return nil
        }

        if spell.kind == .heal && spell.targetCount == 0 {
            let healValue = max(
                Int(
                    (
                        Double(combatants[queuedAction.actorIndex].status.battleStats.healing)
                        * combatants[queuedAction.actorIndex].status.battleDerivedStats.magicDamageMultiplier
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
                        * combatants[queuedAction.actorIndex].status.battleDerivedStats.magicDamageMultiplier
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

    private mutating func interruptActions(
        after queuedAction: QueuedAction,
        targetIndex: Int,
        targetWasDefeated: Bool
    ) -> [QueuedAction] {
        let actorIndex = queuedAction.actorIndex
        var queuedInterrupts: [QueuedAction] = []

        if targetWasDefeated {
            let rescueHolders = combatants.indices.filter { index in
                combatants[index].side == combatants[targetIndex].side
                    && combatants[index].canAct
                    && combatants[index].status.interruptKinds.contains(.rescue)
                    && selectRescueSpell(for: index) != nil
            }

            for rescuerIndex in rescueHolders {
                let roll = uniform(
                    turn: currentTurn,
                    action: currentActionNumber,
                    subaction: 1,
                    roll: rescuerIndex + 1,
                    purpose: "interrupt.rescue.\(combatants[rescuerIndex].id.rawValue)"
                )
                if roll < probability(for: .recoverySpell, rates: combatants[rescuerIndex].actionRates) {
                    queuedInterrupts.append(
                        QueuedAction(
                            actorIndex: rescuerIndex,
                            recordKind: .rescue,
                            fixedTargetIndices: [targetIndex],
                            criticalAllowed: false,
                            canTriggerInterrupts: false
                        )
                    )
                }
            }
        }

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
            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: actorIndex + 1,
                purpose: "interrupt.extraAttack.\(combatants[actorIndex].id.rawValue)"
            )
            if roll < 0.3 {
                queuedInterrupts.append(
                    QueuedAction(
                        actorIndex: actorIndex,
                        recordKind: .extraAttack,
                        attackPowerMultiplier: 0.5,
                        attackCountMultiplier: 0.3,
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
                        recordKind: .attack,
                        criticalAllowed: true,
                        canTriggerInterrupts: false
                    )
                )
            }
        }

        if let pursuingAllyIndex = highestPriorityPursuer(excluding: actorIndex),
           combatants[pursuingAllyIndex].canAct {
            let roll = uniform(
                turn: currentTurn,
                action: currentActionNumber,
                subaction: 1,
                roll: pursuingAllyIndex + 1,
                purpose: "interrupt.pursuit.\(combatants[pursuingAllyIndex].id.rawValue)"
            )
            if roll < 0.3 {
                queuedInterrupts.append(
                    QueuedAction(
                        actorIndex: pursuingAllyIndex,
                        recordKind: .pursuit,
                        attackPowerMultiplier: 0.5,
                        attackCountMultiplier: 0.3,
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
    }

    private func currentOutcomeIfFinished() -> BattleOutcome? {
        let livingAllies = combatants.contains { $0.side == .ally && $0.isAlive }
        let livingEnemies = combatants.contains { $0.side == .enemy && $0.isAlive }

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
        let actionSpeed = Double(actor.status.baseStats.agility)
            * actor.status.battleDerivedStats.actionSpeedMultiplier
        return actionSpeed + randomAdjustment
    }

    private func compareCombatantPriority(_ lhs: Int, _ rhs: Int) -> Bool {
        let lhsScore = initiativeScores[lhs]
        let rhsScore = initiativeScores[rhs]
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        let lhsCombatant = combatants[lhs]
        let rhsCombatant = combatants[rhs]
        if lhsCombatant.status.baseStats.luck != rhsCombatant.status.baseStats.luck {
            return lhsCombatant.status.baseStats.luck > rhsCombatant.status.baseStats.luck
        }
        if lhsCombatant.status.baseStats.agility != rhsCombatant.status.baseStats.agility {
            return lhsCombatant.status.baseStats.agility > rhsCombatant.status.baseStats.agility
        }
        return lhsCombatant.formationIndex < rhsCombatant.formationIndex
    }

    private func sortInterrupts(_ actions: [QueuedAction]) -> [QueuedAction] {
        actions.sorted { lhs, rhs in
            if lhs.interruptPriority != rhs.interruptPriority {
                return lhs.interruptPriority < rhs.interruptPriority
            }
            return compareCombatantPriority(lhs.actorIndex, rhs.actorIndex)
        }
    }

    private func didHit(attackerIndex: Int, defenderIndex: Int, subactionNumber: Int) -> Bool {
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

        let hitLuckBias = biasedLuck(attacker.status.baseStats.luck)
        let evadeLuckBias = biasedLuck(defender.status.baseStats.luck)
        let hitRoll = (1 - hitLuckBias) * u1 + hitLuckBias * max(u1, u2)
        let evadeRoll = (1 - evadeLuckBias) * u3 + evadeLuckBias * max(u3, u4)
        let finalAccuracy = Double(attacker.status.battleStats.accuracy) + (hitRoll - 0.5) * 14
        let finalEvasion = Double(defender.status.battleStats.evasion) + (evadeRoll - 0.5) * 14
        let delta = finalAccuracy - finalEvasion
        let curveWidth = 0.8 * pow(Double(max(attacker.level, 1)), 1)
        let rawHitRate = 0.5 + delta / (2 * curveWidth)
        let hitRate = min(max(rawHitRate, 0.10), 0.90)
        return uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: subactionNumber,
            roll: 5,
            purpose: "hit.judge.\(attacker.id.rawValue).\(defender.id.rawValue)"
        ) < hitRate
    }

    private func criticalDidTrigger(for attackerIndex: Int) -> Bool {
        let attacker = combatants[attackerIndex]
        let rawRate = attacker.status.isUnarmed
            ? Double(attacker.status.battleStats.criticalRate) * 1.5
            : Double(attacker.status.battleStats.criticalRate)
        let criticalRate = min(rawRate, 75) / 100
        return uniform(
            turn: currentTurn,
            action: currentActionNumber,
            subaction: 1,
            roll: attackerIndex + 1,
            purpose: "critical.\(attacker.id.rawValue)"
        ) < criticalRate
    }

    private func damageValue(
        basePower: Double,
        multiplier: Double,
        resistance: Double,
        barrierMultiplier: Double,
        guarded: Bool
    ) -> Int {
        let guardedMultiplier = guarded ? 0.5 : 1.0
        let value = Int(
            (basePower * multiplier * resistance * barrierMultiplier * guardedMultiplier)
                .rounded()
        )
        return max(value, 1)
    }

    private mutating func applyDamage(
        _ value: Int,
        to targetIndex: Int,
        guarded: Bool,
        purposeSubaction: Int
    ) -> BattleTargetResult {
        let wasAlive = combatants[targetIndex].isAlive
        combatants[targetIndex].currentHP = max(combatants[targetIndex].currentHP - value, 0)
        var flags: [BattleTargetResultFlag] = guarded ? [.guarded] : []
        if wasAlive && !combatants[targetIndex].isAlive {
            flags.append(.defeated)
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
        let restoredHP = fullRestore
            ? combatants[targetIndex].status.maxHP
            : min(combatants[targetIndex].currentHP + value, combatants[targetIndex].status.maxHP)
        combatants[targetIndex].currentHP = restoredHP
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
        combatants[targetIndex].currentHP = restoredHP
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
        guard roll < statusChance else {
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
        actionNumber: Int
    ) -> [Int] {
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

    private func selectPhysicalTarget(
        for actingSide: BattleSide,
        purpose: String,
        actionNumber: Int
    ) -> Int? {
        let candidateGroups = [
            livingIndices(on: opposingSide(of: actingSide), rank: .front),
            livingIndices(on: opposingSide(of: actingSide), rank: .middle),
            livingIndices(on: opposingSide(of: actingSide), rank: .back)
        ]
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
                return group[roll]
            }
        }

        return randomChoice(
            from: groups.last ?? [],
            turn: currentTurn,
            action: actionNumber,
            subaction: groups.count,
            purpose: "\(purpose).fallback"
        )
    }

    private func highestPriorityPursuer(excluding actorIndex: Int) -> Int? {
        let actorSide = combatants[actorIndex].side
        return combatants.indices
            .filter {
                $0 != actorIndex
                    && combatants[$0].side == actorSide
                    && combatants[$0].status.interruptKinds.contains(.pursuit)
                    && combatants[$0].canAct
            }
            .sorted(by: compareCombatantPriority)
            .first
    }

    private func livingIndices() -> [Int] {
        combatants.indices.filter { combatants[$0].isAlive }
    }

    private func livingIndices(on side: BattleSide) -> [Int] {
        combatants.indices.filter { combatants[$0].side == side && combatants[$0].isAlive }
    }

    private func livingIndices(on side: BattleSide, rank: FormationRank) -> [Int] {
        combatants.indices.filter {
            combatants[$0].side == side
                && combatants[$0].isAlive
                && formationRank(for: combatants[$0].formationIndex) == rank
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

    var interruptPriority: Int {
        switch recordKind {
        case .rescue:
            0
        case .counter:
            1
        case .extraAttack, .attack:
            2
        case .pursuit:
            3
        case .breath, .recoverySpell, .attackSpell, .defend:
            99
        }
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
