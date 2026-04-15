// Presents reusable read-only aptitude information for character detail and hiring flows.

import SwiftUI

struct AptitudeDetailView: View {
    let aptitude: MasterData.Aptitude
    let masterData: MasterData

    private let resolver: MasterDataDetailContentResolver

    init(aptitude: MasterData.Aptitude, masterData: MasterData) {
        self.aptitude = aptitude
        self.masterData = masterData
        resolver = MasterDataDetailContentResolver(masterData: masterData)
    }

    var body: some View {
        List {
            Section("基本情報") {
                LabeledContent("資質", value: aptitude.name)
            }

            MasterDataSkillSectionView(
                title: "パッシブスキル",
                skillIDs: aptitude.passiveSkillIds,
                resolver: resolver
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("素質詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
