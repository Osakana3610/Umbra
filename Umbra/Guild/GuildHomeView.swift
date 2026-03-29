// Presents the guild overview with roster state and navigation into hiring.

import SwiftUI

struct GuildHomeView: View {
    let masterData: MasterData
    let guildStore: GuildStore

    var body: some View {
        List {
            if let playerState = guildStore.playerState {
                Section {
                    NavigationLink {
                        HireView(masterData: masterData, guildStore: guildStore)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.plus")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("雇用する")
                                    .font(.headline)
                                Text("新しいキャラクターをギルドに迎えます。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("hire-entry-link")
                }

                Section("ギルド情報") {
                    LabeledContent("所持金", value: "\(playerState.gold)")
                    LabeledContent("雇用数", value: "\(guildStore.characters.count)")
                }

                Section("雇用中のキャラクター") {
                    if guildStore.characters.isEmpty {
                        Text("まだ雇用していません。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(guildStore.characters) { character in
                            HStack(spacing: 12) {
                                Image(character.portraitAssetName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name)
                                        .font(.headline)
                                    Text(summaryText(for: character))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("ギルド")
    }

    private func summaryText(for character: CharacterRecord) -> String {
        let raceName = masterData.races.first(where: { $0.id == character.raceId })?.name ?? "不明"
        let jobName = masterData.jobs.first(where: { $0.id == character.currentJobId })?.name ?? "不明"
        let aptitudeName = masterData.aptitudes.first(where: { $0.id == character.aptitudeId })?.name ?? "不明"
        return "\(raceName) / \(jobName) / \(aptitudeName) / Lv.\(character.level) / HP \(character.currentHP)"
    }
}
