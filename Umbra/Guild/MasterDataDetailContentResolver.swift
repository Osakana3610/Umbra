// Shares lookup tables and formatting helpers used by master-data detail sheets.
// The resolver keeps repeated skill and spell lookups out of individual views so job, race, and
// monster detail screens can render the same support content consistently.

import SwiftUI

struct MasterDataDetailContentResolver {
    let skillsByID: [Int: MasterData.Skill]
    let spellsByID: [Int: MasterData.Spell]

    init(masterData: MasterData) {
        skillsByID = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        spellsByID = Dictionary(uniqueKeysWithValues: masterData.spells.map { ($0.id, $0) })
    }

    func grantedSpellNames(for skill: MasterData.Skill) -> [String] {
        // Only magic-access grant effects surface as extra spell names in detail sheets.
        skill.effects
            .flatMap { effect -> [Int] in
                guard case let .magicAccess(operation, spellIds, _) = effect,
                      operation == .grant else {
                    return []
                }
                return spellIds
            }
            .compactMap { spellsByID[$0]?.name }
    }
}

struct MasterDataSkillSectionView: View {
    let title: String
    let skillIDs: [Int]
    let resolver: MasterDataDetailContentResolver
    let emptyText: String
    let footer: String?

    init(
        title: String,
        skillIDs: [Int],
        resolver: MasterDataDetailContentResolver,
        emptyText: String = "なし",
        footer: String? = nil
    ) {
        self.title = title
        self.skillIDs = skillIDs
        self.resolver = resolver
        self.emptyText = emptyText
        self.footer = footer
    }

    var body: some View {
        Section {
            if skillIDs.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(skillIDs, id: \.self) { skillID in
                    // Missing IDs are rendered explicitly so partial or stale master data still
                    // produces a readable detail view instead of silently dropping rows.
                    if let skill = resolver.skillsByID[skillID] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(skill.name)
                                .font(.body.weight(.medium))

                            Text(skill.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            let grantedSpellNames = resolver.grantedSpellNames(for: skill)
                            if !grantedSpellNames.isEmpty {
                                Text("使用可能魔法: \(grantedSpellNames.joined(separator: " / "))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    } else {
                        Text("不明なスキル")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }
}
