// Shows a lightweight placeholder for tabs that don't have feature content yet.

import SwiftUI

struct PlaceholderRootView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
    }
}
