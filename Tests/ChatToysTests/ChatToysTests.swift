import XCTest
@testable import ChatToys

final class ChatToysTests: XCTestCase {
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
        let resIds3_vector = try await store.embeddingSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(resIds3_vector), Set(["apple", "orange"]))
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
        try await _testPersistence(withDelete: false)
    }

    func testPersistenceWithDeletion() async throws {
        try await  _testPersistence(withDelete: true)
    }

    func _testPersistence(withDelete: Bool) async throws {
        let tempTest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-vectorstore")
        try? FileManager.default.removeItem(at: tempTest)
        struct Info: Equatable, Codable {}
        let store = try VectorStore<Info>(url: tempTest, embedder: HashEmbedder())
        try await store.insert(records: [
            .init(id: "apple", group: nil, date: Date(), text: "Hey I like apples", data: .init()),
        ])

        if withDelete {
            try await store.insert(records: [
                .init(id: "banana", group: nil, date: Date(), text: "Hey I like bananas", data: .init()),
            ])
            try await store.deleteRecords(ids: ["banana"])
        }

        let beforeIds_Fts = try await store.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(beforeIds_Fts), Set(["apple"]))
        let beforeIds_Vector = try await store.embeddingSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(beforeIds_Vector), Set(["apple"]))
        store.save(sync: true)
        store.save(sync: true) // test overwrite

        let store2 = try VectorStore<Info>(url: tempTest, embedder: HashEmbedder())
        let afterIds_Fts = try await store2.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(afterIds_Fts), Set(["apple"]))
        let afterIds_Vector = try await store2.embeddingSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(afterIds_Vector), Set(["apple"]))
    }

    func testAtomicGroupReplacement() async throws {
        struct Info: Equatable, Codable {}
        let store = try VectorStore<Info>(url: nil, embedder: HashEmbedder())
        try await store.insert(records: [
            .init(id: "apple", group: "myGroup", date: Date(), text: "Hey I like apples", data: .init()),
        ])
        try await store.insert(records: [
            .init(id: "orange", group: "myGroup", date: Date(), text: "Hey I like oranges", data: .init()),
        ], deletingOldItemsFromGroup: "myGroup")

        let afterIds_Fts = try await store.fullTextSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(afterIds_Fts), Set(["orange"]))
        let afterIds_Vector = try await store.embeddingSearch(query: "hey").map { $0.id }
        XCTAssertEqual(Set(afterIds_Vector), Set(["orange"]))
    }

    func testEmbeddingDecoding() async throws {
        for testStr in ["hi", "Hello WORLD!", "18794304"] {
            let embedded = try await HashEmbedder().embed(documents: [testStr])[0]
            let roundtripped = try roundtripEncoded(embedded)
            XCTAssertEqual(embedded, roundtripped)
        }
    }

    func testSimd2() async throws {
        let base = try await HashEmbedder().embed(documents: ["hi there"])[0]
        for testStr in ["hi", "Hello WORLD!", "18794304"] {
            let embeddedSimd = try await HashEmbedder(forceFloatStorage: false).embed(documents: [testStr])[0]
            let embeddedVecs = try await HashEmbedder(forceFloatStorage: true).embed(documents: [testStr])[0]
            XCTAssertEqual(embeddedSimd.magnitude, embeddedVecs.magnitude, accuracy: 0.01)
            XCTAssertEqual(embeddedSimd.cosineSimilarity(with: base), embeddedVecs.cosineSimilarity(with: base), accuracy: 0.01)
        }
    }

    func testHalfPrecisionEmbeddings() async throws {
        for testStr in ["hi", "Hello WORLD!", "18794304"] {
            let originalHighPrec = try await HashEmbedder().embed(documents: [testStr])[0]
            var originalLowPrec = originalHighPrec
            originalLowPrec.halfPrecision = true
            let roundtripLowPrec = try roundtripEncoded(originalLowPrec)
            let roundtripLowPrec2 = try roundtripEncoded(roundtripLowPrec)
            XCTAssertEqual(roundtripLowPrec2, roundtripLowPrec)
            XCTAssertTrue(roundtripLowPrec.halfPrecision)
            XCTAssert(roundtripLowPrec.cosineSimilarity(with: originalHighPrec) >= 0.99)
            let encodedHighPrec = try! JSONEncoder().encode(originalHighPrec)
            let encodedLowPrec = try! JSONEncoder().encode(originalLowPrec)
            XCTAssertLessThan(encodedLowPrec.count, encodedHighPrec.count)
        }
    }

    func testFunctionCalling() throws {
        let fn = LLMFunction(
            name: "get_current_weather",
            description: "Get the current weather in a given location",
            parameters: [
                "location": .string(description: "The city and state, e.g. San Francisco, CA"),
                "unit": .enumerated(description: nil, options: ["celsius", "fahrenheit"])
            ], required: ["location"])
        let target = """
    {
      "name": "get_current_weather",
      "description": "Get the current weather in a given location",
      "parameters": {
        "type": "object",
        "properties": {
          "location": {
            "type": "string",
            "description": "The city and state, e.g. San Francisco, CA"
          },
          "unit": {
            "type": "string",
            "enum": ["celsius", "fahrenheit"]
          }
        },
        "required": ["location"]
      }
    }
"""
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        print(try! String(data: enc.encode(fn), encoding: .utf8)!)
        try XCTAssertTrue(compareJson(object: fn, reference: target))
    }

    func testSortedPrefix() {
//        public func sortedPrefix(
//          _ count: Int,
//          by areInIncreasingOrder: (Element, Element) throws -> Bool
        for _ in 0...4 {
            // Choose random length from 1000...2000
            let length = 1000 + Int.random(in: 0..<1000)
            let arr: [Int] = (0..<length).map { _ in Int.random(in: 0..<1000) }
            // Assert that the sortedPrefix function works and is the same as sorting and taking prefix
            let prefixLen = Int.random(in: 1..<50)
            let sortedPrefix = arr.sortedPrefix(prefixLen, by: <)
            let sorted = arr.sorted(by: <)
            let prefix = Array(sorted.prefix(prefixLen))
            XCTAssertEqual(sortedPrefix, prefix)
        }
    }
}

func compareJson(data1: Data, data2: Data) throws -> Bool {
    func normalizeJsonData(_ data: Data) throws -> Data {
        let obj = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .fragmentsAllowed])
    }
    return try normalizeJsonData(data1) == normalizeJsonData(data2)
}

func compareJson<O: Encodable>(object: O, reference: String) throws -> Bool {
    try compareJson(data1: JSONEncoder().encode(object), data2: reference.data(using: .utf8)!)
}

struct HashEmbedder: Embedder {
    var forceFloatStorage: Bool = false

    func embed(documents: [String]) async throws -> [Embedding] {
        return documents.map { doc in
            let hash = doc.hashValue
            var rand = SeededGenerator(string: "\(hash)")
            return .init(vectors: (0..<128).map { _ in Float(rand.nextRandFloat1_Neg1()) }, provider: "test:hashEmbedder", forceFloatStorage: forceFloatStorage)
        }
    }
    var tokenLimit: Int { 4096 } // aka context size
    var dimensions: Int { 128 }
    var providerString: String { "test:hashEmbedder" }
}

func roundtripEncoded<T: Encodable & Decodable>(_ element: T) throws -> T {
    let data = try JSONEncoder().encode(element)
    return try JSONDecoder().decode(T.self, from: data)
}
