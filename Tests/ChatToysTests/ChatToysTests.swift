import XCTest
@testable import ChatToys

final class ChatToysTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(ChatToys().text, "Hello, World!")
    }

    func testHTML() throws {
        let testPage = """
<div>
    <h2>Item 1</h2>
    <a href="https://google.com">A very cool item</a>
</div>
<div>
    <h3>Item 2</h3>
    <a href="https://bing.com">A less cool item <span class='edit'>edit</span></a>
</div>
"""

        struct Item: Equatable, Codable {
            var title: String
            var desc: String
            var link: String
        }
        let scrape = ScraperInstructions<Item>(base: .init(
                fieldSelectors: ["title": "h2, h3", "desc": "a", "link": "a"],
                fieldAttributes: ["title": .innerText, "desc": .innerText, "link": .href],
                firstField: "title",
                excludeSelectors: [".edit"]
            )
        )
        let items = try scrape.extract(fromHTML: testPage, baseURL: nil)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], .init(title: "Item 1", desc: "A very cool item", link: "https://google.com"))
        XCTAssertEqual(items[1], .init(title: "Item 2", desc: "A less cool item", link: "https://bing.com"))
    }

    private var testEmbedder: some Embedder {
        // TODO
        OpenAIEmbedder(credentials: .init(apiKey: ""), options: .init())
    }

    func testVectorStoreTextSearch() async throws {
        struct Info: Equatable, Codable {
            var value: String
        }
        let store = try VectorStore<Info>(url: nil, embedder: HashEmbedder())
        let docs: [String: String] = [
            "a1": "I like apples",
            "o1": "I like oranges",
            "ao1": "I like apples and oranges",
            "b1": "I like bananas",
            "ab1": "I like apples and bananas",
            "a2": "I hate apples",
        ]
        let records = docs.map { (id, text) in
            VectorStoreRecord<Info>(id: id, group: "my group", date: Date(), text: text, data: .init(value: id))
        }
        try await store.insert(records: Array(records))
        let record = try await store.record(forId: "a1")
        XCTAssertEqual(record?.id, "a1")
        XCTAssertEqual(record?.text, "I like apples")
        XCTAssertEqual(record?.data.value, "a1")
        let res = try await store.fullTextSearch(query: "apples")
        XCTAssertEqual(res.count, 4)
        let res2 = try await store.fullTextSearch(query: "apples and oranges")

        XCTAssertEqual(res2[0].id, "ao1") // the one that mentions apples AND oranges should rank first
        // Test embedding search. We're using a fake embedder that returns hashes so we can only test on EXACT matches
        let x = try await store.embeddingSearch(query: "I like oranges")[0].id
        XCTAssertEqual(x, "o1")
        let x2 = try await store.embeddingSearch(query: "I hate apples")[0].id
        XCTAssertEqual(x2, "a2")
    }

    func testVectorStoreStressTest() async throws {
        struct Info: Equatable, Codable {
            var value: String
        }
        let store = try VectorStore<Info>(url: nil, embedder: HashEmbedder())
        try await store.insert(records: [.init(id: "hi", group: nil, date: Date(), text: "hello world", data: .init(value: "x"))])

        for i in 0..<1045 {
            try await store.insert(records: [.init(id: "i-\(i)", group: "junk", date: Date(), text: "w", data: .init(value: "x"))])
        }

        let x = try await store.embeddingSearch(query: "hello world")[0].id
        XCTAssertEqual(x, "hi")
    }

    func testVectorStoreDeletion() async throws {
        struct Info: Equatable, Codable {}
        let store = try VectorStore<Info>(url: nil, embedder: HashEmbedder())
        try await store.insert(records: [
            .init(id: "apple", group: nil, date: Date(), text: "Hey I like apples", data: .init()),
            .init(id: "orange", group: nil, date: Date(), text: "Hey I like oranges", data: .init()),
            .init(id: "apple-rude", group: "rude", date: Date(), text: "Hey I hate apples", data: .init()),
            .init(id: "orange-rude", group: "rude", date: Date(), text: "Hey I hate oranges", data: .init()),
        ])
        let resIds = try await store.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(resIds), Set(["apple", "orange", "apple-rude", "orange-rude"]))

        try await store.deleteRecords(ids: ["orange-rude"])
        let resIds2 = try await store.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(resIds2), Set(["apple", "orange", "apple-rude"]))

        try await store.deleteRecords(groups: ["rude"])
        let resIds3 = try await store.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(resIds3), Set(["apple", "orange"]))

    }

    func testLimitToMostRecent() async throws {
        struct Info: Equatable, Codable {}
        let store = try VectorStore<Info>(url: nil, embedder: HashEmbedder())
        try await store.insert(records: [
            .init(id: "apple", group: nil, date: Date(), text: "Hey I like apples", data: .init()),
        ])
        try await Task.sleep(seconds: 2)
        try await store.insert(records: [
            .init(id: "orange", group: nil, date: Date(), text: "Hey I like oranges", data: .init()),
        ])
        try await store.deleteOldestRecords(keep: 1)
        let resIds = try await store.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(resIds), Set(["orange"]))
    }

    func testPersistence() async throws {
        let tempTest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-vectorstore")
        try? FileManager.default.removeItem(at: tempTest)
        struct Info: Equatable, Codable {}
        let store = try VectorStore<Info>(url: tempTest, embedder: HashEmbedder())
        try await store.insert(records: [
            .init(id: "apple", group: nil, date: Date(), text: "Hey I like apples", data: .init()),
        ])
        let beforeIds_Fts = try await store.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(beforeIds_Fts), Set(["apple"]))
        let beforeIds_Vector = try await store.embeddingSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(beforeIds_Vector), Set(["apple"]))
        store.save(sync: true)

        let store2 = try VectorStore<Info>(url: tempTest, embedder: HashEmbedder())
        let afterIds_Fts = try await store2.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(afterIds_Fts), Set(["apple"]))
        let afterIds_Vector = try await store2.embeddingSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(afterIds_Vector), Set(["apple"]))
    }
}

struct HashEmbedder: Embedder {
    func embed(documents: [String]) async throws -> [Embedding] {
        return documents.map { doc in
            let hash = doc.hashValue
            var rand = SeededGenerator(string: "\(hash)")
            return .init(vectors: (0..<32).map { _ in Double(rand.nextRandFloat1_Neg1()) }, provider: "test:hashEmbedder")
        }
    }
    var tokenLimit: Int { 4096 } // aka context size
    var dimensions: Int { 32 }
}
