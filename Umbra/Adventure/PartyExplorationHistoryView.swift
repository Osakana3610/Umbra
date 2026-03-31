// Presents one party's completed exploration summaries and routes each run to its stored detail view.

import SwiftUI

struct PartyExplorationHistoryView: View {
    let partyId: Int
    let partyName: String
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    var body: some View {
        List {
            if completedRuns.isEmpty {
                Section {
                    ContentUnavailableView(
                        "過去の探索はありません",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                }
            } else {
                ForEach(completedRuns) { run in
                    NavigationLink {
                        RunSessionDetailView(
                            partyId: run.partyId,
                            partyRunId: run.partyRunId,
                            masterData: masterData,
                            rosterStore: rosterStore,
                            partyStore: partyStore,
                            equipmentStore: equipmentStore,
                            explorationStore: explorationStore
                        )
                    } label: {
                        CompletedExplorationSummaryRow(
                            headerText: returnedAtText(for: run),
                            logText: logText(for: run)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(partyName)の探索記録を見る")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(partyName)の過去の探索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var completedRuns: [RunSessionRecord] {
        explorationStore.runs
            .filter { $0.partyId == partyId && $0.isCompleted }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completion?.completedAt ?? lhs.startedAt
                let rhsDate = rhs.completion?.completedAt ?? rhs.startedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.partyRunId > rhs.partyRunId
            }
    }

    private func returnedAtText(for run: RunSessionRecord) -> String {
        guard let completedAt = run.completion?.completedAt else {
            return "帰還時刻 --"
        }

        let returnedAt = completedAt.formatted(
            Date.FormatStyle(date: .numeric, time: .standard)
                .locale(Locale(identifier: "ja_JP"))
        )
        return "帰還時刻 \(returnedAt)"
    }

    private func logText(for run: RunSessionRecord) -> String {
        let labyrinthName = masterData.labyrinths.first(where: { $0.id == run.labyrinthId }).map { labyrinth in
            masterData.explorationLabyrinthDisplayName(
                labyrinthName: labyrinth.name,
                difficultyTitleId: run.selectedDifficultyTitleId
            )
        } ?? "不明な迷宮"
        let resultText = completionText(for: run.completion?.reason ?? .draw)
        return "\(labyrinthName)：\(resultText)"
    }

    private func completionText(for reason: RunCompletionReason) -> String {
        switch reason {
        case .cleared:
            "踏破"
        case .defeated:
            "全滅"
        case .draw:
            "引き分け"
        }
    }
}

private struct CompletedExplorationSummaryRow: View {
    let headerText: String
    let logText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headerText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(logText)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
