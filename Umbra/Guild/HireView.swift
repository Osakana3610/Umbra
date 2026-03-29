// Provides the dedicated hiring form reachable from the guild tab.

import SwiftUI

struct HireView: View {
    let masterData: MasterData
    let guildStore: GuildStore

    @State private var selectedRaceId: Int
    @State private var selectedJobId: Int
    @State private var selectedAptitudeId: Int

    init(masterData: MasterData, guildStore: GuildStore) {
        self.masterData = masterData
        self.guildStore = guildStore
        _selectedRaceId = State(initialValue: masterData.races.first?.id ?? 0)
        _selectedJobId = State(initialValue: masterData.jobs.first?.id ?? 0)
        _selectedAptitudeId = State(initialValue: masterData.aptitudes.first?.id ?? 0)
    }

    var body: some View {
        Form {
            Section("条件") {
                Picker("種族", selection: $selectedRaceId) {
                    ForEach(masterData.races) { race in
                        Text(race.name).tag(race.id)
                    }
                }

                Picker("職業", selection: $selectedJobId) {
                    ForEach(masterData.jobs) { job in
                        Text(job.name).tag(job.id)
                    }
                }

                Picker("資質", selection: $selectedAptitudeId) {
                    ForEach(masterData.aptitudes) { aptitude in
                        Text(aptitude.name).tag(aptitude.id)
                    }
                }
            }

            Section("確認") {
                LabeledContent("雇用価格", value: hirePriceText)

                Button(guildStore.isMutating ? "雇用中..." : "求人") {
                    Task {
                        await guildStore.hireCharacter(
                            raceId: selectedRaceId,
                            jobId: selectedJobId,
                            aptitudeId: selectedAptitudeId,
                            masterData: masterData
                        )
                    }
                }
                .disabled(!canHire)
                .accessibilityIdentifier("hire-button")
            }

            if let message = guildStore.lastHireMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("hire-result-message")
                }
            }

            if let error = guildStore.lastOperationError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("雇用")
    }

    private var canHire: Bool {
        guard let playerState = guildStore.playerState,
              let hirePrice,
              selectedRaceId != 0,
              selectedJobId != 0,
              selectedAptitudeId != 0 else {
            return false
        }

        return !guildStore.isMutating && playerState.gold >= hirePrice
    }

    private var hirePrice: Int? {
        guildStore.hirePrice(
            raceId: selectedRaceId,
            jobId: selectedJobId,
            masterData: masterData
        )
    }

    private var hirePriceText: String {
        guard let hirePrice else {
            return "-"
        }

        return "\(hirePrice)"
    }
}
