// Shares the legacy player-status bottom inset with scrollable tab content.

import SwiftUI

extension EnvironmentValues {
    @Entry var playerStatusContentInset: CGFloat = 0
}

private struct PlayerStatusContentInsetModifier: ViewModifier {
    @Environment(\.playerStatusContentInset) private var playerStatusContentInset

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if playerStatusContentInset > 0 {
                Color.clear
                    .frame(height: playerStatusContentInset)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func playerStatusContentInsetAware() -> some View {
        modifier(PlayerStatusContentInsetModifier())
    }
}
