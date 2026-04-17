// Resolves deterministic exploration progress, rewards, and completion from a stored run session.

import Foundation

nonisolated struct ExplorationMemberStatusCacheEntry: Sendable {
    let level: Int
    let status: CharacterStatus
}

nonisolated enum ExplorationResolver {
    static func plan(
        session: RunSessionRecord,
        masterData: MasterData,
        cachedStatuses: inout [Int: ExplorationMemberStatusCacheEntry]
    ) throws -> RunSessionRecord {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == session.labyrinthId }) else {
            throw ExplorationError.invalidLabyrinth(labyrinthId: session.labyrinthId)
        }
        let difficultyMultiplier = masterData.explorationDifficultyTitle(id: session.selectedDifficultyTitleId)?
            .positiveMultiplier ?? 1.0

        let battlePlans = buildBattlePlans(
            for: session,
            labyrinth: labyrinth,
            difficultyMultiplier: difficultyMultiplier
        )
        let interval = session.progressIntervalSeconds(baseIntervalSeconds: labyrinth.progressIntervalSeconds)

        var currentPartyMembers = try preparedPartyMembers(
            from: session.memberSnapshots,
            memberCharacterIds: session.memberCharacterIds,
            currentPartyHPs: session.memberSnapshots.map(\.currentHP),
            experienceRewards: [],
            masterData: masterData
        )
        var completedBattleCount = 0
        var currentPartyHPs = session.memberSnapshots.map(\.currentHP)
        var battleLogs: [ExplorationBattleLog] = []
        var goldBuffer = 0
        var experienceRewards: [ExplorationExperienceReward] = []
        var dropRewards: [ExplorationDropReward] = []
        var completion: RunCompletionRecord?

        while completedBattleCount < battlePlans.count, completion == nil {
            let battlePlan = battlePlans[completedBattleCount]
            let battleContext = BattleContext(
                runId: session.runSessionID,
                rootSeed: session.rootSeed,
                floorNumber: battlePlan.floorNumber,
                battleNumber: battlePlan.battleNumber
            )
            let resolvedMembers = try resolvedPartyMembers(
                from: currentPartyMembers,
                masterData: masterData,
                cachedStatuses: &cachedStatuses
            )
            let result = try SingleBattleResolver.resolve(
                context: battleContext,
                partyMembers: resolvedMembers,
                enemies: battlePlan.enemies,
                masterData: masterData
            )
            completedBattleCount += 1
            currentPartyHPs = result.partyRemainingHPs
            currentPartyMembers = updatedPartyMembers(
                from: currentPartyMembers,
                currentPartyHPs: currentPartyHPs
            )
            battleLogs.append(
                ExplorationBattleLog(
                    battleRecord: result.battleRecord,
                    combatants: result.combatants
                )
            )

            switch result.result {
            case .victory:
                let rewards = resolveRewards(
                    rewardContext: makeRewardContext(
                        from: session,
                        partyMembers: resolvedMembers,
                        masterData: masterData
                    ),
                    enemySeeds: battlePlan.enemies,
                    result: result,
                    floorNumber: battlePlan.floorNumber,
                    battleNumber: battlePlan.battleNumber,
                    rootSeed: session.rootSeed,
                    masterData: masterData
                )
                goldBuffer += rewards.gold
                experienceRewards = merged(
                    existing: experienceRewards,
                    additions: rewards.experienceRewards
                )
                dropRewards.append(contentsOf: rewards.dropRewards)
                currentPartyMembers = applyExperienceRewards(
                    rewards.experienceRewards,
                    to: currentPartyMembers,
                    masterData: masterData
                )

                if completedBattleCount == battlePlans.count {
                    completion = RunCompletionRecord(
                        completedAt: completionDate(
                            startedAt: session.startedAt,
                            interval: interval,
                            completedBattleCount: completedBattleCount
                        ),
                        reason: .cleared,
                        gold: goldBuffer,
                        experienceRewards: experienceRewards,
                        dropRewards: dropRewards
                    )
                }
            case .defeat:
                completion = RunCompletionRecord(
                    completedAt: completionDate(
                        startedAt: session.startedAt,
                        interval: interval,
                        completedBattleCount: completedBattleCount
                    ),
                    reason: .defeated,
                    gold: goldBuffer,
                    experienceRewards: experienceRewards,
                    dropRewards: dropRewards
                )
            case .draw:
                completion = RunCompletionRecord(
                    completedAt: completionDate(
                        startedAt: session.startedAt,
                        interval: interval,
                        completedBattleCount: completedBattleCount
                    ),
                    reason: .draw,
                    gold: goldBuffer,
                    experienceRewards: experienceRewards,
                    dropRewards: dropRewards
                )
            }
        }

        return RunSessionRecord(
            partyRunId: session.partyRunId,
            partyId: session.partyId,
            labyrinthId: session.labyrinthId,
            selectedDifficultyTitleId: session.selectedDifficultyTitleId,
            targetFloorNumber: session.targetFloorNumber,
            startedAt: session.startedAt,
            rootSeed: session.rootSeed,
            memberSnapshots: session.memberSnapshots,
            memberCharacterIds: session.memberCharacterIds,
            completedBattleCount: completedBattleCount,
            currentPartyHPs: currentPartyHPs,
            memberExperienceMultipliers: session.memberExperienceMultipliers,
            progressIntervalMultiplier: session.progressIntervalMultiplier,
            goldMultiplier: session.goldMultiplier,
            rareDropMultiplier: session.rareDropMultiplier,
            partyAverageLuck: session.partyAverageLuck,
            latestBattleFloorNumber: battleLogs.last?.battleRecord.floorNumber,
            latestBattleNumber: battleLogs.last?.battleRecord.battleNumber,
            latestBattleOutcome: battleLogs.last?.battleRecord.result,
            battleLogs: battleLogs,
            goldBuffer: goldBuffer,
            experienceRewards: experienceRewards,
            dropRewards: dropRewards,
            completion: completion
        )
    }

    static func reveal(
        session: RunSessionRecord,
        upTo currentDate: Date,
        masterData: MasterData
    ) throws -> RunSessionRecord {
        guard session.completion == nil else {
            return session
        }

        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == session.labyrinthId }) else {
            throw ExplorationError.invalidLabyrinth(labyrinthId: session.labyrinthId)
        }

        let interval = session.progressIntervalSeconds(baseIntervalSeconds: labyrinth.progressIntervalSeconds)
        let revealedBattleCount = min(
            max(Int(currentDate.timeIntervalSince(session.startedAt) / interval), 0),
            session.battleLogs.count
        )
        guard revealedBattleCount > session.completedBattleCount else {
            return session
        }

        let latestBattleLog = revealedBattleCount > 0 ? session.battleLogs[revealedBattleCount - 1] : nil
        let latestPartyHPs = latestBattleLog.map { battleLog in
            battleLog.combatants
                .filter { $0.side == .ally }
                .sorted { $0.formationIndex < $1.formationIndex }
                .map(\.remainingHP)
        } ?? session.memberSnapshots.map(\.currentHP)
        let completionReason: RunCompletionReason = switch latestBattleLog?.battleRecord.result ?? .draw {
        case .victory:
            .cleared
        case .defeat:
            .defeated
        case .draw:
            .draw
        }

        return RunSessionRecord(
            partyRunId: session.partyRunId,
            partyId: session.partyId,
            labyrinthId: session.labyrinthId,
            selectedDifficultyTitleId: session.selectedDifficultyTitleId,
            targetFloorNumber: session.targetFloorNumber,
            startedAt: session.startedAt,
            rootSeed: session.rootSeed,
            memberSnapshots: session.memberSnapshots,
            memberCharacterIds: session.memberCharacterIds,
            completedBattleCount: revealedBattleCount,
            currentPartyHPs: latestPartyHPs,
            memberExperienceMultipliers: session.memberExperienceMultipliers,
            progressIntervalMultiplier: session.progressIntervalMultiplier,
            goldMultiplier: session.goldMultiplier,
            rareDropMultiplier: session.rareDropMultiplier,
            partyAverageLuck: session.partyAverageLuck,
            latestBattleFloorNumber: latestBattleLog?.battleRecord.floorNumber,
            latestBattleNumber: latestBattleLog?.battleRecord.battleNumber,
            latestBattleOutcome: latestBattleLog?.battleRecord.result,
            battleLogs: session.battleLogs,
            goldBuffer: session.goldBuffer,
            experienceRewards: session.experienceRewards,
            dropRewards: session.dropRewards,
            completion: revealedBattleCount == session.battleLogs.count
                ? RunCompletionRecord(
                    completedAt: completionDate(
                        startedAt: session.startedAt,
                        interval: interval,
                        completedBattleCount: revealedBattleCount
                    ),
                    reason: completionReason,
                    gold: session.goldBuffer,
                    experienceRewards: session.experienceRewards,
                    dropRewards: session.dropRewards
                )
                : nil
        )
    }

    static func rebuildPartyMembersAfterBattle(
        from partyMembers: [CharacterRecord],
        currentPartyHPs: [Int],
        masterData: MasterData,
        cachedStatuses: inout [Int: ExplorationMemberStatusCacheEntry]
    ) throws -> [PartyBattleMember] {
        try resolvedPartyMembers(
            from: updatedPartyMembers(
                from: partyMembers,
                currentPartyHPs: currentPartyHPs
            ),
            masterData: masterData,
            cachedStatuses: &cachedStatuses
        )
    }
}

