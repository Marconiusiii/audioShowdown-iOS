//
//  ScreenshotCaptureTests.swift
//  AudioShowdownUITests
//
//  Captures App Store screenshots. Requires no touch input from the operator.
//
//  Game states are staged directly (see ScreenshotStaging in the app target)
//  rather than played into existence: the app launches with a scene name, sets
//  that exact frame, and freezes it. Scores, puck position, and paddle
//  positions are therefore deterministic — the same run always produces the
//  same image.
//
//  Themes and other settings are written into the app's UserDefaults by
//  appStore/CaptureScreenshots.sh before launch.
//

import XCTest

final class ScreenshotCaptureTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(scene: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let scene {
            app.launchArguments += ["-showdownStagedScene", scene]
        }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Enters a match and waits for the staged frame to be on screen.
    private func showStagedTable(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Start Game"].waitForExistence(timeout: 15))
        app.buttons["Start Game"].tap()
        let table = app.otherElements["Audio Showdown table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15), "Table did not appear")
    }

    /// Asserts the staged score actually reached the screen, so a silently
    /// broken staging path can't yield a 0–0 marketing shot.
    private func assertScore(_ app: XCUIApplication, player: Int, opponent: Int) {
        let expected = "Score, You: \(player), Computer: \(opponent)"
        let label = app.staticTexts[expected]
        XCTAssertTrue(
            label.waitForExistence(timeout: 5),
            "Staged score not on screen; expected \(expected)"
        )
    }

    @MainActor
    func testCaptureGameplayRally() throws {
        let app = launchApp(scene: "rally")
        showStagedTable(app)
        assertScore(app, player: 8, opponent: 5)
        attach(app, named: "01_Gameplay_Rally")
    }

    @MainActor
    func testCaptureGameplayDefend() throws {
        let app = launchApp(scene: "defend")
        showStagedTable(app)
        assertScore(app, player: 9, opponent: 7)
        attach(app, named: "02_Gameplay_Defend")
    }

    @MainActor
    func testCaptureSettings() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attach(app, named: "03_Settings")
    }

    /// Captures the staged table in whichever theme the script has written into
    /// defaults. Run once per theme; the name arrives via the environment of
    /// the test runner process, which xcodebuild populates from the shell.
    @MainActor
    func testCaptureCurrentTheme() throws {
        let name = ProcessInfo.processInfo.environment["SHOWDOWN_THEME_NAME"]
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Theme"
        let app = launchApp(scene: "theme")
        showStagedTable(app)
        assertScore(app, player: 6, opponent: 4)
        attach(app, named: "Theme_\(name)")
    }
}
