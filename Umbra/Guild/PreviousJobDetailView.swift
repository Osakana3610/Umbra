// Presents previous-job details with inherited passive skills only.

import SwiftUI

struct PreviousJobDetailView: View {
    let job: MasterData.Job
    let masterData: MasterData

    private let resolver: MasterDataDetailContentResolver

    init(job: MasterData.Job, masterData: MasterData) {
        self.job = job
        self.masterData = masterData
        resolver = MasterDataDetailContentResolver(masterData: masterData)
    }

    var body: some View {
        List {
            MasterDataSkillSectionView(
                title: "パッシブスキル",
                skillIDs: job.passiveSkillIds,
                resolver: resolver,
                footer: "転職前の職業はパッシブスキルのみ有効です。"
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("職業詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
