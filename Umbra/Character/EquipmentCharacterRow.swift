// Renders a character row for equipment menus so party and shop entry points stay visually aligned.

import SwiftUI

struct EquipmentCharacterRow: View {
    let character: CharacterRecord
    let masterData: MasterData
    let nameResolver: EquipmentDisplayNameResolver

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            GameAssetImage(assetName: masterData.portraitAssetName(for: character))
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(character.name)
                        .font(.headline)

                    Text("装備 \(character.equippedItemCount)/\(character.maximumEquippedItemCount(masterData: masterData))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(masterData.characterSummaryText(for: character))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if character.orderedEquippedItemStacks.isEmpty {
                    Text("装備なし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(character.orderedEquippedItemStacks) { stack in
                        let displayName = nameResolver.displayName(for: stack.itemID)
                        Text(stack.count > 1 ? "\(displayName) x\(stack.count)" : displayName)
                            .font(stack.itemID.baseSuperRareId > 0 ? .body.weight(.semibold) : .body)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
