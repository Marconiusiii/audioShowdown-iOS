import SwiftUI

struct GameTheme: Identifiable {
    let name: String
    let background: Color
    let table: Color
    let line: Color
    let player: Color
    let opponent: Color
    let puck: Color
    let accent: Color
    var id: String { name }

    static let all: [GameTheme] = [
        .init(name: "White on black", background: .black, table: .black, line: .white, player: .cyan, opponent: .orange, puck: .white, accent: .yellow),
        .init(name: "Black on white", background: .white, table: .white, line: .black, player: .blue, opponent: .red, puck: .black, accent: .purple),
        .init(name: "Yellow on black", background: .black, table: .black, line: .yellow, player: .yellow, opponent: .white, puck: .yellow, accent: .cyan),
        .init(name: "Blue and gold", background: Color(red: 0.02, green: 0.06, blue: 0.14), table: Color(red: 0.03, green: 0.11, blue: 0.23), line: .white, player: .yellow, opponent: .cyan, puck: .white, accent: .yellow),
        .init(name: "Teal", background: Color(red: 0.01, green: 0.09, blue: 0.10), table: Color(red: 0.02, green: 0.16, blue: 0.17), line: .white, player: .mint, opponent: .orange, puck: .white, accent: .yellow),
        .init(name: "Hot arcade", background: Color(red: 0.10, green: 0.01, blue: 0.13), table: Color(red: 0.17, green: 0.02, blue: 0.22), line: .white, player: .cyan, opponent: .pink, puck: .yellow, accent: .mint),
        .init(name: "Electric purple", background: Color(red: 0.04, green: 0.01, blue: 0.12), table: Color(red: 0.09, green: 0.03, blue: 0.22), line: .white, player: .green, opponent: .orange, puck: .white, accent: .yellow),
        .init(name: "Cosmic", background: Color(red: 0.01, green: 0.01, blue: 0.08), table: Color(red: 0.03, green: 0.02, blue: 0.16), line: .cyan, player: .mint, opponent: .pink, puck: .yellow, accent: .white),
        .init(name: "Neon night", background: .black, table: Color(red: 0.02, green: 0.02, blue: 0.04), line: .green, player: .cyan, opponent: .pink, puck: .yellow, accent: .white)
    ]
}
