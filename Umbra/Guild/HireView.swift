// Provides the dedicated hiring form reachable from the guild tab.

import SwiftUI
import UIKit

struct HireView: View {
    let masterData: MasterData
    let rosterStore: GuildRosterStore

    @State private var selectedRaceId: Int
    @State private var selectedJobId: Int
    @State private var selectedAptitudeId: Int
    @State private var presentedDetail: HireDetailDestination?
    @State private var isShowingHireAlert = false

    init(masterData: MasterData, rosterStore: GuildRosterStore) {
        self.masterData = masterData
        self.rosterStore = rosterStore
        // Seed each selection from the first available master row so the form is immediately usable
        // even before the user changes any field.
        _selectedRaceId = State(initialValue: masterData.races.first?.id ?? 0)
        _selectedJobId = State(initialValue: masterData.jobs.first?.id ?? 0)
        _selectedAptitudeId = State(initialValue: masterData.aptitudes.first?.id ?? 0)
    }

    var body: some View {
        List {
            Section("種族") {
                ForEach(masterData.races) { race in
                    HireSelectionRow(
                        title: race.name,
                        subtitle: "基本雇用価格 \(race.baseHirePrice)G",
                        isSelected: selectedRaceId == race.id,
                        onSelect: {
                            selectedRaceId = race.id
                        },
                        onShowDetail: {
                            presentedDetail = .race(race.id)
                        }
                    ) {
                        HireRaceIconView(race: race)
                    }
                }
            }

            Section("職業") {
                ForEach(masterData.jobs) { job in
                    HireSelectionRow(
                        title: job.name,
                        subtitle: "雇用倍率 \(hirePriceMultiplierText(job.hirePriceMultiplier))",
                        isSelected: selectedJobId == job.id,
                        onSelect: {
                            selectedJobId = job.id
                        },
                        onShowDetail: {
                            presentedDetail = .job(job.id)
                        }
                    ) {
                        HireJobIconView(job: job)
                    }
                }
            }

            Section("資質") {
                ForEach(masterData.aptitudes) { aptitude in
                    HireSelectionRow(
                        title: aptitude.name,
                        isSelected: selectedAptitudeId == aptitude.id,
                        onSelect: {
                            selectedAptitudeId = aptitude.id
                        },
                        onShowDetail: {
                            presentedDetail = .aptitude(aptitude.id)
                        }
                    ) {
                        EmptyView()
                    }
                }
            }

            Section("確認") {
                LabeledContent("種族", value: selectedRace?.name ?? "-")
                LabeledContent("職業", value: selectedJob?.name ?? "-")
                LabeledContent("資質", value: selectedAptitude?.name ?? "-")
                LabeledContent("雇用価格", value: hirePriceText)
            }

            if let error = rosterStore.lastOperationError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("雇用")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(rosterStore.isMutating ? "雇用中..." : "求人", action: hireCharacter)
                    .disabled(!canHire)
                    .accessibilityIdentifier("hire-button")
            }
        }
        .onChange(of: rosterStore.lastHireMessage) { _, newValue in
            isShowingHireAlert = newValue != nil
        }
        .alert(
            "雇用完了",
            isPresented: $isShowingHireAlert,
            presenting: rosterStore.lastHireMessage
        ) { _ in
            Button("OK") {
                rosterStore.dismissHireMessage()
            }
        } message: { message in
            Text(message)
        }
        .sheet(item: $presentedDetail) { destination in
            NavigationStack {
                hireDetailView(for: destination)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") {
                                presentedDetail = nil
                            }
                        }
                    }
            }
        }
    }

    private var selectedRace: MasterData.Race? {
        masterData.races.first { $0.id == selectedRaceId }
    }

    private var selectedJob: MasterData.Job? {
        masterData.jobs.first { $0.id == selectedJobId }
    }

    private var selectedAptitude: MasterData.Aptitude? {
        masterData.aptitudes.first { $0.id == selectedAptitudeId }
    }

    private var canHire: Bool {
        guard let playerState = rosterStore.playerState,
              let hirePrice,
              selectedRaceId != 0,
              selectedJobId != 0,
              selectedAptitudeId != 0 else {
            return false
        }

        return !rosterStore.isMutating && playerState.gold >= hirePrice
    }

    private var hirePrice: Int? {
        // The form always reuses GuildHiring so any economy cap or multiplier change is reflected
        // identically in both UI and mutation logic.
        GuildHiring.price(raceId: selectedRaceId, jobId: selectedJobId, masterData: masterData)
    }

    private var hirePriceText: String {
        guard let hirePrice else {
            return "-"
        }

        return "\(hirePrice)G"
    }

    private func hireCharacter() {
        rosterStore.hireCharacter(
            raceId: selectedRaceId,
            jobId: selectedJobId,
            aptitudeId: selectedAptitudeId,
            masterData: masterData
        )
    }

    @ViewBuilder
    private func hireDetailView(for destination: HireDetailDestination) -> some View {
        switch destination {
        case .race(let raceID):
            if let race = masterData.races.first(where: { $0.id == raceID }) {
                RaceDetailView(race: race, masterData: masterData)
            }
        case .job(let jobID):
            if let job = masterData.jobs.first(where: { $0.id == jobID }) {
                JobDetailView(job: job, masterData: masterData)
            }
        case .aptitude(let aptitudeID):
            if let aptitude = masterData.aptitudes.first(where: { $0.id == aptitudeID }) {
                AptitudeDetailView(aptitude: aptitude, masterData: masterData)
            }
        }
    }

    private func hirePriceMultiplierText(_ multiplier: Double) -> String {
        String(format: "%.2f倍", multiplier)
    }
}

private struct HireSelectionRow<Icon: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onShowDetail: () -> Void
    @ViewBuilder let icon: () -> Icon

    init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onShowDetail: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onShowDetail = onShowDetail
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .opacity(isSelected ? 1 : 0)
                        .frame(width: 16)

                    icon()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .foregroundStyle(.primary)

                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(title)の詳細")
        }
        .padding(.vertical, 2)
    }
}

private struct HireRaceIconView: View {
    let race: MasterData.Race

    var body: some View {
        if let uiImage = UIImage(named: race.assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Color.clear
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)
        }
    }
}

private struct HireJobIconView: View {
    let job: MasterData.Job

    var body: some View {
        if let uiImage = UIImage(named: job.portraitAssetName(for: .unisex)) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Color.clear
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)
        }
    }
}

private enum HireDetailDestination: Identifiable {
    case race(Int)
    case job(Int)
    case aptitude(Int)

    var id: String {
        switch self {
        case .race(let raceID):
            "race-\(raceID)"
        case .job(let jobID):
            "job-\(jobID)"
        case .aptitude(let aptitudeID):
            "aptitude-\(aptitudeID)"
        }
    }
}
