// Presents reusable read-only aptitude information for character detail and hiring flows.

import SwiftUI

struct AptitudeDetailView: View {
    let aptitude: MasterData.Aptitude
    let masterData: MasterData

    var body: some View {
        List {
            Section("基本情報") {
                LabeledContent("資質", value: aptitude.name)
            }

            Section("効果") {
                Text("現在の資質マスタには、表示できる固有スキルや補正は設定されていません。")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("素質詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
