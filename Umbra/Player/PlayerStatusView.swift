// Renders the shared bottom status bar for player-wide state across the tab shell.

import SwiftUI

struct PlayerStatusView: View {
    let premiumTimeText: String
    let rosterStore: GuildRosterStore
    let showsChrome: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            if showsChrome {
                statusContent(for: context.date)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) {
                        Divider()
                    }
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
            } else {
                statusContent(for: context.date)
            }
        }
    }

    private func statusContent(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(catTicketText)

                Spacer(minLength: 0)

                Text(premiumTimeText)
                    .multilineTextAlignment(.trailing)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(
                    date.formatted(
                        Date.FormatStyle(date: .numeric, time: .standard)
                            .locale(Locale(identifier: "ja_JP"))
                    )
                )

                Spacer(minLength: 0)

                Text("\(rosterStore.playerState?.gold ?? 0)G")
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var catTicketText: String {
        "キャット・チケット \(rosterStore.playerState?.catTicketCount ?? 0)枚"
    }
}
