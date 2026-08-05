import Foundation

/// Stages exact game states for App Store screenshots.
///
/// Capturing marketing shots by playing the game is unreliable: the score, the
/// puck position, and who is winning are all emergent, so getting a specific
/// frame means replaying until luck cooperates. Instead a scene describes the
/// frame directly — scores, disc positions, phase — and the model adopts it.
///
/// This is inert unless the `-showdownStagedScene <name>` launch argument is
/// present, so it never affects a shipping run.
enum ScreenshotStaging {

    /// A fully specified frame. Coordinates are in the model's table space
    /// (600 x 1200, origin top-left, opponent goal at the top).
    struct Scene {
        var playerScore: Int
        var opponentScore: Int
        var puck: (x: Double, y: Double)
        var puckVelocity: (vx: Double, vy: Double) = (0, 0)
        var playerMallet: (x: Double, y: Double)
        var opponentMallet: (x: Double, y: Double)
        /// Freezes physics so the staged frame survives until the screenshot.
        var frozen: Bool = true
    }

    /// Launch argument that selects a scene by name.
    static let argument = "-showdownStagedScene"

    static let scenes: [String: Scene] = [
        // Lead shot: player comfortably ahead, puck driving into the
        // opponent's half, both paddles visible and clearly engaged.
        "rally": Scene(
            playerScore: 8,
            opponentScore: 5,
            puck: (x: 246, y: 470),
            puckVelocity: (vx: -120, vy: -880),
            playerMallet: (x: 300, y: 900),
            opponentMallet: (x: 355, y: 250)
        ),

        // Second shot: puck defended near the player's end, a different and
        // more tense composition than the lead.
        "defend": Scene(
            playerScore: 9,
            opponentScore: 7,
            puck: (x: 400, y: 815),
            puckVelocity: (vx: 150, vy: 640),
            playerMallet: (x: 372, y: 940),
            opponentMallet: (x: 300, y: 180)
        ),

        // Theme sampler: mid-table, symmetrical and readable at thumbnail size.
        "theme": Scene(
            playerScore: 6,
            opponentScore: 4,
            puck: (x: 315, y: 545),
            puckVelocity: (vx: 90, vy: -700),
            playerMallet: (x: 285, y: 930),
            opponentMallet: (x: 330, y: 235)
        )
    ]

    /// The scene requested on the command line, if any.
    static var requested: Scene? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument),
              index + 1 < arguments.count else { return nil }
        return scenes[arguments[index + 1]]
    }

    static var isStaging: Bool { requested != nil }
}
