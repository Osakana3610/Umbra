import SwiftUI

// Shows the current master-data loading state and a small runtime summary.

struct ContentView: View {
    let masterDataStore: MasterDataStore

    var body: some View {
        NavigationStack {
            Group {
                switch masterDataStore.phase {
                case .idle, .loading:
                    ProgressView("マスターデータを読み込み中")
                case let .failed(message):
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "読み込みに失敗しました",
                            systemImage: "exclamationmark.triangle",
                            description: Text(message)
                        )

                        Button("再読み込み") {
                            Task {
                                await masterDataStore.reload()
                            }
                        }
                    }
                    .padding()
                case let .loaded(masterData):
                    List {
                        Section("Bundle") {
                            LabeledContent("Generator", value: masterData.metadata.generator)
                            LabeledContent("種族", value: "\(masterData.races.count)")
                            LabeledContent("職業", value: "\(masterData.jobs.count)")
                            LabeledContent("資質", value: "\(masterData.aptitudes.count)")
                            LabeledContent("アイテム", value: "\(masterData.items.count)")
                            LabeledContent("称号", value: "\(masterData.titles.count)")
                            LabeledContent("超レア", value: "\(masterData.superRares.count)")
                            LabeledContent("スキル", value: "\(masterData.skills.count)")
                            LabeledContent("魔法", value: "\(masterData.spells.count)")
                            LabeledContent("敵", value: "\(masterData.enemies.count)")
                            LabeledContent("迷宮", value: "\(masterData.labyrinths.count)")
                            LabeledContent(
                                "名前",
                                value: "\(masterData.namePools.reduce(0) { $0 + $1.count })"
                            )
                        }

                        Section("Samples") {
                            if let firstRace = masterData.races.first {
                                LabeledContent("最初の種族", value: firstRace.name)
                            }
                            if let firstJob = masterData.jobs.first {
                                LabeledContent("最初の職業", value: firstJob.name)
                            }
                            if let firstLabyrinth = masterData.labyrinths.first {
                                LabeledContent("最初の迷宮", value: firstLabyrinth.name)
                            }
                            if let roughTitle = masterData.titles.first(where: { $0.key == "rough" }) {
                                LabeledContent("称号 rough", value: roughTitle.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Umbra")
        }
        .task {
            await masterDataStore.loadIfNeeded()
        }
    }
}

#Preview {
    ContentView(masterDataStore: MasterDataStore(phase: .loading))
}
