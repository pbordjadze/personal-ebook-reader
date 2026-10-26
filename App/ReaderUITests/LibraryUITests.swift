import XCTest

/// The library slice end to end, against the fixture catalog the demo scenarios serve.
final class LibraryUITests: XCTestCase {
    /// A row or button whose VoiceOver label (its texts, combined) starts with `prefix`.
    @MainActor
    func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor
    func testAddingTheServerOpensItsCatalog() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "library-empty"]
        app.launch()
        let add = app.buttons["Add Server"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let address = app.textFields["Address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        address.typeText("books.example.com")
        app.buttons["Save"].tap()
        let browse = button(app, startingWith: "Browse the Catalog")
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        browse.tap()
        XCTAssertTrue(button(app, startingWith: "Recently Added Books").waitForExistence(timeout: 10))
    }

    @MainActor
    func testDownloadingABookPutsItOnTheShelf() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "catalog-new"]
        app.launch()
        let book = button(app, startingWith: "Pride and Prejudice, ")
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        let download = button(app, startingWith: "Download EPUB")
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()
        XCTAssertTrue(app.descendants(matching: .any)["EPUB on this iPhone"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Recently Added Books"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(button(app, startingWith: "Pride and Prejudice, ").waitForExistence(timeout: 10))
    }
}
