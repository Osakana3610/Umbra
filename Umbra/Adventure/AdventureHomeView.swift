// Presents the adventure tab's party cards, sortie actions, and exploration summaries.

import SwiftUI
import UIKit

struct AdventureHomeView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    @State private var showsCappedUnlockJewelPicker = false

    var body: some View {
        List {
            if rosterStore.playerState != nil {
                ForEach(partyStore.parties) { party in
                    let status = explorationStore.status(for: party.partyId)
                    let completedRuns = explorationStore.runs.filter {
                        $0.partyId == party.partyId && $0.isCompleted
                    }
                    let presentation = AdventurePartyPresentation(
                        party: party,
                        status: status,
                        charactersById: rosterStore.charactersById,
                        masterData: masterData,
                        canStartRun: canStartRun(for: party)
                    )

                    Section {
                        AdventurePartyHeaderRow(
                            party: party,
                            presentation: presentation,
                            onStartRun: {
                                startRun(for: party)
                            },
                            onStartRunWithCatTicket: {
                                startRun(
                                    for: party,
                                    catTicketUsage: .required
                                )
                            },
                            onStartRunWithoutCatTicket: {
                                startRun(
                                    for: party,
                                    catTicketUsage: .never
                                )
                            }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))

                        NavigationLink {
                            PartyDetailView(
                                partyId: party.partyId,
                                masterData: masterData,
                                rosterStore: rosterStore,
                                partyStore: partyStore,
                                equipmentStore: equipmentStore,
                                explorationStore: explorationStore
                            )
                        } label: {
                            PartyMembersView(
                                masterData: masterData,
                                memberCharacterIds: party.memberCharacterIds,
                                charactersById: rosterStore.charactersById,
                                displayedHPs: status.activeRun?.currentPartyHPs
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(party.name)のメンバーを見る")
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 20))

                        if let run = status.activeRun ?? status.latestCompletedRun {
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
                                AdventurePartyLogRow(presentation: presentation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(party.name)の探索記録を見る")
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        } else {
                            AdventurePartyLogRow(presentation: presentation)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }

                        if !completedRuns.isEmpty {
                            NavigationLink {
                                PartyExplorationHistoryView(
                                    partyId: party.partyId,
                                    partyName: party.name,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    equipmentStore: equipmentStore,
                                    explorationStore: explorationStore
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Text("過去の探索")
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)

                                    Text("\(completedRuns.count)件")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(party.name)の過去の探索を見る")
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                    }
                }

                Section {
                    Button {
                        if nextPartyUnlockRequiresCapJewel {
                            showsCappedUnlockJewelPicker = true
                        } else {
                            unlockParty()
                        }
                    } label: {
                        Text("パーティ枠を追加")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(canUnlockParty ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canUnlockParty)
                } footer: {
                    Text(partyUnlockFooterText)
                }

                if let error = explorationStore.lastOperationError ?? partyStore.lastOperationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .playerStatusContentInsetAware()
        .navigationTitle("冒険")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("一括出撃") {
                    startAllRuns()
                }
                .disabled(bulkStartableRuns.isEmpty || explorationStore.isSortieLocked)
            }
        }
        .sheet(isPresented: $showsCappedUnlockJewelPicker) {
            NavigationStack {
                EconomicCapJewelPickerView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    equipmentStore: equipmentStore,
                    navigationTitle: "宝石を選ぶ",
                    descriptionText: "パーティ枠の最終解放では、価格が99,999,999Gの宝石を1個消費します。",
                    confirmButtonTitle: "解放する",
                    emptyStateText: "99,999,999Gの宝石を所持していません。",
                    onConfirm: { selection in
                        showsCappedUnlockJewelPicker = false
                        unlockParty(consuming: selection)
                    }
                )
            }
        }
        .task {
            await explorationStore.loadIfNeeded(masterData: masterData)
        }
    }

    private var bulkStartableRuns: [ConfiguredRunStart] {
        partyStore.parties.compactMap { party in
            guard canStartRun(for: party),
                  let labyrinthId = configuredLabyrinthId(for: party),
                  let selectedDifficultyTitleId = configuredDifficultyTitleId(for: party) else {
                return nil
            }

            return ConfiguredRunStart(
                partyId: party.partyId,
                labyrinthId: labyrinthId,
                selectedDifficultyTitleId: selectedDifficultyTitleId,
                catTicketUsage: party.automaticallyUsesCatTicket ? .automaticIfAvailable : .never
            )
        }
    }

    private var canUnlockParty: Bool {
        guard let playerState = rosterStore.playerState,
              let nextPartyUnlockCost else {
            return false
        }

        return !partyStore.isMutating
            && partyStore.parties.count < PartyRecord.maxPartyCount
            && playerState.gold >= nextPartyUnlockCost
    }

    private var nextPartyUnlockCost: Int? {
        PartyRecord.unlockCost(forExistingPartyCount: partyStore.parties.count)
    }

    private var nextPartyUnlockRequiresCapJewel: Bool {
        PartyRecord.unlockRequiresCappedJewel(forExistingPartyCount: partyStore.parties.count)
    }

    private var partyUnlockFooterText: String {
        guard let nextPartyUnlockCost else {
            return "これ以上パーティ枠を追加できません。 \(partyStore.parties.count)/\(PartyRecord.maxPartyCount)"
        }

        var text = "\(nextPartyUnlockCost.formatted())Gで新しいパーティ枠を追加できます。"
        if nextPartyUnlockRequiresCapJewel {
            text += " さらに\(EconomyPricing.maximumEconomicPrice.formatted())G相当の宝石が1個必要です。"
        }
        text += " \(partyStore.parties.count)/\(PartyRecord.maxPartyCount)"
        return text
    }

    private func configuredLabyrinthId(for party: PartyRecord) -> Int? {
        guard let selectedLabyrinthId = party.selectedLabyrinthId,
              masterData.labyrinths.contains(where: { $0.id == selectedLabyrinthId }),
              isLabyrinthUnlocked(selectedLabyrinthId) else {
            return nil
        }

        return selectedLabyrinthId
    }

    private func isLabyrinthUnlocked(_ labyrinthId: Int) -> Bool {
        masterData.defaultUnlockedLabyrinthId == labyrinthId
            || rosterStore.labyrinthProgressByLabyrinthId[labyrinthId] != nil
    }

    private func configuredDifficultyTitleId(for party: PartyRecord) -> Int? {
        guard let labyrinthId = configuredLabyrinthId(for: party) else {
            return nil
        }

        // The displayed sortie target is always clamped to the highest unlocked difficulty so a
        // stale party selection cannot point at an unavailable title.
        let highestUnlockedTitleId = rosterStore.labyrinthProgressByLabyrinthId[labyrinthId]?
            .highestUnlockedDifficultyTitleId
        return masterData.resolvedExplorationDifficultyTitleId(
            requestedTitleId: party.selectedDifficultyTitleId,
            highestUnlockedTitleId: highestUnlockedTitleId
        )
    }

    private func canStartRun(for party: PartyRecord) -> Bool {
        // A party can only sortie when configuration, member state, and exploration state all
        // agree; this keeps the button logic consistent with the underlying service validation.
        guard !explorationStore.isSortieLocked,
              configuredLabyrinthId(for: party) != nil,
              !explorationStore.hasActiveRun(for: party.partyId),
              !party.memberCharacterIds.isEmpty else {
            return false
        }

        return party.memberCharacterIds.allSatisfy { characterId in
            (rosterStore.charactersById[characterId]?.currentHP ?? 0) > 0
        }
    }

    private func startRun(
        for party: PartyRecord,
        catTicketUsage: CatTicketUsage? = nil
    ) {
        guard let labyrinthId = configuredLabyrinthId(for: party),
              let selectedDifficultyTitleId = configuredDifficultyTitleId(for: party) else {
            return
        }

        let resolvedCatTicketUsage = catTicketUsage
            ?? (party.automaticallyUsesCatTicket ? .automaticIfAvailable : .never)
        let startedAt = Date()
        Task {
            await explorationStore.startRun(
                partyId: party.partyId,
                labyrinthId: labyrinthId,
                selectedDifficultyTitleId: selectedDifficultyTitleId,
                startedAt: startedAt,
                catTicketUsage: resolvedCatTicketUsage,
                masterData: masterData
            )
        }
    }

    private func unlockParty(
        consuming requiredJewel: EconomicCapJewelSelection? = nil
    ) {
        partyStore.unlockParty(
            masterData: masterData,
            consuming: requiredJewel
        )
        rosterStore.reload()
        try? equipmentStore.reload(masterData: masterData)
    }

    private func startAllRuns() {
        let startedAt = Date()
        Task {
            await explorationStore.startConfiguredRuns(
                bulkStartableRuns,
                startedAt: startedAt,
                masterData: masterData
            )
        }
    }
}

private struct AdventurePartyHeaderRow: View {
    let party: PartyRecord
    let presentation: AdventurePartyPresentation
    let onStartRun: () -> Void
    let onStartRunWithCatTicket: () -> Void
    let onStartRunWithoutCatTicket: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        metricText("平均Lv", value: presentation.averageLevelText)
                        metricText("生存", value: presentation.aliveMemberText)
                        metricText("総HP", value: presentation.totalHPText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 12) {
                            metricText("平均Lv", value: presentation.averageLevelText)
                            metricText("生存", value: presentation.aliveMemberText)
                        }

                        metricText("総HP", value: presentation.totalHPText)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

                SortieButton(
                    title: presentation.actionTitle,
                    isDisabled: presentation.actionDisabled,
                    onStartRun: onStartRun,
                    onStartRunWithCatTicket: onStartRunWithCatTicket,
                    onStartRunWithoutCatTicket: onStartRunWithoutCatTicket
                )
            }

            Text(party.name)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private func metricText(_ label: String, value: String) -> some View {
        Text("\(label) \(value)")
            .fixedSize(horizontal: true, vertical: true)
    }
}

