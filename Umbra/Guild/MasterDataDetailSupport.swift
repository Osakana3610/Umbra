// Shares reusable helpers for master-data detail sheets.

import SwiftUI

struct MasterDataDetailContentResolver {
    let skillsByID: [Int: MasterData.Skill]
    let spellsByID: [Int: MasterData.Spell]

    init(masterData: MasterData) {
        skillsByID = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        spellsByID = Dictionary(uniqueKeysWithValues: masterData.spells.map { ($0.id, $0) })
    }

    func grantedSpellNames(for skill: MasterData.Skill) -> [String] {
        skill.effects
            .filter { $0.kind == .magicAccess && $0.operation == "grant" }
            .flatMap(\.spellIds)
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
