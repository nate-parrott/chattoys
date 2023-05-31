import SwiftUI

public struct MessageBubble<Content: View>: View {
    public let content: Content
    public let isFromUser: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(isFromUser: Bool, @ViewBuilder content: () -> Content) {
        self.isFromUser = isFromUser
        self.content = content()
    }

    public var body: some View {
        content
            .font(.body)
            .foregroundColor(fgColor)
            .background(bgColor)
            .cornerRadius(20)
            .clipped()
            .padding(isFromUser ? .leading : .trailing)
            .frame(maxWidth: .infinity, alignment: isFromUser ? .trailing : .leading)
    }

    private var bgColor: Color {
        switch colorScheme {
        case .dark:
            return isFromUser ? .accentColor : .secondary.opacity(0.2)
        default:
            return isFromUser ? .accentColor : .secondary.opacity(0.2)
        }
    }

    private var fgColor: Color {
        switch colorScheme {
        case .dark:
            return isFromUser ? .white : .primary
        default:
            return isFromUser ? .white : .primary
        }
    }
}

public struct TextMessageBubble: View {
    public var text: Text
    public var isFromUser: Bool

    public init(_ text: Text, isFromUser: Bool) {
        self.text = text
        self.isFromUser = isFromUser
    }

    public var body: some View {
        MessageBubble(isFromUser: isFromUser) {
            text
                .textSelection(.enabled)
                .withStandardMessagePadding
        }
    }
}

extension View {
    var withStandardMessagePadding: some View {
        self
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
    }
}
