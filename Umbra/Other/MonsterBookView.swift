// Presents labyrinth-indexed monster reference screens from the master data set.

import SwiftUI

struct MonsterBookView: View {
    let masterData: MasterData

    var body: some View {
        List {
            Section("迷宮一覧") {
                ForEach(masterData.labyrinths) { labyrinth in
                    NavigationLink {
                        MonsterBookLabyrinthView(
                            labyrinth: labyrinth,
                            masterData: masterData
                        )
                        .navigationTitle(labyrinth.name)
                    } label: {
                        MonsterBookLabyrinthRowView(labyrinth: labyrinth)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct MonsterBookLabyrinthView: View {
    let labyrinth: MasterData.Labyrinth
    let masterData: MasterData

    @State private var selectedAppearance: MonsterBookEnemyAppearance?

    var body: some View {
        List {
            Section("概要") {
                LabeledContent("階層数", value: "\(labyrinth.floors.count)")
                LabeledContent("敵数上限", value: "\(labyrinth.enemyCountCap)")
                LabeledContent("出現敵数", value: "\(enemyAppearances.count)")
            }

            Section("出現する敵") {
                if enemyAppearances.isEmpty {
                    Text("出現する敵がありません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(enemyAppearances) { appearance in
                        MonsterBookEnemyRowView(
                            appearance: appearance,
                            enemy: enemyByID[appearance.enemyId],
                            onShowDetail: {
                                selectedAppearance = appearance
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $selectedAppearance) { appearance in
            NavigationStack {
                MonsterBookEnemyDetailView(
                    appearance: appearance,
                    masterData: masterData
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") {
                            selectedAppearance = nil
                        }
                    }
                }
            }
        }
    }

    private var enemyAppearances: [MonsterBookEnemyAppearance] {
        // Merge normal encounters and fixed battles by enemy ID so each monster appears once per
        // labyrinth with its full level span and floor coverage.
        var aggregated: [Int: AggregatedAppearance] = [:]

        for floor in labyrinth.floors {
            for encounter in floor.encounters {
                aggregated[encounter.enemyId, default: AggregatedAppearance()].record(
                    level: encounter.level,
                    floorNumber: floor.floorNumber
                )
            }

            for fixedBattle in floor.fixedBattle ?? [] {
                aggregated[fixedBattle.enemyId, default: AggregatedAppearance()].record(
                    level: fixedBattle.level,
                    floorNumber: floor.floorNumber
                )
            }
        }

        return aggregated.map { enemyId, appearance in
            MonsterBookEnemyAppearance(
                labyrinthId: labyrinth.id,
                labyrinthName: labyrinth.name,
                enemyId: enemyId,
                minimumLevel: appearance.minimumLevel,
                maximumLevel: appearance.maximumLevel,
                floorNumbers: appearance.floorNumbers.sorted()
            )
        }
        .sorted { lhs, rhs in
            if lhs.floorNumbers.first != rhs.floorNumbers.first {
                return (lhs.floorNumbers.first ?? 0) < (rhs.floorNumbers.first ?? 0)
            }

            let lhsName = enemyByID[lhs.enemyId]?.name ?? ""
            let rhsName = enemyByID[rhs.enemyId]?.name ?? ""
            if lhsName != rhsName {
                return lhsName < rhsName
            }

            return lhs.enemyId < rhs.enemyId
        }
    }

    private var enemyByID: [Int: MasterData.Enemy] {
        Dictionary(uniqueKeysWithValues: masterData.enemies.map { ($0.id, $0) })
    }
}

struct MonsterBookEnemyAppearance: Identifiable {
    let labyrinthId: Int
    let labyrinthName: String
    let enemyId: Int
    let minimumLevel: Int
    let maximumLevel: Int
    let floorNumbers: [Int]

    var id: String {
        "\(labyrinthId)-\(enemyId)"
    }

    var levelText: String {
        if minimumLevel == maximumLevel {
            return "Lv\(minimumLevel)"
        }

        return "Lv\(minimumLevel)-\(maximumLevel)"
    }

    var floorText: String {
        floorNumbers.compactConsecutiveRanges().map { range in
            if range.lowerBound == range.upperBound {
                return "\(range.lowerBound)F"
            }

            return "\(range.lowerBound)-\(range.upperBound)F"
        }
        .joined(separator: ", ")
    }

    var selectableLevels: [Int] {
        Array(minimumLevel ... maximumLevel)
    }
}

private struct MonsterBookLabyrinthRowView: View {
    let labyrinth: MasterData.Labyrinth

    var body: some View {
        Text(labyrinth.name)
            .font(.body.weight(.medium))
            .padding(.vertical, 2)
    }
}

private struct MonsterBookEnemyRowView: View {
    let appearance: MonsterBookEnemyAppearance
    let enemy: MasterData.Enemy?
    let onShowDetail: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(enemy?.name ?? "不明な敵")
                    .font(.body.weight(.medium))

                Text("レベル: \(appearance.levelText) / 出現階層: \(appearance.floorText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(enemy?.name ?? "敵")の詳細")
        }
    }
}

private struct AggregatedAppearance {
    private(set) var minimumLevel = Int.max
    private(set) var maximumLevel = Int.min
    private(set) var floorNumbers: Set<Int> = []

    mutating func record(level: Int, floorNumber: Int) {
        minimumLevel = min(minimumLevel, level)
        maximumLevel = max(maximumLevel, level)
        floorNumbers.insert(floorNumber)
    }
}

private extension Array where Element == Int {
    func compactConsecutiveRanges() -> [ClosedRange<Int>] {
        guard let first else {
            return []
        }

        // Compress sorted floor numbers such as [1, 2, 3, 6, 7] into 1...3 and 6...7 for a more
        // readable monster book summary.
        var ranges: [ClosedRange<Int>] = []
        var rangeStart = first
        var previous = first

        for value in dropFirst() {
            if value == previous + 1 {
                previous = value
                continue
            }

            ranges.append(rangeStart ... previous)
            rangeStart = value
            previous = value
        }

        ranges.append(rangeStart ... previous)
        return ranges
    }
}
