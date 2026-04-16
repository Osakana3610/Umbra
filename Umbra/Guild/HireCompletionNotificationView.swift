// Renders the top capsule notification shown after guild hiring completes.

import SwiftUI

struct HireCompletionNotificationView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let message: String
    let dismissNotification: () -> Void

    @State private var isVisible = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.plus.fill")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("雇用完了")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(notificationBackground)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .contentShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .opacity(isVisible ? 1 : 0)
        .offset(y: entranceOffset + min(dragOffset, 0))
        .onAppear(perform: animateEntrance)
        .onTapGesture(perform: dismissAnimated)
        .gesture(dismissGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(message)
        .accessibilityHint("タップまたは上にスワイプで通知を閉じます。")
    }

    private var notificationBackground: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = min(value.translation.height, 0)
            }
            .onEnded { value in
                if value.translation.height < -36 || value.predictedEndTranslation.height < -72 {
                    dismissAnimated()
                } else {
                    resetDragOffset()
                }
            }
    }

    private func dismissAnimated() {
        withAnimation(animation) {
            dismissNotification()
        }
    }

    private func animateEntrance() {
        guard !isVisible else {
            return
        }

        withAnimation(entranceAnimation) {
            isVisible = true
        }
    }

    private func resetDragOffset() {
        withAnimation(animation) {
            dragOffset = 0
        }
    }

    private var entranceOffset: CGFloat {
        guard !isVisible else {
            return 0
        }

        return accessibilityReduceMotion ? 0 : -72
    }

    private var animation: Animation {
        accessibilityReduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22)
    }

    private var entranceAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.12)
    }
}
