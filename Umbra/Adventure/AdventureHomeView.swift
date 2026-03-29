// Presents party cards, deterministic sortie actions, and exploration status from the adventure tab.

import SwiftUI

struct AdventureHomeView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    @State private var pendingSortieRequest: SortieRequest?

    var body: some View {
        List {
            if rosterStore.playerState != nil {
                Section {
                    Button {
                        partyStore.unlockParty()
                        rosterStore.reload()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.sequence")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("パーティ枠を追加")
                                    .font(.headline)
                                Text("1Gで新しいパーティ枠を追加します。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(partyStore.parties.count)/\(PartyRecord.maxPartyCount)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canUnlockParty)
                }

                Section("パーティ") {
                    ForEach(partyStore.parties) { party in
                        PartyCard(
                            party: party,
                            status: explorationStore.status(for: party.partyId),
                            canStartRun: canStartRun(for: party),
                            charactersById: rosterStore.charactersById,
                            memberSummary: memberSummary(for: party),
                            onStartRun: {
                                pendingSortieRequest = .single(partyId: party.partyId)
                            },
                            detailDestination: {
                                PartyDetailView(
                                    partyId: party.partyId,
                                    masterData: masterData,
                                    rosterStore: rosterStore,
                                    partyStore: partyStore,
                                    equipmentStore: equipmentStore,
                                    explorationStore: explorationStore
                                )
                            }
                        )
                    }
                }

                if let error = explorationStore.lastOperationError ?? partyStore.lastOperationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("冒険")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("一括出撃") {
                    pendingSortieRequest = .bulk(partyIds: bulkStartablePartyIds)
                }
                .disabled(bulkStartablePartyIds.isEmpty || explorationStore.isMutating)
            }
        }
        .confirmationDialog(
            "出撃先を選んでください",
            isPresented: pendingSortieBinding,
            titleVisibility: .visible
        ) {
            ForEach(masterData.labyrinths) { labyrinth in
                Button(labyrinth.name) {
                    startRun(to: labyrinth.id)
                }
            }
            Button("キャンセル", role: .cancel) {
                pendingSortieRequest = nil
            }
        } message: {
            if let pendingSortieRequest {
                Text(sortieMessage(for: pendingSortieRequest))
            }
        }
        .task {
            explorationStore.loadIfNeeded()
            await keepProgressFresh()
        }
        .refreshable {
            refreshProgress()
        }
    }

    private var bulkStartablePartyIds: [Int] {
        partyStore.parties
            .filter(canStartRun(for:))
            .map(\.partyId)
    }

    private var canUnlockParty: Bool {
        guard let playerState = rosterStore.playerState else {
            return false
        }

        return !partyStore.isMutating
            && partyStore.parties.count < PartyRecord.maxPartyCount
            && playerState.gold >= PartyRecord.unlockCost
    }

    private var pendingSortieBinding: Binding<Bool> {
        Binding(
            get: { pendingSortieRequest != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSortieRequest = nil
                }
            }
        )
    }

    private func canStartRun(for party: PartyRecord) -> Bool {
        guard !explorationStore.hasActiveRun(for: party.partyId),
              !party.memberCharacterIds.isEmpty else {
            return false
        }

        return party.memberCharacterIds.allSatisfy { characterId in
            (rosterStore.charactersById[characterId]?.currentHP ?? 0) > 0
        }
    }

    private func memberSummary(for party: PartyRecord) -> String? {
        let status = explorationStore.status(for: party.partyId)

        if let activeRun = status.activeRun {
            let labyrinthName = masterData.labyrinths.first(where: { $0.id == activeRun.labyrinthId })?.name ?? "不明な迷宮"
            return "\(labyrinthName)を探索中 / \(activeRun.completedBattleCount)戦完了"
        }

        if let latestCompletedRun = status.latestCompletedRun,
           let completion = latestCompletedRun.completion {
            return "\(completionText(for: completion.reason)) / \(completion.gold) G / アイテム \(completion.dropRewards.count) 件"
        }

        if party.memberCharacterIds.isEmpty {
            return "メンバーを編成すると出撃できます。"
        }

        if !party.memberCharacterIds.allSatisfy({ (rosterStore.charactersById[$0]?.currentHP ?? 0) > 0 }) {
            return "HPが0のメンバーを含むため出撃できません。"
        }

        return nil
    }

    private func keepProgressFresh() async {
        refreshProgress()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                return
            }
            refreshProgress()
        }
    }

    private func refreshProgress() {
        let didApplyRewards = explorationStore.refreshProgress(at: Date(), masterData: masterData)
        guard didApplyRewards else {
            return
        }

        rosterStore.reload()
        partyStore.reload()
        try? equipmentStore.reload(masterData: masterData)
    }

    private func sortieMessage(for request: SortieRequest) -> String {
        switch request {
        case let .single(partyId):
            let partyName = partyStore.partiesById[partyId]?.name ?? "パーティ\(partyId)"
            return "\(partyName)の出撃先を選択します。"
        case let .bulk(partyIds):
            return "\(partyIds.count)パーティを同じ時刻で出撃させます。"
        }
    }

    private func startRun(to labyrinthId: Int) {
        guard let request = pendingSortieRequest else {
            return
        }

        let startedAt = Date()
        switch request {
        case let .single(partyId):
            explorationStore.startRun(
                partyId: partyId,
                labyrinthId: labyrinthId,
                startedAt: startedAt,
                masterData: masterData
            )
        case let .bulk(partyIds):
            explorationStore.startRuns(
                partyIds: partyIds,
                labyrinthId: labyrinthId,
                startedAt: startedAt,
                masterData: masterData
            )
        }
        pendingSortieRequest = nil
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

private struct PartyCard<Destination: View>: View {
    let party: PartyRecord
    let status: ExplorationPartyStatus
    let canStartRun: Bool
    let charactersById: [Int: CharacterRecord]
    let memberSummary: String?
    let onStartRun: () -> Void
    @ViewBuilder let detailDestination: () -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(party.name)
                        .font(.headline)
                    Text("\(party.memberCharacterIds.count)/\(PartyRecord.memberLimit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(status.activeRun == nil ? "出撃" : "出撃中") {
                    onStartRun()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canStartRun)
            }

            if let memberSummary, !memberSummary.isEmpty {
                Text(memberSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                detailDestination()
            } label: {
                PartyMemberStrip(
                    memberCharacterIds: party.memberCharacterIds,
                    charactersById: charactersById
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

private enum SortieRequest {
    case single(partyId: Int)
    case bulk(partyIds: [Int])
}

private struct PartyMemberStrip: View {
    let memberCharacterIds: [Int]
    let charactersById: [Int: CharacterRecord]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<PartyRecord.memberLimit, id: \.self) { index in
                if index < memberCharacterIds.count,
                   let character = charactersById[memberCharacterIds[index]] {
                    Image(character.portraitAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.quaternary)
                        }
                        .frame(width: 44, height: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
