// Presents unlocked parties and navigation into party setup from the adventure tab.

import SwiftUI

struct AdventureHomeView: View {
    let masterData: MasterData
    let guildStore: GuildStore

    var body: some View {
        List {
            if guildStore.playerState != nil {
                Section("パーティ") {
                    ForEach(guildStore.parties) { party in
                        NavigationLink {
                            PartyDetailView(
                                partyId: party.partyId,
                                masterData: masterData,
                                guildStore: guildStore
                            )
                        } label: {
                            PartySummaryRow(
                                party: party,
                                charactersById: guildStore.charactersById
                            )
                        }
                    }
                }

                if let error = guildStore.lastOperationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("冒険")
    }
}

private struct PartySummaryRow: View {
    let party: PartyRecord
    let charactersById: [Int: CharacterRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(party.name)
                    .font(.headline)
                Spacer()
                Text("\(party.memberCharacterIds.count)/\(PartyRecord.memberLimit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            PartyMemberStrip(
                memberCharacterIds: party.memberCharacterIds,
                charactersById: charactersById
            )
        }
        .padding(.vertical, 4)
    }
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
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
}
