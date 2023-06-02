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
}
