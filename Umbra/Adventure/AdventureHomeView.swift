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
    @State private var partyEntries: [AdventurePartyListEntry] = []
    @State private var cachedBulkStartableRuns: [ConfiguredRunStart] = []

    private let labyrinthByID: [Int: MasterData.Labyrinth]
    private let cumulativeBattleCountsByLabyrinthId: [Int: [Int: Int]]

    init(
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        partyStore: PartyStore,
        equipmentStore: EquipmentInventoryStore,
        explorationStore: ExplorationStore
    ) {
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.partyStore = partyStore
        self.equipmentStore = equipmentStore
        self.explorationStore = explorationStore
        labyrinthByID = Dictionary(uniqueKeysWithValues: masterData.labyrinths.map { ($0.id, $0) })
        cumulativeBattleCountsByLabyrinthId = Dictionary(
            uniqueKeysWithValues: masterData.labyrinths.map { labyrinth in
                var cumulativeBattleCount = 0
                let battleCountsByFloor = Dictionary(
                    uniqueKeysWithValues: labyrinth.floors
                        .sorted { $0.floorNumber < $1.floorNumber }
                        .map { floor in
                            cumulativeBattleCount += floor.battleCount
                            return (floor.floorNumber, cumulativeBattleCount)
                        }
                )
                return (labyrinth.id, battleCountsByFloor)
            }
        )
    }

    var body: some View {
        List {
            if rosterStore.playerState != nil {
                ForEach(partyEntries) { entry in
                    Section {
                        AdventurePartyHeaderRow(
                            party: entry.party,
                            presentation: entry.presentation,
                            onStartRun: {
                                startRun(for: entry)
                            },
                            onStartRunWithCatTicket: {
                                startRun(
                                    for: entry,
                                    catTicketUsage: .required
                                )
                            },
                            onStartRunWithoutCatTicket: {
                                startRun(
                                    for: entry,
                                    catTicketUsage: .never
                                )
                            }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 6, trailing: 20))

                        NavigationLink {
                            PartyDetailView(
                                partyId: entry.party.partyId,
                                masterData: masterData,
                                rosterStore: rosterStore,
                                partyStore: partyStore,
                                equipmentStore: equipmentStore,
                                explorationStore: explorationStore
                            )
                        } label: {
                            PartyMembersView(
                                masterData: masterData,
                                memberCharacterIds: entry.party.memberCharacterIds,
                                charactersById: rosterStore.charactersById,
                                displayedHPs: entry.status.activeRun?.currentPartyHPs
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(entry.party.name)のメンバーを見る")
                        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 6, trailing: 20))

                        if let run = entry.status.activeRun ?? entry.status.latestCompletedRun {
                            NavigationLink {
                                RunSessionDetailView(
                                    partyId: run.partyId,
                                    partyRunId: run.partyRunId,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    explorationStore: explorationStore
                                )
                            } label: {
                                AdventurePartyLogRow(presentation: entry.presentation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.party.name)の探索記録を見る")
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        } else {
                            AdventurePartyLogRow(presentation: entry.presentation)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }

                        if entry.completedRunCount > 0 {
                            NavigationLink {
                                PartyExplorationHistoryView(
                                    partyId: entry.party.partyId,
                                    partyName: entry.party.name,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    explorationStore: explorationStore
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Text("過去の探索")
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)

                                    Text("\(entry.completedRunCount)件")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.party.name)の過去の探索を見る")
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
                .disabled(cachedBulkStartableRuns.isEmpty || explorationStore.isSortieLocked)
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
        .task(
            id: AdventureHomePresentationInput(
                rosterRevision: rosterStore.contentRevision,
                partyRevision: partyStore.contentRevision,
                explorationRevision: explorationStore.contentRevision
            )
        ) {
            rebuildPartyEntries()
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
              labyrinthByID[selectedLabyrinthId] != nil,
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

    private func configuredRunStart(for party: PartyRecord) -> ConfiguredRunStart? {
        // A party can only sortie when configuration, member state, and exploration state all
        // agree; this keeps the button logic consistent with the underlying service validation.
        guard !explorationStore.isSortieLocked,
              let labyrinthId = configuredLabyrinthId(for: party),
              let selectedDifficultyTitleId = configuredDifficultyTitleId(for: party),
              !explorationStore.hasActiveRun(for: party.partyId),
              !party.memberCharacterIds.isEmpty,
              party.memberCharacterIds.allSatisfy({ characterId in
                  (rosterStore.charactersById[characterId]?.currentHP ?? 0) > 0
              }) else {
            return nil
        }

        return ConfiguredRunStart(
            partyId: party.partyId,
            labyrinthId: labyrinthId,
            selectedDifficultyTitleId: selectedDifficultyTitleId,
            catTicketUsage: party.automaticallyUsesCatTicket ? .automaticIfAvailable : .never
        )
    }

    private func startRun(
        for entry: AdventurePartyListEntry,
        catTicketUsage: CatTicketUsage? = nil
    ) {
        guard let configuredRunStart = entry.configuredRunStart else {
            return
        }

        let resolvedCatTicketUsage = catTicketUsage ?? configuredRunStart.catTicketUsage
        let startedAt = Date()
        Task {
            await explorationStore.startRun(
                partyId: configuredRunStart.partyId,
                labyrinthId: configuredRunStart.labyrinthId,
                selectedDifficultyTitleId: configuredRunStart.selectedDifficultyTitleId,
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
        guard equipmentStore.isLoaded,
              let requiredJewel else {
            return
        }

        if let characterId = requiredJewel.characterId,
           let updatedCharacter = rosterStore.charactersById[characterId] {
            equipmentStore.synchronizeCharacter(updatedCharacter, masterData: masterData)
        } else {
            equipmentStore.applyInventoryChanges(
                [requiredJewel.itemID: -1],
                masterData: masterData
            )
        }
    }

    private func startAllRuns() {
        let startedAt = Date()
        Task {
            await explorationStore.startConfiguredRuns(
                cachedBulkStartableRuns,
                startedAt: startedAt,
                masterData: masterData
            )
        }
    }

    private func rebuildPartyEntries() {
        let entries = partyStore.parties.map { party in
            let status = explorationStore.status(for: party.partyId)
            let configuredRunStart = configuredRunStart(for: party)
            return AdventurePartyListEntry(
                party: party,
                status: status,
                completedRunCount: explorationStore.completedRunCount(for: party.partyId),
                presentation: AdventurePartyPresentation(
                    party: party,
                    status: status,
                    charactersById: rosterStore.charactersById,
                    masterData: masterData,
                    labyrinthByID: labyrinthByID,
                    cumulativeBattleCountsByLabyrinthId: cumulativeBattleCountsByLabyrinthId,
                    canStartRun: configuredRunStart != nil
                ),
                configuredRunStart: configuredRunStart
            )
        }
        partyEntries = entries
        cachedBulkStartableRuns = entries.compactMap(\.configuredRunStart)
    }
}

private struct AdventurePartyHeaderRow: View {
    let party: PartyRecord
    let presentation: AdventurePartyPresentation
    let onStartRun: () -> Void
    let onStartRunWithCatTicket: () -> Void
    let onStartRunWithoutCatTicket: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(party.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            SortieButton(
                title: presentation.actionTitle,
                isDisabled: presentation.actionDisabled,
                onStartRun: onStartRun,
                onStartRunWithCatTicket: onStartRunWithCatTicket,
                onStartRunWithoutCatTicket: onStartRunWithoutCatTicket
            )
            .frame(height: 28)
        }
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

    init(
        party: PartyRecord,
        status: ExplorationPartyStatus,
        charactersById: [Int: CharacterRecord],
        masterData: MasterData,
        labyrinthByID: [Int: MasterData.Labyrinth],
        cumulativeBattleCountsByLabyrinthId: [Int: [Int: Int]],
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

        if let activeRun = status.activeRun {
            let labyrinthName = labyrinthByID[activeRun.labyrinthId].map { labyrinth in
                masterData.explorationLabyrinthDisplayName(
                    labyrinthName: labyrinth.name,
                    difficultyTitleId: activeRun.selectedDifficultyTitleId
                )
            } ?? "不明な迷宮"
            // The active-run card emphasizes the latest resolved battle, while the header shows the
            // projected return time computed from the full configured route.
            let latestBattleText = activeRun.latestBattleOutcome.map(Self.battleText(for:)) ?? "探索開始"
            logHeaderText = Self.estimatedReturnText(
                for: activeRun,
                labyrinthByID: labyrinthByID,
                cumulativeBattleCountsByLabyrinthId: cumulativeBattleCountsByLabyrinthId
            )
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
            let labyrinthName = labyrinthByID[latestCompletedRun.labyrinthId].map { labyrinth in
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
           let labyrinth = labyrinthByID[labyrinthId] {
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
        labyrinthByID: [Int: MasterData.Labyrinth],
        cumulativeBattleCountsByLabyrinthId: [Int: [Int: Int]]
    ) -> String {
        guard let labyrinth = labyrinthByID[run.labyrinthId] else {
            return "帰還予定時刻 --:--:--"
        }

        // Return time is based on the configured target floor rather than current progress so the
        // card shows the original planned finish even while the run is still underway.
        let totalBattleCount = cumulativeBattleCountsByLabyrinthId[run.labyrinthId]?[run.targetFloorNumber] ?? 0
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

private struct AdventurePartyListEntry: Identifiable {
    let party: PartyRecord
    let status: ExplorationPartyStatus
    let completedRunCount: Int
    let presentation: AdventurePartyPresentation
    let configuredRunStart: ConfiguredRunStart?

    var id: Int {
        party.partyId
    }
}

private struct AdventureHomePresentationInput: Equatable {
    let rosterRevision: Int
    let partyRevision: Int
    let explorationRevision: Int
}
