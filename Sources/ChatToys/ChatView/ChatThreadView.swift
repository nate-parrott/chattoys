import SwiftUI

public struct ChatThreadView<Message, ID: Hashable, MessageView: View>: View {
    public let messages: [Message]
    public let id: (Message, Int) -> ID
    public let messageView: (Message) -> MessageView
    public let typingIndicator: Bool
    public var headerView: AnyView?

    @State private var messageCountToShow = 15

    public init(
        messages: [Message], 
        id: @escaping (Message, Int) -> ID,
        messageView: @escaping (Message) -> MessageView,
        typingIndicator: Bool = false,
        headerView: AnyView?
        ) {
        self.messages = messages
        self.id = id
        self.messageView = messageView
        self.typingIndicator = typingIndicator
        self.headerView = headerView
    }

    public var body: some View {
        ScrollViewReader { scrollReader in
            scrollView
//            .animation(.niceDefault, value: messages.count)
            .onAppearOrChange(of: scrollToId) { id in
                if let scrollToId {
                    withAnimation {
                        scrollReader.scrollTo(scrollToId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private struct IdentifiableMessage: Identifiable {
        var message: Message
        var id: ID
    }

    private var identifiableMessages: [IdentifiableMessage] {
        messages.enumerated().map { (index, message) in
             IdentifiableMessage(message: message, id: id(message, index))
        }
    }

    @ViewBuilder private var scrollView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                headerView
                
                TruncatedForEach(items: identifiableMessages, itemsToShow: messageCountToShow, showMoreButton: {
                    LoadMoreButton {
                        messageCountToShow += 5
                    }
                }, itemView: { item in
                    messageView(item.message)
                        .id(AnyHashable(item.id))
                })
                if typingIndicator {
                    TypingIndicator().id("typing")
                }
            }
            .padding(10)
        }
    }

    private var scrollToId: AnyHashable? {
        if typingIndicator {
            return AnyHashable("typing")
        } else if let last = messages.last {
            return AnyHashable(id(last, messages.count - 1))
        }
        return nil
    }
}

private struct TruncatedForEach<Item: Identifiable, ShowMore: View, ItemView: View>: View {
    var items: [Item]
    var itemsToShow: Int
    @ViewBuilder var showMoreButton: () -> ShowMore
    @ViewBuilder var itemView: (Item) -> ItemView

    var body: some View {
        if items.count > itemsToShow {
            showMoreButton()
        }
        ForEach(truncatedItems) { item in
            itemView(item)
        }
    }

    private var truncatedItems: [Item] {
        Array(items.suffix(itemsToShow))
    }
}

private struct LoadMoreButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Load older messages")
                .foregroundColor(.accentColor)
                .padding()
        }
        .buttonStyle(PlainButtonStyle())
    }
}
