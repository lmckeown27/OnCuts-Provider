import XCTest

final class OnCutsProviderUITests: XCTestCase {
    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
