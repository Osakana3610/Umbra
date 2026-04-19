// Hosts the app's primary five-tab shell after startup data has loaded.

import SwiftUI

struct RootTabView: View {
    private static let statusBarBottomInset: CGFloat = 49
    private static let legacyPlayerStatusContentInset: CGFloat = 106

    let masterData: MasterData
    let persistenceController: PersistenceController
    let rosterStore: GuildRosterStore
    let partyStore: PartyStore
    let equipmentStore: EquipmentInventoryStore
    let shopStore: ShopInventoryStore
    let explorationStore: ExplorationStore
    let itemDropNotificationService: ItemDropNotificationService
    let equipmentStatusNotificationService: EquipmentStatusNotificationService
    let guildServices: GuildServices

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
                    rosterService: guildServices.roster
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
                ShopHomeView(
                    masterData: masterData,
                    rosterStore: rosterStore,
                    equipmentStore: equipmentStore,
                    shopStore: shopStore
                )
            }
            .tabItem {
                Label("商店", systemImage: "bag")
            }

            NavigationStack {
                OtherMenuView(
                    masterData: masterData,
                    persistentContainer: persistenceController.container,
                    inventoryService: guildServices.inventory,
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
        .environment(\.playerStatusContentInset, playerStatusContentInset)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let hireMessage = rosterStore.lastHireMessage {
                HStack {
                    Spacer(minLength: 0)

                    HireCompletionNotificationView(
                        message: hireMessage,
                        dismissNotification: rosterStore.dismissHireMessage
                    )
                    .id(hireMessage)
                    .transition(
                        .asymmetric(
                            insertion: .identity,
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                ItemDropNotificationView(
                    itemDropNotificationService: itemDropNotificationService
                )
                EquipmentStatusNotificationView(
                    equipmentStatusNotificationService: equipmentStatusNotificationService
                )
            }
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

    private var playerStatusContentInset: CGFloat {
        guard rosterStore.playerState != nil else {
            return 0
        }

        if #available(iOS 26.0, *) {
            return 0
        }

        return Self.legacyPlayerStatusContentInset
    }
}