nonisolated extension ExplorationResolver {
    struct PlannedBattle {
        let floorNumber: Int
        let battleNumber: Int
        let enemies: [BattleEnemySeed]
    }

    struct RewardContext {
        let memberCharacterIds: [Int]
        let memberExperienceMultipliers: [Double]
        let goldMultiplier: Double
        let rareDropMultiplier: Double
        let titleRollCountModifier: Int
        let normalDropJewelizeChance: Double
        let goldPenaltyPerDamageTaken: Double
        let goldGainPctAddOnNormalKill: Double
        let partyAverageLuck: Double
        let defaultTitle: MasterData.Title
        let enemyTitle: MasterData.Title
    }

    struct BattleRewards {
        let gold: Int
        let experienceRewards: [ExplorationExperienceReward]
        let dropRewards: [ExplorationDropReward]
    }

    static func preparedPartyMembers(
        from partyMembers: [CharacterRecord],
        memberCharacterIds: [Int],
        currentPartyHPs: [Int],
        experienceRewards: [ExplorationExperienceReward],
        masterData: MasterData
    ) throws -> [CharacterRecord] {
        guard memberCharacterIds.count == currentPartyHPs.count else {
            throw ExplorationError.invalidParty(partyId: 0)
        }

        let charactersById = Dictionary(uniqueKeysWithValues: partyMembers.map { ($0.characterId, $0) })
        let racesById = Dictionary(uniqueKeysWithValues: masterData.races.map { ($0.id, $0) })
        let experienceByCharacterId = experienceRewards.reduce(into: [Int: Int]()) { partial, reward in
            partial[reward.characterId, default: 0] += reward.experience
        }
        return try memberCharacterIds.enumerated().map { index, characterId in
            guard var character = charactersById[characterId] else {
                throw ExplorationError.invalidRunMember(characterId: characterId)
            }
            character.currentHP = currentPartyHPs[index]
            character = applyAccumulatedExperience(
                to: character,
                additionalExperience: experienceByCharacterId[characterId] ?? 0,
                racesById: racesById
            )
            return character
        }
    }

    static func updatedPartyMembers(
        from partyMembers: [CharacterRecord],
        currentPartyHPs: [Int]
    ) -> [CharacterRecord] {
        partyMembers.enumerated().map { index, member in
            var updatedMember = member
            updatedMember.currentHP = currentPartyHPs[index]
            return updatedMember
        }
    }

    static func applyExperienceRewards(
        _ rewards: [ExplorationExperienceReward],
        to partyMembers: [CharacterRecord],
        masterData: MasterData
    ) -> [CharacterRecord] {
        let experienceByCharacterId = rewards.reduce(into: [Int: Int]()) { partial, reward in
            partial[reward.characterId, default: 0] += reward.experience
        }
        guard !experienceByCharacterId.isEmpty else {
            return partyMembers
        }

        let racesById = Dictionary(uniqueKeysWithValues: masterData.races.map { ($0.id, $0) })
        return partyMembers.map { member in
            applyAccumulatedExperience(
                to: member,
                additionalExperience: experienceByCharacterId[member.characterId] ?? 0,
                racesById: racesById
            )
        }
    }

    static func applyAccumulatedExperience(
        to member: CharacterRecord,
        additionalExperience: Int,
        racesById: [Int: MasterData.Race]
    ) -> CharacterRecord {
        guard additionalExperience > 0 else {
            return member
        }

        var updatedMember = member
        updatedMember.experience += additionalExperience
        if let race = racesById[updatedMember.raceId] {
            updatedMember.level = CharacterLevelProgression.level(
                for: updatedMember.experience,
                levelCap: race.levelCap
            )
        }
        return updatedMember
    }

    static func resolvedPartyMembers(
        from partyMembers: [CharacterRecord],
        masterData: MasterData,
        cachedStatuses: inout [Int: ExplorationMemberStatusCacheEntry]
    ) throws -> [PartyBattleMember] {
        try partyMembers.map { member in
            if let cachedStatus = cachedStatuses[member.characterId], cachedStatus.level == member.level {
                return PartyBattleMember(character: member, status: cachedStatus.status)
            }

            guard let status = CharacterDerivedStatsCalculator.status(
                for: member,
                masterData: masterData
            ) else {
                throw ExplorationError.invalidRunMember(characterId: member.characterId)
            }
            cachedStatuses[member.characterId] = ExplorationMemberStatusCacheEntry(
                level: member.level,
                status: status
            )
            return PartyBattleMember(character: member, status: status)
        }
    }

    static func buildBattlePlans(
        for session: RunSessionRecord,
        labyrinth: MasterData.Labyrinth,
        difficultyMultiplier: Double
    ) -> [PlannedBattle] {
        var battlePlans: [PlannedBattle] = []
        battlePlans.reserveCapacity(
            labyrinth.floors.reduce(0) { partial, floor in
                partial + floor.battleCount
            }
        )

        var globalBattleNumber = 1
        for floor in labyrinth.floors {
            let fixedBattle = floor.fixedBattle ?? []
            let normalBattleCount = max(floor.battleCount - (fixedBattle.isEmpty ? 0 : 1), 0)

            if normalBattleCount > 0 {
                for normalBattleIndex in 1...normalBattleCount {
                    battlePlans.append(
                        PlannedBattle(
                            floorNumber: floor.floorNumber,
                            battleNumber: globalBattleNumber,
                            enemies: resolveEncounterEnemies(
                                for: floor,
                                enemyCountCap: labyrinth.enemyCountCap,
                                difficultyMultiplier: difficultyMultiplier,
                                battleNumber: globalBattleNumber,
                                normalBattleIndex: normalBattleIndex,
                                rootSeed: session.rootSeed
                            )
                        )
                    )
                    globalBattleNumber += 1
                }
            }

            if !fixedBattle.isEmpty {
                battlePlans.append(
                    PlannedBattle(
                        floorNumber: floor.floorNumber,
                        battleNumber: globalBattleNumber,
                        enemies: fixedBattle.map { enemy in
                            BattleEnemySeed(
                                enemyId: enemy.enemyId,
                                level: scaledEnemyLevel(
                                    baseLevel: enemy.level,
                                    difficultyMultiplier: difficultyMultiplier
                                )
                            )
                        }
                    )
                )
                globalBattleNumber += 1
            }
        }

        return battlePlans
    }

    static func resolveEncounterEnemies(
        for floor: MasterData.Floor,
        enemyCountCap: Int,
        difficultyMultiplier: Double,
        battleNumber: Int,
        normalBattleIndex: Int,
        rootSeed: UInt64
    ) -> [BattleEnemySeed] {
        guard !floor.encounters.isEmpty, enemyCountCap > 0 else {
            return []
        }

        let totalWeight = floor.encounters.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return []
        }

        return (1...enemyCountCap).compactMap { enemySlot in
            let purpose = "battle:\(battleNumber):normal:\(normalBattleIndex):slot:\(enemySlot):encounter"
            let roll = ExplorationDeterministicRandom.integer(
                upperBound: totalWeight,
                rootSeed: rootSeed,
                purpose: purpose
            )
            var cumulativeWeight = 0
            for encounter in floor.encounters {
                cumulativeWeight += encounter.weight
                if roll < cumulativeWeight {
                    return BattleEnemySeed(
                        enemyId: encounter.enemyId,
                        level: scaledEnemyLevel(
                            baseLevel: encounter.level,
                            difficultyMultiplier: difficultyMultiplier
                        )
                    )
                }
            }
            return floor.encounters.last.map { encounter in
                BattleEnemySeed(
                    enemyId: encounter.enemyId,
                    level: scaledEnemyLevel(
                        baseLevel: encounter.level,
                        difficultyMultiplier: difficultyMultiplier
                    )
                )
            }
        }
    }

    static func makeRewardContext(
        from session: RunSessionRecord,
        partyMembers: [PartyBattleMember],
        masterData: MasterData
    ) -> RewardContext {
        let defaultTitle = masterData.defaultExplorationDifficultyTitle ?? masterData.titles[0]
        let enemyTitle = masterData.explorationDifficultyTitle(id: session.selectedDifficultyTitleId) ?? defaultTitle
        let skillTable = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        let uniqueSkillIDs = Set(partyMembers.flatMap(\.status.skillIds))

        return RewardContext(
            memberCharacterIds: session.memberCharacterIds,
            memberExperienceMultipliers: session.memberExperienceMultipliers,
            goldMultiplier: session.goldMultiplier,
            rareDropMultiplier: session.rareDropMultiplier,
            titleRollCountModifier: titleRollCountModifier(
                skillIds: uniqueSkillIDs,
                skillTable: skillTable
            ),
            normalDropJewelizeChance: normalDropJewelizeChance(
                skillIds: uniqueSkillIDs,
                skillTable: skillTable
            ),
            goldPenaltyPerDamageTaken: rewardRuleTotal(
                target: "goldPenaltyPerDamageTaken",
                skillIds: uniqueSkillIDs,
                skillTable: skillTable
            ),
            goldGainPctAddOnNormalKill: rewardRuleTotal(
                target: "goldGainPctAddOnNormalKill",
                skillIds: uniqueSkillIDs,
                skillTable: skillTable
            ),
            partyAverageLuck: session.partyAverageLuck,
            defaultTitle: defaultTitle,
            enemyTitle: enemyTitle
        )
    }

    static func resolveRewards(
        rewardContext: RewardContext,
        enemySeeds: [BattleEnemySeed],
        result: SingleBattleResult,
        floorNumber: Int,
        battleNumber: Int,
        rootSeed: UInt64,
        masterData: MasterData
    ) -> BattleRewards {
        let enemyTable = Dictionary(uniqueKeysWithValues: masterData.enemies.map { ($0.id, $0) })
        let itemTable = Dictionary(uniqueKeysWithValues: masterData.items.map { ($0.id, $0) })
        let titlesByAscendingQuality = masterData.titles.sorted {
            $0.positiveMultiplier < $1.positiveMultiplier
        }
        let superRareRateMultiplier = superRareRateMultiplier(for: result)
        // Battle snapshots only know ally formation order, so rewards map surviving allies back
        // through the original party member list before deciding who receives experience.
        let livingCharacterIds = Set(
            result.combatants
                .filter { $0.side == .ally && $0.remainingHP > 0 }
                .sorted { $0.formationIndex < $1.formationIndex }
                .enumerated()
                .compactMap { index, _ in
                    rewardContext.memberCharacterIds.indices.contains(index)
                        ? rewardContext.memberCharacterIds[index]
                        : nil
                }
        )

        // Gold is pooled once per battle, while experience is split evenly first and only then
        // scaled by each surviving member's multiplier.
        let totalBaseGold = enemySeeds.reduce(into: 0) { partial, enemySeed in
            guard let enemy = enemyTable[enemySeed.enemyId] else {
                return
            }
            partial += enemy.goldBaseValue * enemySeed.level
        }
        let totalBaseExperience = enemySeeds.reduce(into: 0) { partial, enemySeed in
            guard let enemy = enemyTable[enemySeed.enemyId] else {
                return
            }
            partial += enemy.experienceBaseValue * enemySeed.level
        }

        let goldPenalty = Int((
            totalDamageTakenByAllies(in: result) * rewardContext.goldPenaltyPerDamageTaken
        ).rounded())
        let goldBonus = Int((
            Double(totalBaseGold)
                * rewardContext.goldGainPctAddOnNormalKill
                * Double(normalAttackKillCount(in: result))
        ).rounded())
        let gold = Int((Double(totalBaseGold) * rewardContext.goldMultiplier).rounded()) + goldBonus - goldPenalty
        let sharedExperience = rewardContext.memberCharacterIds.isEmpty
            ? 0.0
            : Double(totalBaseExperience) / Double(rewardContext.memberCharacterIds.count)
        let experienceRewards: [ExplorationExperienceReward] = rewardContext.memberCharacterIds.enumerated().compactMap { index, characterId in
            guard livingCharacterIds.contains(characterId) else {
                return nil
            }
            guard totalBaseExperience > 0 else {
                return nil
            }
            let experienceMultiplier = rewardContext.memberExperienceMultipliers.indices.contains(index)
                ? rewardContext.memberExperienceMultipliers[index]
                : 1.0
            let experience = max(Int((sharedExperience * experienceMultiplier).rounded()), 1)
            return ExplorationExperienceReward(characterId: characterId, experience: experience)
        }

        var dropRewards: [ExplorationDropReward] = []
        for (enemyIndex, enemySeed) in enemySeeds.enumerated() {
            guard let enemy = enemyTable[enemySeed.enemyId] else {
                continue
            }

            if let normalDrop = resolveNormalDrop(
                enemyLevel: enemySeed.level,
                superRareRateMultiplier: superRareRateMultiplier,
                floorNumber: floorNumber,
                battleNumber: battleNumber,
                enemyIndex: enemyIndex,
                rootSeed: rootSeed,
                titles: titlesByAscendingQuality,
                rewardContext: rewardContext,
                itemTable: itemTable,
                masterData: masterData
            ) {
                dropRewards.append(normalDrop)
            }

            let rareDropRate = rareDropRate(
                enemyLevel: enemySeed.level,
                rewardContext: rewardContext
            )
            for rareDropOffset in enemy.rareDropItemIds.indices {
                // Rare drops roll independently per configured slot so one enemy can drop
                // multiple rare candidates when the deterministic rolls line up.
                let purpose = "drop:rare:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):candidate:\(rareDropOffset)"
                let roll = ExplorationDeterministicRandom.uniform(
                    rootSeed: rootSeed,
                    purpose: purpose
                )
                guard roll < rareDropRate else {
                    continue
                }

                let itemId = enemy.rareDropItemIds[rareDropOffset]
                guard itemTable[itemId] != nil else {
                    continue
                }

                let title = resolveTitle(
                    floorNumber: floorNumber,
                    battleNumber: battleNumber,
                    enemyIndex: enemyIndex,
                    dropIndex: rareDropOffset,
                    rewardContext: rewardContext,
                    titles: titlesByAscendingQuality,
                    rootSeed: rootSeed
                )
                let superRareId = resolveSuperRareId(
                    title: title,
                    superRareRateMultiplier: superRareRateMultiplier,
                    floorNumber: floorNumber,
                    battleNumber: battleNumber,
                    enemyIndex: enemyIndex,
                    dropIndex: rareDropOffset,
                    rootSeed: rootSeed,
                    masterData: masterData
                )
                dropRewards.append(
                    ExplorationDropReward(
                        itemID: .baseItem(
                            itemId: itemId,
                            titleId: title.id,
                            superRareId: superRareId
                        ),
                        sourceFloorNumber: floorNumber,
                        sourceBattleNumber: battleNumber
                    )
                )
            }
        }

        return BattleRewards(
            gold: gold,
            experienceRewards: experienceRewards,
            dropRewards: dropRewards
        )
    }

    static func resolveNormalDrop(
        enemyLevel: Int,
        superRareRateMultiplier: Double,
        floorNumber: Int,
        battleNumber: Int,
        enemyIndex: Int,
        rootSeed: UInt64,
        titles: [MasterData.Title],
        rewardContext: RewardContext,
        itemTable: [Int: MasterData.Item],
        masterData: MasterData
    ) -> ExplorationDropReward? {
        guard let tier = resolveNormalDropTier(
            enemyLevel: enemyLevel,
            floorNumber: floorNumber,
            battleNumber: battleNumber,
            enemyIndex: enemyIndex,
            rootSeed: rootSeed
        ) else {
            return nil
        }

        let candidates = itemTable.values
            .filter { $0.normalDropTier == tier && $0.category != .jewel }
            .sorted { $0.id < $1.id }
        guard !candidates.isEmpty else {
            return nil
        }

        let itemRoll = ExplorationDeterministicRandom.integer(
            upperBound: candidates.count,
            rootSeed: rootSeed,
            purpose: "drop:normal:item:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):tier:\(tier)"
        )
        let item = normalDropBaseItem(
            from: candidates[itemRoll],
            tier: tier,
            rewardContext: rewardContext,
            floorNumber: floorNumber,
            battleNumber: battleNumber,
            enemyIndex: enemyIndex,
            rootSeed: rootSeed,
            itemTable: itemTable
        )
        let title = resolveTitle(
            floorNumber: floorNumber,
            battleNumber: battleNumber,
            enemyIndex: enemyIndex,
            dropIndex: tier,
            rewardContext: rewardContext,
            titles: titles,
            rootSeed: rootSeed
        )
        let superRareId = resolveSuperRareId(
            title: title,
            superRareRateMultiplier: superRareRateMultiplier,
            floorNumber: floorNumber,
            battleNumber: battleNumber,
            enemyIndex: enemyIndex,
            dropIndex: tier,
            rootSeed: rootSeed,
            masterData: masterData
        )

        return ExplorationDropReward(
            itemID: .baseItem(
                itemId: item.id,
                titleId: title.id,
                superRareId: superRareId
            ),
            sourceFloorNumber: floorNumber,
            sourceBattleNumber: battleNumber
        )
    }

    static func resolveNormalDropTier(
        enemyLevel: Int,
        floorNumber: Int,
        battleNumber: Int,
        enemyIndex: Int,
        rootSeed: UInt64
    ) -> Int? {
        // Normal-drop progression stays two-stage on purpose:
        // 1) enemy level only decides how many times to reroll the tier,
        // 2) this static weight table decides the baseline rarity skew inside each roll.
        // Keeping the tier weights fixed in code avoids splitting one tuning rule across master
        // data and resolver logic, while the exponential roll thresholds define when high-level
        // enemies are allowed to fish for better tiers.
        let weightedTiers: [(value: Int, weight: Double)] = [
            (8, 1),
            (7, 2),
            (6, 4),
            (5, 8),
            (4, 16),
            (3, 32),
            (2, 64),
            (1, 128)
        ]
        let rollCount = normalDropTierRollCount(enemyLevel: enemyLevel)
        var bestTier = 1

        for rollIndex in 0..<rollCount {
            guard let tier = weightedRandomChoice(
                from: weightedTiers,
                rootSeed: rootSeed,
                purpose: "drop:normal:tier:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):roll:\(rollIndex)"
            ) else {
                continue
            }
            // Stronger enemies earn extra rolls and keep the best result instead of warping the
            // base table, which makes the tier curve easier to tune.
            bestTier = max(bestTier, tier)
        }

        return bestTier
    }

    static func normalDropTierRollCount(
        enemyLevel: Int
    ) -> Int {
        let sanitizedLevel = max(enemyLevel, 1)
        var rollCount = 1
        var upperBound = 10

        while sanitizedLevel > upperBound, rollCount < 10 {
            rollCount += 1
            upperBound *= 2
        }

        return rollCount
    }

    static func rareDropRate(
        enemyLevel: Int,
        rewardContext: RewardContext
    ) -> Double {
        let luckBaseRate = 0.001 + cbrt(max(rewardContext.partyAverageLuck, 0)) / 1_000
        return luckBaseRate
            * rewardContext.rareDropMultiplier
            * (1 + 0.1 * (cbrt(Double(enemyLevel)) - 1))
    }

    static func resolveTitle(
        floorNumber: Int,
        battleNumber: Int,
        enemyIndex: Int,
        dropIndex: Int,
        rewardContext: RewardContext,
        titles: [MasterData.Title],
        rootSeed: UInt64
    ) -> MasterData.Title {
        let rollCount = titleRollCount(rewardContext: rewardContext)
        let weightedTitles = titles.map { title in
            (title, Double(title.dropWeight))
        }
        func chooseTitle(for rollIndex: Int) -> MasterData.Title {
            guard let title = weightedRandomChoice(
                from: weightedTitles,
                rootSeed: rootSeed,
                purpose: "drop:title:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):drop:\(dropIndex):roll:\(rollIndex)"
            ) else {
                preconditionFailure("Title drop table must contain at least one positive-weight title.")
            }
            return title
        }

        var bestTitle = chooseTitle(for: 0)
        for rollIndex in 1..<rollCount {
            // Title selection uses the static master-data weights; better results come from
            // additional rerolls rather than runtime reshaping of the drop table.
            let title = chooseTitle(for: rollIndex)
            if title.positiveMultiplier > bestTitle.positiveMultiplier {
                bestTitle = title
            }
        }
        return bestTitle
    }

    static func titleRollCount(
        rewardContext: RewardContext
    ) -> Int {
        max(
            Int((
                (
                    1
                    + Double(rewardContext.titleRollCountModifier)
                    + cbrt(max(rewardContext.partyAverageLuck, 0))
                )
                * rewardContext.enemyTitle.positiveMultiplier
            ).rounded()),
            1
        )
    }

    static func titleRollCountModifier(
        skillIds: Set<Int>,
        skillTable: [Int: MasterData.Skill]
    ) -> Int {
        skillIds.reduce(into: 0) { partialResult, skillId in
            guard let skill = skillTable[skillId] else {
                return
            }

            for effect in skill.effects where effect.kind == .titleRollCountModifier {
                guard let value = effect.value else {
                    continue
                }
                partialResult += Int(value.rounded())
            }
        }
    }

    static func normalDropJewelizeChance(
        skillIds: Set<Int>,
        skillTable: [Int: MasterData.Skill]
    ) -> Double {
        skillIds.reduce(into: 0.0) { partialResult, skillId in
            guard let skill = skillTable[skillId] else {
                return
            }

            for effect in skill.effects where effect.kind == .normalDropJewelize {
                guard let value = effect.value else {
                    continue
                }
                partialResult = max(partialResult, value)
            }
        }
    }

    static func rewardRuleTotal(
        target: String,
        skillIds: Set<Int>,
        skillTable: [Int: MasterData.Skill]
    ) -> Double {
        skillIds.reduce(into: 0.0) { partialResult, skillId in
            guard let skill = skillTable[skillId] else {
                return
            }

            for effect in skill.effects where effect.kind == .rewardRule && effect.target == target {
                guard let value = effect.value else {
                    continue
                }
                partialResult += value
            }
        }
    }

    static func totalDamageTakenByAllies(
        in result: SingleBattleResult
    ) -> Double {
        let allyIDs = Set(result.combatants.filter { $0.side == .ally }.map(\.id))
        return Double(
            result.battleRecord.turns
                .flatMap(\.actions)
                .flatMap(\.results)
                .reduce(into: 0) { partialResult, targetResult in
                    guard targetResult.resultKind == .damage,
                          let value = targetResult.value,
                          allyIDs.contains(targetResult.targetId) else {
                        return
                    }
                    partialResult += value
                }
        )
    }

    static func normalAttackKillCount(
        in result: SingleBattleResult
    ) -> Int {
        result.battleRecord.turns
            .flatMap(\.actions)
            .reduce(into: 0) { partialResult, action in
                guard action.actionKind == .attack else {
                    return
                }
                partialResult += action.results.filter { $0.flags.contains(.defeated) }.count
            }
    }

    static func normalDropBaseItem(
        from defaultItem: MasterData.Item,
        tier: Int,
        rewardContext: RewardContext,
        floorNumber: Int,
        battleNumber: Int,
        enemyIndex: Int,
        rootSeed: UInt64,
        itemTable: [Int: MasterData.Item]
    ) -> MasterData.Item {
        guard rewardContext.normalDropJewelizeChance > 0 else {
            return defaultItem
        }

        let roll = ExplorationDeterministicRandom.uniform(
            rootSeed: rootSeed,
            purpose: "drop:normal:jewelize:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):tier:\(tier)"
        )
        guard roll < rewardContext.normalDropJewelizeChance else {
            return defaultItem
        }

        let jewelCandidates = itemTable.values
            .filter { $0.category == .jewel }
            .sorted { $0.id < $1.id }
        guard !jewelCandidates.isEmpty else {
            return defaultItem
        }

        let weightedJewelCandidates = jewelCandidates.map { jewel in
            (value: jewel, weight: normalDropJewelRarityWeight(for: jewel.rarity))
        }
        guard let selectedJewel = weightedRandomChoice(
            from: weightedJewelCandidates,
            rootSeed: rootSeed,
            purpose: "drop:normal:jewelize:item:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):tier:\(tier)"
        ) else {
            return defaultItem
        }

        return selectedJewel
    }

    static func normalDropJewelRarityWeight(
        for rarity: ItemRarity
    ) -> Double {
        switch rarity {
        case .normal:
            256
        case .uncommon:
            64
        case .rare:
            16
        case .mythic:
            4
        case .godfiend:
            1
        }
    }

    static func resolveSuperRareId(
        title: MasterData.Title,
        superRareRateMultiplier: Double,
        floorNumber: Int,
        battleNumber: Int,
        enemyIndex: Int,
        dropIndex: Int,
        rootSeed: UInt64,
        masterData: MasterData
    ) -> Int {
        guard !masterData.superRares.isEmpty else {
            return 0
        }

        let rollCount = max(Int(title.positiveMultiplier.rounded()), 1)
        for rollIndex in 0..<rollCount {
            let roll = ExplorationDeterministicRandom.uniform(
                rootSeed: rootSeed,
                purpose: "drop:superrare:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):drop:\(dropIndex):roll:\(rollIndex)"
            )
            if roll < 0.000_001 * superRareRateMultiplier {
                let superRareIndex = ExplorationDeterministicRandom.integer(
                    upperBound: masterData.superRares.count,
                    rootSeed: rootSeed,
                    purpose: "drop:superrare:pick:\(floorNumber):\(battleNumber):enemy:\(enemyIndex):drop:\(dropIndex)"
                )
                return masterData.superRares[superRareIndex].id
            }
        }

        return 0
    }

    static func superRareRateMultiplier(
        for result: SingleBattleResult
    ) -> Double {
        let allyCombatants = result.combatants.filter { $0.side == .ally }
        guard !allyCombatants.isEmpty else {
            return 1.0
        }

        let totalMaxHP = allyCombatants.reduce(0) { $0 + $1.maxHP }
        guard totalMaxHP > 0 else {
            return 1.0
        }

        // Hidden super-rare scaling rewards cleaner, faster wins without changing the
        // underlying title or drop tables.
        let totalRemainingHP = allyCombatants.reduce(0) { $0 + max($1.remainingHP, 0) }
        let hpRatio = Double(totalRemainingHP) / Double(totalMaxHP)
        let turnCount = max(result.battleRecord.turns.count, 1)
        return (hpRatio + 0.5) * (10.0 / Double(turnCount))
    }

    static func merged(
        existing: [ExplorationExperienceReward],
        additions: [ExplorationExperienceReward]
    ) -> [ExplorationExperienceReward] {
        let mergedExperience = (existing + additions).reduce(into: [Int: Int]()) { partial, reward in
            partial[reward.characterId, default: 0] += reward.experience
        }

        return mergedExperience.keys.sorted().compactMap { characterId in
            guard let experience = mergedExperience[characterId] else {
                return nil
            }
            return ExplorationExperienceReward(characterId: characterId, experience: experience)
        }
    }

    static func rewardMultiplier(
        target: String,
        skillIds: [Int],
        skillTable: [Int: MasterData.Skill]
    ) -> Double {
        var multiplier = 1.0
        for skillId in skillIds {
            guard let skill = skillTable[skillId] else {
                continue
            }

            for effect in skill.effects where effect.kind == .rewardMultiplier && effect.target == target {
                guard let value = effect.value else {
                    continue
                }

                switch effect.operation {
                case "pctAdd":
                    multiplier *= 1.0 + value
                case nil, "mul":
                    multiplier *= value
                default:
                    continue
                }
            }
        }
        return multiplier
    }

    static func weightedRandomChoice<T>(
        from values: [(value: T, weight: Double)],
        rootSeed: UInt64,
        purpose: String
    ) -> T? {
        let totalWeight = values.reduce(0.0) { $0 + max($1.weight, 0) }
        guard totalWeight > 0 else {
            return nil
        }

        let roll = ExplorationDeterministicRandom.uniform(
            rootSeed: rootSeed,
            purpose: purpose
        ) * totalWeight
        var cumulativeWeight = 0.0
        for value in values {
            cumulativeWeight += max(value.weight, 0)
            if roll < cumulativeWeight {
                return value.value
            }
        }

        return values.last?.value
    }

    static func scaledEnemyLevel(
        baseLevel: Int,
        difficultyMultiplier: Double
    ) -> Int {
        max(Int((Double(baseLevel) * difficultyMultiplier).rounded()), 1)
    }

    static func completionDate(
        startedAt: Date,
        interval: Double,
        completedBattleCount: Int
    ) -> Date {
        startedAt.addingTimeInterval(interval * Double(completedBattleCount))
    }

    static func clamp(
        _ value: Double,
        min minimum: Double,
        max maximum: Double
    ) -> Double {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}

nonisolated private enum ExplorationDeterministicRandom {
    static func uniform(
        rootSeed: UInt64,
        purpose: String
    ) -> Double {
        Double(state(rootSeed: rootSeed, purpose: purpose) >> 11) / Double(1 << 53)
    }

    static func integer(
        upperBound: Int,
        rootSeed: UInt64,
        purpose: String
    ) -> Int {
        guard upperBound > 0 else {
            return 0
        }

        return Int(
            floor(
                uniform(rootSeed: rootSeed, purpose: purpose)
                    * Double(upperBound)
            )
        )
    }

    private static func state(
        rootSeed: UInt64,
        purpose: String
    ) -> UInt64 {
        splitMix64(rootSeed ^ hash(purpose))
    }

    private static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private static func splitMix64(_ value: UInt64) -> UInt64 {
        var state = value &+ 0x9e3779b97f4a7c15
        state = (state ^ (state >> 30)) &* 0xbf58476d1ce4e5b9
        state = (state ^ (state >> 27)) &* 0x94d049bb133111eb
        return state ^ (state >> 31)
    }
}
