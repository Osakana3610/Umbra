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
                            entries: aggregation.rewardEntries(for: "experience")
                        )
                    } header: {
                        Text("経験値倍率")
                    } footer: {
                        Text("経験値倍率は各メンバーに個別適用されます。")
                    }

                    Section("ゴールド") {
                        LabeledContent("合計倍率", value: multiplierText(aggregation.goldMultiplier))

                        PartySkillEntryListView(
                            entries: aggregation.rewardEntries(for: "gold")
                        )
                    }

                    Section("称号") {
                        LabeledContent("合計倍率", value: multiplierText(aggregation.titleDropMultiplier))

                        PartySkillEntryListView(
                            entries: aggregation.rewardEntries(for: "titleDrop")
                        )
                    }

                    Section("レア倍率") {
                        LabeledContent("合計倍率", value: multiplierText(aggregation.rareDropMultiplier))

                        PartySkillEntryListView(
                            entries: aggregation.rewardEntries(for: "rareDrop")
                        )
                    }

                }
                .listStyle(.insetGrouped)
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
                multiplier: rewardMultiplier(
                    target: "experience",
                    skillIds: memberStatus.status.skillIds,
                    skillTable: skillsByID
                )
            )
        }
    }

    private func multiplierText(_ multiplier: Double) -> String {
        "x" + String(format: "%.2f", multiplier)
    }

    private func rewardMultiplier(
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
    let rewardEntriesByTarget: [String: [PartySkillEntry]]
    let goldMultiplier: Double
    let rareDropMultiplier: Double
    let titleDropMultiplier: Double

    init(
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill]
    ) {
        rewardEntriesByTarget = Self.rewardEntriesByTarget(
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
        goldMultiplier = Self.totalRewardMultiplier(
            target: "gold",
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
        rareDropMultiplier = Self.totalRewardMultiplier(
            target: "rareDrop",
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
        titleDropMultiplier = Self.totalRewardMultiplier(
            target: "titleDrop",
            memberStatuses: memberStatuses,
            skillsByID: skillsByID
        )
    }

    func rewardEntries(for target: String) -> [PartySkillEntry] {
        rewardEntriesByTarget[target, default: []]
    }

    private static func rewardEntriesByTarget(
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill]
    ) -> [String: [PartySkillEntry]] {
        let targets = ["experience", "gold", "titleDrop", "rareDrop"]

        return targets.reduce(into: [:]) { partialResult, target in
            partialResult[target] = aggregateEntries(
                memberStatuses: memberStatuses,
                skillsByID: skillsByID,
                includeSkill: { skill in
                    skill.effects.contains { effect in
                        effect.kind == .rewardMultiplier && effect.target == target
                    }
                }
            )
        }
    }

    private static func totalRewardMultiplier(
        target: String,
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill]
    ) -> Double {
        memberStatuses.reduce(into: 1.0) { partialResult, memberStatus in
            partialResult *= rewardMultiplier(
                target: target,
                skillIds: memberStatus.status.skillIds,
                skillTable: skillsByID
            )
        }
    }

    private static func aggregateEntries(
        memberStatuses: [PartyMemberStatus],
        skillsByID: [Int: MasterData.Skill],
        includeSkill: (MasterData.Skill) -> Bool
    ) -> [PartySkillEntry] {
        var ownerNamesBySkillID: [Int: [String]] = [:]

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

    private static func rewardMultiplier(
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