private struct SortieButton: UIViewRepresentable {
    let title: String
    let isDisabled: Bool
    let onStartRun: () -> Void
    let onStartRunWithCatTicket: () -> Void
    let onStartRunWithoutCatTicket: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(configuration: .filled(), primaryAction: UIAction { _ in
            context.coordinator.onStartRun?()
        })
        button.configuration?.cornerStyle = .capsule
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onStartRun = onStartRun
        context.coordinator.onStartRunWithCatTicket = onStartRunWithCatTicket
        context.coordinator.onStartRunWithoutCatTicket = onStartRunWithoutCatTicket

        var configuration = button.configuration ?? .filled()
        configuration.title = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        configuration.baseBackgroundColor = isDisabled ? .systemGray5 : .systemBlue
        configuration.baseForegroundColor = isDisabled ? .secondaryLabel : .white
        button.configuration = configuration
        button.isEnabled = !isDisabled
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var onStartRun: (() -> Void)?
        var onStartRunWithCatTicket: (() -> Void)?
        var onStartRunWithoutCatTicket: (() -> Void)?

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: [
                    UIAction(title: "キャット・チケットを使用して出撃") { _ in self.onStartRunWithCatTicket?() },
                    UIAction(title: "キャット・チケットを使用せず出撃") { _ in self.onStartRunWithoutCatTicket?() }
                ])
            }
        }
    }
}

