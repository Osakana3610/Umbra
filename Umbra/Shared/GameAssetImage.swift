// Renders asset-catalog images and applies the shared dark-mode inversion rule to combatant art.

import SwiftUI

struct GameAssetImage: View {
    let assetName: String
    var contentMode: ContentMode = .fill

    var body: some View {
        Image(assetName)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .modifier(CombatantDarkModeInversionModifier(assetName: assetName))
    }
}

private struct CombatantDarkModeInversionModifier: ViewModifier {
    let assetName: String

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if assetName.requiresCombatantDarkModeInversion && colorScheme == .dark {
            content.colorInvert()
        } else {
            content
        }
    }
}

private extension String {
    var requiresCombatantDarkModeInversion: Bool {
        hasPrefix("job_") || hasPrefix("enemy_")
    }
}
