// Presents one character's job-change status, eligible targets, and confirmation flow.

import SwiftUI

struct JobChangeView: View {
    @Environment(\.dismiss) private var dismiss

    let characterId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let explorationStore: ExplorationStore

    @State private var pendingJobChangeTarget: MasterData.Job?
    @State private var presentedJobDetail: MasterData.Job?
    @State private var didRequestJobChange = false

    var body: some View {
        Group {
            if let character {
                let canChangeJob = canChangeJob(for: character)
                let eligibleJobs = eligibleJobs(for: character)

                List {
                    Section {
                        CharacterJobChangeSummaryView(
                            character: character,
                            masterData: masterData
                        )
                    }

                    Section {
                        if eligibleJobs.isEmpty {
                            Text("転職条件を満たす職業はありません。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(eligibleJobs) { job in
                                JobChangeCandidateRowView(
                                    job: job,
                                    requirementText: job.jobChangeRequirementSummary(masterData: masterData),
                                    isSelectionEnabled: canChangeJob && !rosterStore.isMutating,
                                    onSelect: {
                                        pendingJobChangeTarget = job
                                    },
                                    onShowDetail: {
                                        presentedJobDetail = job
                                    }
                                )
                            }
                        }
                    } header: {
                        Text("転職候補")
                    } footer: {
                        if let reason = unavailableReason(for: character) {
                            Text(reason)
                        }
                    }

                    if let error = rosterStore.lastOperationError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("転職")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    await explorationStore.loadIfNeeded(masterData: masterData)
                }
                .onChange(of: character.previousJobId) { _, newValue in
                    guard didRequestJobChange, newValue != 0 else {
                        return
                    }
                    dismiss()
                }
                .alert(
                    "転職しますか？",
                    isPresented: Binding(
                        get: { pendingJobChangeTarget != nil },
                        set: { isPresented in
                            if !isPresented {
                                pendingJobChangeTarget = nil
                            }
                        }
                    ),
                    presenting: pendingJobChangeTarget
                ) { job in
                    Button("OK") {
                        didRequestJobChange = true
                        rosterStore.changeJob(
                            characterId: character.characterId,
                            to: job.id,
                            masterData: masterData
                        )
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: { job in
                    Text("\(character.name)を\(job.name)に転職させます。転職は一度しか行えず、キャンセルもできません。")
                }
                .sheet(item: $presentedJobDetail) { job in
                    NavigationStack {
                        JobDetailView(job: job, masterData: masterData)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("閉じる") {
                                        presentedJobDetail = nil
                                    }
                                }
                            }
                    }
                }
            } else {
                ContentUnavailableView(
                    "キャラクターが見つかりません",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
            }
        }
    }

    private var character: CharacterRecord? {
        rosterStore.charactersById[characterId]
    }

    private func eligibleJobs(for character: CharacterRecord) -> [MasterData.Job] {
        masterData.jobs.filter { job in
            job.id != character.currentJobId
                && job.canChange(fromCurrentJobId: character.currentJobId, level: character.level)
        }
    }

    private func canChangeJob(for character: CharacterRecord) -> Bool {
        unavailableReason(for: character) == nil
    }

    private func unavailableReason(for character: CharacterRecord) -> String? {
        if character.hasChangedJob {
            return "このキャラクターはすでに転職済みです。"
        }
        if explorationStore.hasActiveRun(forCharacterId: character.characterId) {
            return "出撃中のキャラクターは転職できません。"
        }
        if eligibleJobs(for: character).isEmpty {
            return "転職条件を満たす候補がありません。"
        }
        return nil
    }
}

private struct JobChangeCandidateRowView: View {
    let job: MasterData.Job
    let requirementText: String?
    let isSelectionEnabled: Bool
    let onSelect: () -> Void
    let onShowDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.name)
                            .foregroundStyle(isSelectionEnabled ? .primary : .secondary)

                        if let requirementText {
                            Text(requirementText)
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
            .disabled(!isSelectionEnabled)

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(job.name)の詳細")
        }
    }
}

private struct CharacterJobChangeSummaryView: View {
    let character: CharacterRecord
    let masterData: MasterData

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(character.portraitAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 8) {
                Text(character.name)
                    .font(.title3.weight(.semibold))

                Text(masterData.characterSummaryText(for: character))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("現在の職業: \(masterData.jobDisplayName(for: character))")
                    .font(.subheadline)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
