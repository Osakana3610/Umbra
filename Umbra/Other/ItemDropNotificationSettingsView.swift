// Presents the in-game item-drop notification filters on a dedicated settings screen.

import SwiftUI

struct ItemDropNotificationSettingsView: View {
    let masterData: MasterData

    @AppStorage("itemDropNotification.showsNormalRarityItems")
    private var showsNormalRarityItems = true

    var body: some View {
        Form {
            Section {
                Text("画面の左下に表示されるドロップの通知設定です。オフにした通知は表示されません。")
            }

            Section("レア度") {
                Toggle("ノーマルアイテムを表示", isOn: $showsNormalRarityItems)
            }

            Section("称号") {
                ForEach(masterData.titles) { title in
                    Toggle(
                        title.name.isEmpty ? "無称号" : title.name,
                        isOn: Binding(
                            get: { ItemDropNotificationSettings.isTitleEnabled(title.id) },
                            set: { ItemDropNotificationSettings.setTitleEnabled($0, titleId: title.id) }
                        )
                    )
                }
            }

            Section {
                ForEach(masterData.superRares) { superRare in
                    Toggle(
                        superRare.name,
                        isOn: Binding(
                            get: { ItemDropNotificationSettings.isSuperRareEnabled(superRare.id) },
                            set: { ItemDropNotificationSettings.setSuperRareEnabled($0, superRareId: superRare.id) }
                        )
                    )
                }
            } header: {
                Text("超レア")
            }
        }
    }
}
