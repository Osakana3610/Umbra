// Presents reusable read-only race information for character detail and hiring flows.

import SwiftUI

struct RaceDetailView: View {
    let race: MasterData.Race
    let masterData: MasterData

    private let resolver: MasterDataDetailContentResolver

    init(race: MasterData.Race, masterData: MasterData) {
        self.race = race
        self.masterData = masterData
        resolver = MasterDataDetailContentResolver(masterData: masterData)
    }

    var body: some View {
        List {
            Section("基本情報") {
                LabeledContent("種族", value: race.name)
                LabeledContent("レベル上限", value: "\(race.levelCap)")
                LabeledContent("基本雇用価格", value: "\(race.baseHirePrice)")
            }

            Section("基本能力値") {
                LabeledContent("体力", value: "\(race.baseStats.vitality)")
                LabeledContent("腕力", value: "\(race.baseStats.strength)")
                LabeledContent("精神", value: "\(race.baseStats.mind)")
                LabeledContent("知略", value: "\(race.baseStats.intelligence)")
                LabeledContent("俊敏", value: "\(race.baseStats.agility)")
                LabeledContent("運", value: "\(race.baseStats.luck)")
            }

            MasterDataSkillSectionView(
                title: "種族スキル",
                skillIDs: race.skillIds,
                resolver: resolver
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("種族詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
