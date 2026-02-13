import SwiftUI

/// Animated typing/thinking indicator shown while the agent is generating.
struct TypingIndicator: View {
    @State private var animationPhase: Int = 0

    private let dotCount = 3
    private let dotSize: CGFloat = 6
    private let animationInterval: TimeInterval = 0.4

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text("Thinking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }

                HStack(spacing: 4) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: dotSize, height: dotSize)
                            .opacity(dotOpacity(for: index))
                            .animation(
                                .easeInOut(duration: animationInterval),
                                value: animationPhase
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer(minLength: 60)
        }
        .onAppear { startAnimation() }
    }

    private func dotOpacity(for index: Int) -> Double {
        index == animationPhase % dotCount ? 1.0 : 0.3
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: animationInterval, repeats: true) { _ in
            animationPhase += 1
        }
    }
}
