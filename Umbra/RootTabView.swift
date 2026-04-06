// Hosts the app's primary five-tab shell after startup data has loaded.

import SwiftUI

struct RootTabView: View {
    private static let statusBarBottomInset: CGFloat = 49

    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let explorationStore: ExplorationStore
    let itemDropNotificationService: ItemDropNotificationService
    let guildService: GuildService

    var body: some View {
        let tabView = TabView {
            NavigationStack {
                PlaceholderRootView(
                    title: "ストーリー",
                    systemImage: "book.closed",
                    description: "メインストーリーはこれから実装します。"
                )
                .navigationTitle("ストーリー")
            }
            .tabItem {
                Label("ストーリー", systemImage: "book.closed")
            }

            NavigationStack {
                GuildHomeView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    partyStore: partyStore,
                    equipmentStore: equipmentStore,
                    explorationStore: explorationStore,
                    guildService: guildService
                )
            }
            .tabItem {
                Label("ギルド", systemImage: "person.3")
            }

            NavigationStack {
                AdventureHomeView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    partyStore: partyStore,
                    equipmentStore: equipmentStore,
                    explorationStore: explorationStore
                )
            }
            .tabItem {
                Label("冒険", systemImage: "map")
            }

            NavigationStack {
                PlaceholderRootView(
                    title: "商店",
                    systemImage: "bag",
                    description: "商店はこれから実装します。"
                )
                .navigationTitle("商店")
            }
            .tabItem {
                Label("商店", systemImage: "bag")
            }

            NavigationStack {
                OtherMenuView(
                    masterData: masterData,
                    guildService: guildService,
                    equipmentStore: equipmentStore,
                    explorationStore: explorationStore
                )
                .navigationTitle("その他")
            }
            .tabItem {
                Label("その他", systemImage: "ellipsis.circle")
            }
        }

        Group {
            if #available(iOS 26.0, *) {
                tabView
                    .tabViewBottomAccessory {
                        if rosterStore.playerState != nil {
                            // On iOS 26+, the status bar can live inside the tab accessory chrome
                            // without reserving extra safe-area space.
                            PlayerStatusView(
                                premiumTimeText: "プレミアム・タイム なし",
                                rosterStore: rosterStore,
                                showsChrome: false
                            )
                        }
                    }
            } else {
                tabView
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if rosterStore.playerState != nil {
                            // Older systems render the same status view inside a manual bottom
                            // inset so it stays above the tab bar.
                            PlayerStatusView(
                                premiumTimeText: "プレミアム・タイム なし",
                                rosterStore: rosterStore,
                                showsChrome: true
                            )
                            .padding(.bottom, Self.statusBarBottomInset)
                        }
                    }
            }
        }
        .overlay(alignment: .bottomLeading) {
            ItemDropNotificationView(
                itemDropNotificationService: itemDropNotificationService
            )
            .padding(.leading, 20)
            .padding(.bottom, notificationBottomPadding)
        }
    }

    private var notificationBottomPadding: CGFloat {
        // The notification overlay is offset differently per tab chrome implementation so it does
        // not collide with either the accessory bar or the legacy safe-area inset.
        if #available(iOS 26.0, *) {
            return 112
        }

        return 106
    }
}
