// Hosts user-facing secondary settings and routes to developer-only tools.

import SwiftUI

struct OtherMenuView: View {
    let masterData: MasterData
    let guildService: GuildService
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore

    @AppStorage(ExplorationLogRetentionLimit.userDefaultsKey)
    private var explorationLogRetentionCount = ExplorationLogRetentionLimit.defaultValue.rawValue
    var body: some View {
        Form {
            Section("図鑑") {
                NavigationLink("モンスター図鑑") {
                    MonsterBookView(masterData: masterData)
                        .navigationTitle("モンスター図鑑")
                }
            }

            Section {
                NavigationLink("アイテムドロップ通知") {
                    ItemDropNotificationSettingsView(masterData: masterData)
                        .navigationTitle("アイテムドロップ通知")
                }
            } header: {
                Text("通知")
            }

            Section {
                Picker("保存件数", selection: $explorationLogRetentionCount) {
                    ForEach(ExplorationLogRetentionLimit.allCases) { limit in
                        Text(limit.title).tag(limit.rawValue)
                    }
                }
            } header: {
                Text("探索ログ")
            } footer: {
                Text("設定した上限を超えた探索ログは古いものから削除されます。")
            }

            Section("開発者向け") {
                NavigationLink("デバッグメニュー") {
                    DebugMenuView(
                        masterData: masterData,
                        guildService: guildService,
                        equipmentStore: equipmentStore
                    )
                    .navigationTitle("デバッグ")
                }
            }
        }
        .onChange(of: explorationLogRetentionCount) { _, _ in
            // Changing the retention setting triggers an immediate prune pass so the visible run
            // history reflects the new cap without requiring an app relaunch.
            explorationStore.enforceCompletedRunRetention(masterData: masterData)
        }
    }
}
