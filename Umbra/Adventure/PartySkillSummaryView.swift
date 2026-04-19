// Presents aggregated party skill categories derived from current party members.

import SwiftUI

struct PartySkillSummaryView: View {
    let partyId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore

    private let skillsByID: [Int: MasterData.Skill]

    init(
        partyId: Int,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        partyStore: PartyStore
    ) {
        self.partyId = partyId
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.partyStore = partyStore
        skillsByID = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if party != nil {
                List {
                    Section {
                        if experienceMemberRows.isEmpty {
                            Text("メンバーがいません。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(experienceMemberRows) { row in
                                LabeledContent(row.characterName, value: multiplierText(row.multiplier))
                            }
                        }

                        PartySkillEntryListView(
                            entries: aggregation.rewardEntries(for: .experienceGainMultiplier)
                        )
                    } header: {
                        Text("経験値倍率")
                    } footer: {
                        Text("経験値倍率は各メンバーに個別適用されます。")
                    }

                    Section("ゴールド") {
                        LabeledContent("合計倍率", value: multiplierText(aggregation.goldMultiplier))

                        PartySkillEntryListView(
                            entries: aggregation.rewardEntries(for: .goldGainMultiplier)
                        )
                    }

                    Section("称号抽選回数") {
                        LabeledContent("合計補正", value: signedCountText(aggregation.titleRollCountModifier))

                        PartySkillEntryListView(entries: aggregation.titleRollCountEntries)
                    }

                    Section("レア倍率") {
                        LabeledContent("合計倍率", value: multiplierText(aggregation.rareDropMultiplier))

                        PartySkillEntryListView(
                            entries: aggregation.rewardEntries(for: .rareDropMultiplier)
                        )
                    }

                }
                .listStyle(.insetGrouped)
                .playerStatusContentInsetAware()
                .navigationTitle("パーティスキル")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView(
                    "パーティが見つかりません",
                    systemImage: "person.3.sequence"
                )
            }
        }
    }

    private var party: PartyRecord? {
        partyStore.partiesById[partyId]
    }

    private var memberStatuses: [PartyMemberStatus] {
        guard let party else {
            return []
        }

        // Reward skills are derived from the same fully calculated character status used in battle
        // so race, job, previous job, and equipment-granted skills all contribute here.
        return party.memberCharacterIds.compactMap { characterId in
            guard let character = rosterStore.charactersById[characterId],
                  let status = CharacterDerivedStatsCalculator.status(
                    for: character,
                    masterData: masterData
                  ) else {
                return nil
            }

            return PartyMemberStatus(character: character, status: status)
        }
    }

    private var aggregation: PartySkillAggregation {
        PartySkillAggregation(
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
    }

    private var experienceMemberRows: [ExperienceMemberRow] {
        memberStatuses.map { memberStatus in
            ExperienceMemberRow(
                characterID: memberStatus.character.characterId,
                characterName: memberStatus.character.name,
                multiplier: memberStatus.status.rewardMultiplier(for: .experienceGainMultiplier)
            )
        }
    }

    private func multiplierText(_ multiplier: Double) -> String {
        "x" + String(format: "%.2f", multiplier)
    }

    private func signedCountText(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

}

private struct PartyMemberStatus {
    let character: CharacterRecord
    let status: CharacterStatus
}

private struct ExperienceMemberRow: Identifiable {
    let characterID: Int
    let characterName: String
    let multiplier: Double

    var id: Int { characterID }
}

private struct PartySkillAggregation {
    let rewardEntriesByTarget: [RewardMultiplierTarget: [PartySkillEntry]]
    let goldMultiplier: Double
    let rareDropMultiplier: Double
    let titleRollCountEntries: [PartySkillEntry]
    let titleRollCountModifier: Int

    init(
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill]
    ) {
        rewardEntriesByTarget = Self.rewardEntriesByTarget(
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
        goldMultiplier = Self.totalRewardMultiplier(
            target: .goldGainMultiplier,
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
        rareDropMultiplier = Self.totalRewardMultiplier(
            target: .rareDropMultiplier,
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
        titleRollCountEntries = Self.aggregateEntries(
            memberStatuses: memberStatuses,
            skillsByID: skillsByID,
            includeSkill: { skill in
                skill.effects.contains { effect in
                    if case .titleRollCountModifier = effect {
                        return true
                    }
                    return false
                }
            }
        )
        titleRollCountModifier = Self.totalTitleRollCountModifier(
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
    }

    func rewardEntries(for target: RewardMultiplierTarget) -> [PartySkillEntry] {
        rewardEntriesByTarget[target, default: []]
    }

    private static func rewardEntriesByTarget(
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill]
    ) -> [RewardMultiplierTarget: [PartySkillEntry]] {
        let targets = [
            RewardMultiplierTarget.experienceGainMultiplier,
            .goldGainMultiplier,
            .rareDropMultiplier,
        ]

        return targets.reduce(into: [:]) { partialResult, target in
            partialResult[target] = aggregateEntries(
                memberStatuses: memberStatuses,
                skillsByID: skillsByID,
                includeSkill: { skill in
                    skill.effects.contains { effect in
                        if case let .rewardMultiplier(effectTarget, _, _, _) = effect {
                            return effectTarget == target
                        }
                        return false
                    }
                }
            )
        }
    }

    private static func totalRewardMultiplier(
        target: RewardMultiplierTarget,
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill]
    ) -> Double {
        rewardMultiplier(
            target: target,
            skillIds: memberStatuses.flatMap(\.status.skillIds),
            skillTable: skillsByID
        )
    }

    private static func aggregateEntries(
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill],
        includeSkill: (MasterData.Skill) -> Bool
    ) -> [PartySkillEntry] {
        var ownerNamesBySkillID: [Int: [String]] = [:]

        // Entries are aggregated by skill ID first so one skill shared by multiple members renders
        // once with a consolidated owner list.
        for memberStatus in memberStatuses {
            for skillID in memberStatus.status.skillIds {
                guard let skill = skillsByID[skillID], includeSkill(skill) else {
                    continue
                }

                ownerNamesBySkillID[skillID, default: []].append(memberStatus.character.name)
            }
        }

        return ownerNamesBySkillID.keys.sorted().compactMap { skillID in
            guard let skill = skillsByID[skillID] else {
                return nil
            }

            return PartySkillEntry(
                skillID: skillID,
                skill: skill,
                ownerNames: ownerNamesBySkillID[skillID, default: []]
            )
        }
    }

    private static func totalTitleRollCountModifier(
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill]
    ) -> Int {
        Set(memberStatuses.flatMap(\.status.skillIds)).reduce(into: 0) { partialResult, skillId in
            guard let skill = skillsByID[skillId] else {
                return
            }

            for effect in skill.effects {
                guard case let .titleRollCountModifier(value) = effect else {
                    continue
                }
                partialResult += Int(value.rounded())
            }
        }
    }

    private static func rewardMultiplier(
        target: RewardMultiplierTarget,
        skillIds: [Int],
        skillTable: [Int: MasterData.Skill]
    ) -> Double {
        ExplorationResolver.rewardMultiplier(
            target: target,
            skillIds: skillIds,
            skillTable: skillTable
        )
    }
}

private struct PartySkillEntry: Identifiable {
    let skillID: Int
    let skill: MasterData.Skill
    let ownerNames: [String]

    var id: Int { skillID }
}

private struct PartySkillEntryListView: View {
    let entries: [PartySkillEntry]

    var body: some View {
        if entries.isEmpty {
            Text("該当スキルはありません。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.skill.name)
                        .font(.body.weight(.medium))

                    Text(entry.skill.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("所持: \(entry.ownerNames.joined(separator: " / "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
