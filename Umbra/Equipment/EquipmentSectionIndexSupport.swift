// Shares iOS 26 section-index helpers for equipment-like category sections.

import SwiftUI

protocol EquipmentSectionIndexable {
    var key: EquipmentSectionKey { get }
}

extension EquipmentSectionRows: EquipmentSectionIndexable {}
extension ShopEnhancementSection: EquipmentSectionIndexable {}

extension View {
    @ViewBuilder
    func equipmentSectionIndexVisibility() -> some View {
        if #available(iOS 26.0, *) {
            listSectionIndexVisibility(.visible)
        } else {
            self
        }
    }
}

@available(iOS 26.0, *)
func equipmentSectionIndexLabel<Section: EquipmentSectionIndexable>(
    for section: Section,
    in sections: [Section]
) -> Text? {
    guard sections.first(where: { $0.key.category == section.key.category })?.key == section.key else {
        return nil
    }

    return Text(section.key.indexLabel)
}
