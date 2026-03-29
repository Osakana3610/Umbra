// Renders the six-slot member strip shared by adventure and party management screens.

import SwiftUI

struct PartyMembersView: View {
    let memberCharacterIds: [Int]
    let charactersById: [Int: CharacterRecord]
    let displayedHPs: [Int]?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<PartyRecord.memberLimit, id: \.self) { index in
                PartyMemberSlotView(
                    character: character(at: index),
                    displayedCurrentHP: displayedHP(at: index)
                )
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private func character(at index: Int) -> CharacterRecord? {
        guard memberCharacterIds.indices.contains(index) else {
            return nil
        }

        return charactersById[memberCharacterIds[index]]
    }

    private func displayedHP(at index: Int) -> Int? {
        guard let displayedHPs, displayedHPs.indices.contains(index) else {
            return nil
        }

        return displayedHPs[index]
    }
}

private struct PartyMemberSlotView: View {
    let character: CharacterRecord?
    let displayedCurrentHP: Int?

    var body: some View {
        VStack(spacing: 2) {
            if let character {
                Image(character.portraitAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .clipShape(.rect(cornerRadius: 10))

                Text("Lv.\(character.level)")
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("HP\((displayedCurrentHP ?? character.currentHP).formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
