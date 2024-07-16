import SwiftUI

public struct ForEachUnidentifiable<Item, Content>: View where Content: View {
    var items: [Item]
    var content: (Item, Int) -> Content
    var keyPrefix: String

    public init(_ items: [Item], keyPrefix: String = "", @ViewBuilder content: @escaping (Item, Int) -> Content) {
        self.items = items
        self.content = content
        self.keyPrefix = keyPrefix
    }

    public var body: some View {
        ForEach(IdentifiableByIndexAndKey.create(items: items, keyPrefix: keyPrefix)) { entry in
            content(entry.item, entry.offset)
        }
    }
}

private struct IdentifiableByIndexAndKey<Item>: Identifiable {
    var id: String
    var item: Item
    var offset: Int

    static func create<T: Sequence>(items: T, keyPrefix: String = "") -> [IdentifiableByIndexAndKey<T.Element>] where T.Element == Item {
        items.enumerated().map { tuple in
            let (offset, item) = tuple
            return .init(id: "\(keyPrefix):\(offset)", item: item, offset: offset)
        }
    }
}
