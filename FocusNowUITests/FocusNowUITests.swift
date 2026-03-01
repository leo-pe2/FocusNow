import XCTest

final class FocusNowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        let runningPredicate = NSPredicate(format: "state == %d || state == %d", XCUIApplication.State.runningForeground.rawValue, XCUIApplication.State.runningBackground.rawValue)
        expectation(for: runningPredicate, evaluatedWith: app)
        waitForExpectations(timeout: 5)
    }
}
