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
