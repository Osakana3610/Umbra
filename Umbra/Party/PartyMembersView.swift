// Renders the six-slot member strip shared by adventure and party management screens.

import SwiftUI

struct PartyMembersView: View {
    let masterData: MasterData
    let memberCharacterIds: [Int]
    let charactersById: [Int: CharacterRecord]
    let displayedHPs: [Int]?
    let onSelectCharacter: ((CharacterRecord) -> Void)?

    init(
        masterData: MasterData,
        memberCharacterIds: [Int],
        charactersById: [Int: CharacterRecord],
        displayedHPs: [Int]? = nil,
        onSelectCharacter: ((CharacterRecord) -> Void)? = nil
    ) {
        self.masterData = masterData
        self.memberCharacterIds = memberCharacterIds
        self.charactersById = charactersById
        self.displayedHPs = displayedHPs
        self.onSelectCharacter = onSelectCharacter
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<PartyRecord.memberLimit, id: \.self) { index in
                PartyMemberSlotView(
                    masterData: masterData,
                    character: character(at: index),
                    displayedCurrentHP: displayedHP(at: index),
                    onSelectCharacter: onSelectCharacter
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

        // Callers can override roster HP with live run HP while keeping the same member ordering.
        return displayedHPs[index]
    }
}

private struct PartyMemberSlotView: View {
    let masterData: MasterData
    let character: CharacterRecord?
    let displayedCurrentHP: Int?
    let onSelectCharacter: ((CharacterRecord) -> Void)?

    var body: some View {
        Group {
            if let character, let onSelectCharacter {
                Button {
                    onSelectCharacter(character)
                } label: {
                    slotContent(for: character)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(character.name)の詳細を見る")
            } else if let character {
                slotContent(for: character)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func slotContent(for character: CharacterRecord) -> some View {
        // Every slot keeps the same compact layout so six members fit across without nested lists.
        VStack(spacing: 2) {
            Image(masterData.portraitAssetName(for: character))
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
        }
    }
}
