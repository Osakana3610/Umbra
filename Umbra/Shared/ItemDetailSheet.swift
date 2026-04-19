// Shares the standard item-detail sheet presentation used across equipment and shop flows.

import SwiftUI

struct ItemDetailSheetPresentation: Identifiable {
    let itemID: CompositeItemID

    var id: String {
        itemID.stableKey
    }
}

extension View {
    func itemDetailSheet(
        item: Binding<ItemDetailSheetPresentation?>,
        masterData: MasterData
    ) -> some View {
        sheet(item: item) { presentation in
            NavigationStack {
                ItemDetailView(
                    itemID: presentation.itemID,
                    masterData: masterData
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") {
                            item.wrappedValue = nil
                        }
                    }
                }
            }
        }
    }
}
