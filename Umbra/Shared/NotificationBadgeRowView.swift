// Renders shared badge rows used by the overlay notification stacks.

import SwiftUI

struct NotificationBadgeRowView: View {
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding = 10
    @ScaledMetric(relativeTo: .subheadline) private var verticalPadding = 6

    let text: String
    let isHighlighted: Bool
    let accessibilityHint: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .modifier(NotificationBadgeChrome(isHighlighted: isHighlighted))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint(accessibilityHint)
    }
}

struct NotificationBadgeChrome: ViewModifier {
    let isHighlighted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive())
        } else {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

            // Earlier systems approximate the same badge treatment with material plus a light tint.
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape
                        .fill(isHighlighted ? Color.red.opacity(0.18) : Color.black.opacity(0.05))
                }
        }
    }
}
