// Hosts the app's primary five-tab shell after startup data has loaded.

import SwiftUI

struct RootTabView: View {
    let masterData: MasterData
    let guildStore: GuildStore

    var body: some View {
        TabView {
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
                GuildHomeView(masterData: masterData, guildStore: guildStore)
            }
            .tabItem {
                Label("ギルド", systemImage: "person.3")
            }

            NavigationStack {
                AdventureHomeView(masterData: masterData, guildStore: guildStore)
            }
            .tabItem {
                Label("冒険", systemImage: "figure.walk")
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
                PlaceholderRootView(
                    title: "その他",
                    systemImage: "ellipsis.circle",
                    description: "追加メニューはこれから実装します。"
                )
                .navigationTitle("その他")
            }
            .tabItem {
                Label("その他", systemImage: "ellipsis.circle")
            }
        }
    }
}
