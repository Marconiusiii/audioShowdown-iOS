import SwiftUI

struct GameTheme: Identifiable {
    let name: String
    let isLight: Bool
    let background: Color
    let surface: Color
    let rink: Color
    let foreground: Color
    let dim: Color
    let line: Color
    let player: Color
    let opponent: Color
    let puck: Color
    let accent: Color
    var id: String { name }
    var table: Color { surface }

    init(
        name: String,
        isLight: Bool = false,
        background: String,
        surface: String,
        rink: String,
        foreground: String,
        dim: String,
        line: String,
        accent: String,
        player: String,
        opponent: String,
        puck: String
    ) {
        self.name = name
        self.isLight = isLight
        self.background = Color(hex: background)
        self.surface = Color(hex: surface)
        self.rink = Color(hex: rink)
        self.foreground = Color(hex: foreground)
        self.dim = Color(hex: dim)
        self.line = Color(hex: line)
        self.accent = Color(hex: accent)
        self.player = Color(hex: player)
        self.opponent = Color(hex: opponent)
        self.puck = Color(hex: puck)
    }

    static let all: [GameTheme] = [
        .init(name: "White on black", background: "#05080c", surface: "#101820", rink: "#07141c", foreground: "#f7fbfc", dim: "#b5c4ca", line: "#617985", accent: "#f7fbfc", player: "#f7fbfc", opponent: "#b7c6cc", puck: "#ffffff"),
        .init(name: "Black on white", isLight: true, background: "#f4f7f8", surface: "#ffffff", rink: "#e7eef1", foreground: "#101416", dim: "#4d5c62", line: "#64777f", accent: "#183f50", player: "#111719", opponent: "#52656d", puck: "#000000"),
        .init(name: "Orange on black", background: "#090704", surface: "#171008", rink: "#150d04", foreground: "#fff4e7", dim: "#d3b99d", line: "#8e6541", accent: "#ffae42", player: "#ffd07a", opponent: "#ff7e58", puck: "#fff6df"),
        .init(name: "Orange on white", isLight: true, background: "#fff9f4", surface: "#ffffff", rink: "#fff0e5", foreground: "#2a160c", dim: "#6b4b3b", line: "#9a6b51", accent: "#9b3600", player: "#b33e00", opponent: "#6c2f14", puck: "#35160a"),
        .init(name: "Yellow on navy", background: "#020817", surface: "#081426", rink: "#031126", foreground: "#fffbe6", dim: "#c6d3e0", line: "#6385a3", accent: "#ffe066", player: "#ffe066", opponent: "#7dd3fc", puck: "#ffffff"),
        .init(name: "Blue on cream", isLight: true, background: "#f7f3e8", surface: "#fffdf7", rink: "#e5edf0", foreground: "#101820", dim: "#43545c", line: "#5c7480", accent: "#0645ad", player: "#0645ad", opponent: "#653d00", puck: "#101820"),
        .init(name: "Teal on charcoal", background: "#050b0d", surface: "#0d1719", rink: "#071416", foreground: "#f0fffd", dim: "#aec9c5", line: "#527c78", accent: "#53f2d2", player: "#53f2d2", opponent: "#ffd166", puck: "#ffffff"),
        .init(name: "Colorful", background: "#07111f", surface: "#10243a", rink: "#0b1b2e", foreground: "#fffdf5", dim: "#c7d7e8", line: "#5d87ad", accent: "#ffe45e", player: "#45f0df", opponent: "#ff8fb3", puck: "#ffffff"),
        .init(name: "Cosmic", background: "#05020d", surface: "#110722", rink: "#09031a", foreground: "#fff8ff", dim: "#d2bde0", line: "#755a96", accent: "#55f7ff", player: "#ff5eea", opponent: "#b7ff4a", puck: "#ffffff")
    ]
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: value)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }
}