private struct AdventurePartyLogRow: View {
    let presentation: AdventurePartyPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let logHeaderText = presentation.logHeaderText {
                Text(logHeaderText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.logText)
                .font(.body)
                .foregroundStyle(presentation.logPrimaryStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AdventurePartyPresentation {
    let logHeaderText: String?
    let logText: String
    let actionTitle: String
    let actionDisabled: Bool
    let logPrimaryStyle: HierarchicalShapeStyle
    let averageLevelText: String
    let aliveMemberText: String
    let totalHPText: String

    init(
        party: PartyRecord,
        status: ExplorationPartyStatus,
        charactersById: [Int: CharacterRecord],
        masterData: MasterData,
        canStartRun: Bool
    ) {
        let members = party.memberCharacterIds.compactMap { charactersById[$0] }
        let displayedCurrentHPs: [Int]
        // While a run is active, cards prefer the live run HP snapshot over persisted roster HP so
        // the overview reflects attrition before rewards are written back on completion.
        if let runHPs = status.activeRun?.currentPartyHPs, runHPs.count == members.count {
            displayedCurrentHPs = runHPs
        } else {
            displayedCurrentHPs = members.map(\.currentHP)
        }

        if members.isEmpty {
            averageLevelText = "--"
        } else {
            let averageLevel = Double(members.reduce(0) { $0 + $1.level }) / Double(members.count)
            averageLevelText = averageLevel.formatted(.number.precision(.fractionLength(1)))
        }

        aliveMemberText = "\(displayedCurrentHPs.filter { $0 > 0 }.count)/\(party.memberCharacterIds.count)"
        totalHPText = displayedCurrentHPs.reduce(0, +).formatted()

        if let activeRun = status.activeRun {
            let labyrinthName = masterData.labyrinths.first(where: { $0.id == activeRun.labyrinthId }).map { labyrinth in
                masterData.explorationLabyrinthDisplayName(
                    labyrinthName: labyrinth.name,
                    difficultyTitleId: activeRun.selectedDifficultyTitleId
                )
            } ?? "不明な迷宮"
            // The active-run card emphasizes the latest resolved battle, while the header shows the
            // projected return time computed from the full configured route.
            let latestBattleText = activeRun.latestBattleOutcome.map(Self.battleText(for:)) ?? "探索開始"
            logHeaderText = Self.estimatedReturnText(for: activeRun, masterData: masterData)
            logText = Self.logText(
                labyrinthName: labyrinthName,
                floorNumber: activeRun.latestBattleFloorNumber,
                statusText: latestBattleText
            )
            actionTitle = "探索中"
            actionDisabled = true
            logPrimaryStyle = .primary
            return
        }

        if let latestCompletedRun = status.latestCompletedRun,
           let completion = latestCompletedRun.completion {
            let labyrinthName = masterData.labyrinths.first(where: { $0.id == latestCompletedRun.labyrinthId }).map { labyrinth in
                masterData.explorationLabyrinthDisplayName(
                    labyrinthName: labyrinth.name,
                    difficultyTitleId: latestCompletedRun.selectedDifficultyTitleId
                )
            } ?? "不明な迷宮"
            let returnedAt = completion.completedAt.formatted(
                Date.FormatStyle(date: .numeric, time: .standard)
                    .locale(Locale(identifier: "ja_JP"))
            )
            logHeaderText = "帰還時刻 \(returnedAt)"
            logText = Self.logText(
                labyrinthName: labyrinthName,
                floorNumber: latestCompletedRun.latestBattleFloorNumber,
                statusText: Self.completionText(for: completion.reason)
            )
            actionTitle = "出撃"
            actionDisabled = !canStartRun
            logPrimaryStyle = .primary
            return
        }

        if let labyrinthId = party.selectedLabyrinthId,
           let labyrinth = masterData.labyrinths.first(where: { $0.id == labyrinthId }) {
            let labyrinthName = masterData.explorationLabyrinthDisplayName(
                labyrinthName: labyrinth.name,
                difficultyTitleId: party.selectedDifficultyTitleId
            )
            logHeaderText = "出撃先迷宮"
            if party.memberCharacterIds.isEmpty {
                logText = "\(labyrinthName)：メンバーを編成すると出撃できます。"
                actionTitle = "出撃"
                actionDisabled = true
                logPrimaryStyle = .secondary
            } else if displayedCurrentHPs.contains(0) {
                logText = "\(labyrinthName)：HPが0のメンバーを含むため出撃できません。"
                actionTitle = "出撃"
                actionDisabled = true
                logPrimaryStyle = .secondary
            } else {
                logText = "\(labyrinthName)：探索ログはまだありません。"
                actionTitle = "出撃"
                actionDisabled = !canStartRun
                logPrimaryStyle = .secondary
            }
            return
        }

        logHeaderText = nil
        logText = "出撃先の迷宮を選択してください。"
        actionTitle = "出撃"
        actionDisabled = true
        logPrimaryStyle = .secondary
    }

    private static func estimatedReturnText(
        for run: RunSessionRecord,
        masterData: MasterData
    ) -> String {
        guard let labyrinth = masterData.labyrinths.first(where: { $0.id == run.labyrinthId }) else {
            return "帰還予定時刻 --:--:--"
        }

        // Return time is based on the configured target floor rather than current progress so the
        // card shows the original planned finish even while the run is still underway.
        let totalBattleCount = labyrinth.floors
            .filter { $0.floorNumber <= run.targetFloorNumber }
            .reduce(into: 0) { partialResult, floor in
                partialResult += floor.battleCount
            }
        guard totalBattleCount > 0 else {
            return "帰還予定時刻 --:--:--"
        }

        let returnAt = run.startedAt.addingTimeInterval(
            run.progressIntervalSeconds(baseIntervalSeconds: labyrinth.progressIntervalSeconds)
                * Double(totalBattleCount)
        )
        return "帰還予定時刻 \(returnAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Locale(identifier: "ja_JP"))))"
    }

    private static func logText(
        labyrinthName: String,
        floorNumber: Int?,
        statusText: String
    ) -> String {
        guard let floorNumber else {
            return "\(labyrinthName)：\(statusText)"
        }

        return "\(labyrinthName)：\(floorNumber)F / \(statusText)"
    }

    private static func battleText(for outcome: BattleOutcome) -> String {
        switch outcome {
        case .victory:
            "勝利"
        case .draw:
            "引き分け"
        case .defeat:
            "敗北"
        }
    }

    private static func completionText(for reason: RunCompletionReason) -> String {
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
