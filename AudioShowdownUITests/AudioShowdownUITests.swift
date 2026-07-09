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
        XCTAssertTrue(app.buttons["Where the duck is the puck?"].exists)
        XCTAssertFalse(app.staticTexts["About Audio Showdown"].exists)
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Air Hockey Mode"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Opponent Skill").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Game Speed").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Sound Style").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Puck Size").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Pitch Behavior").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Pulse Speed").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Puck Volume").count, 1)
        XCTAssertTrue(app.switches["Speed Up When Approaching"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Color Theme").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Reverb").count, 1)
        XCTAssertTrue(app.staticTexts["Haptics"].exists)
        XCTAssertTrue(app.staticTexts["About Audio Showdown"].exists)
        XCTAssertTrue(app.buttons["Submit Feedback"].exists)
    }

    @MainActor
    func testDoubleTapReplacesTableWithPauseScreen() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Start Game"].tap()

        let table = app.descendants(matching: .any)["Audio Showdown table"]
        XCTAssertTrue(table.waitForExistence(timeout: 3))
        let serveStart = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let serveEnd = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        serveStart.press(forDuration: 0.15, thenDragTo: serveEnd)
        table.doubleTap()

        XCTAssertTrue(app.staticTexts["Game Paused"].waitForExistence(timeout: 2))
        XCTAssertFalse(table.exists)
        XCTAssertTrue(app.buttons["End Game"].exists)
        XCTAssertTrue(app.buttons["Resume Game"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
