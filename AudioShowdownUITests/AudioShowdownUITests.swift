//
//  AudioShowdownUITests.swift
//  AudioShowdownUITests
//
//  Created by Marco Salsiccia on 6/24/26.
//

import XCTest

final class AudioShowdownUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testStartScreenAndSheets() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Audio Showdown, By Chancey Fleet and Marco Salsiccia"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Start Game"].exists)
        XCTAssertTrue(app.buttons["Where the Fuck is the Puck?"].exists)
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Air Hockey Mode"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
