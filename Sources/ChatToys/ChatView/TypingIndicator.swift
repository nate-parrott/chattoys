import SwiftUI

struct TypingIndicator: View {
    var body: some View {
        MessageBubble(isFromUser: false) {
            AnimatedEllipses()
                .withStandardMessagePadding
        }
        .accessibilityLabel("Typing Indicator")
    }
}

struct AnimatedEllipses: View {
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.black)
                    .frame(width: 8, height: 8)
                    .opacity(appeared ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.3)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: appeared)
            }
        }
        .onAppear {
            appeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appeared = true
            }
        }
    }
}
