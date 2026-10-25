import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testFirstLaunchShowsTheEmptyLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "library-empty"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No Books Yet"].exists)
    }
}
