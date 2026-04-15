// Presents reusable read-only job information for hiring and job-change flows.

import SwiftUI

struct JobDetailView: View {
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
            Section("基本情報") {
                LabeledContent("職業", value: job.name)
                LabeledContent("雇用倍率", value: multiplierText(job.hirePriceMultiplier))
                LabeledContent(
                    "転職条件",
                    value: job.jobChangeRequirementSummary(masterData: masterData) ?? "なし"
                )
            }

            Section("戦闘係数") {
                ForEach(coefficientRows, id: \.title) { row in
                    LabeledContent(row.title, value: multiplierText(row.value))
                }
            }

            MasterDataSkillSectionView(
                title: "パッシブスキル",
                skillIDs: job.passiveSkillIds,
                resolver: resolver
            )

            MasterDataSkillSectionView(
                title: "習得スキル",
                skillIDs: job.levelSkillIds,
                resolver: resolver
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("職業詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var coefficientRows: [(title: String, value: Double)] {
        [
            ("最大HP", job.coefficients.maxHP),
            ("物理攻撃", job.coefficients.physicalAttack),
            ("物理防御", job.coefficients.physicalDefense),
            ("魔法攻撃", job.coefficients.magic),
            ("魔法防御", job.coefficients.magicDefense),
            ("回復", job.coefficients.healing),
            ("命中", job.coefficients.accuracy),
            ("回避", job.coefficients.evasion),
            ("攻撃回数", job.coefficients.attackCount),
            ("必殺率", job.coefficients.criticalRate),
            ("ブレス威力", job.coefficients.breathPower)
        ]
    }

    private func multiplierText(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 2))))x"
    }
}
