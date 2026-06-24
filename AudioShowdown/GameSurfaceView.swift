import SwiftUI

struct GameSurfaceView: View {
    @ObservedObject var model: GameModel
    let theme: GameTheme
    @State private var touchStart: CGPoint?
    @State private var moved = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                Canvas { context, size in
                    drawTable(context: &context, size: size)
                }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let point = tablePoint(value.location, in: geometry.size)
                        if touchStart == nil {
                            touchStart = value.location
                            moved = false
                            model.touchBegan(at: point)
                        } else {
                            if let touchStart, hypot(value.location.x - touchStart.x, value.location.y - touchStart.y) > 10 { moved = true }
                            model.touchMoved(to: point)
                        }
                    }
                    .onEnded { _ in
                        model.touchEnded(wasTap: !moved)
                        touchStart = nil
                        moved = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(model.isGameOver ? "Game over table. Double-tap to play again." : "Audio Showdown table")
            .accessibilityHint("Direct Touch area. Touch and drag to move your mallet and play.")
            .accessibilityDirectTouch(options: .silentOnTouch)
                .onChange(of: timeline.date) { _, date in model.tick(date) }
            }
        }
        .background(theme.table)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 3))
    }

    private func drawTable(context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width / GameModel.width, size.height / GameModel.height)
        let xOffset = (size.width - GameModel.width * scale) / 2
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: xOffset + x * scale, y: y * scale) }
        func circle(_ disc: GameModel.Disc, radius: Double, color: Color) {
            let center = point(disc.x, disc.y)
            let rect = CGRect(x: center.x - radius * scale, y: center.y - radius * scale, width: radius * 2 * scale, height: radius * 2 * scale)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }

        let centerY = GameModel.center * scale
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: xOffset, y: centerY))
        centerLine.addLine(to: CGPoint(x: xOffset + GameModel.width * scale, y: centerY))
        context.stroke(centerLine, with: .color(theme.line), lineWidth: 3)

        let goalWidth = GameModel.goalHalfWidth * 2 * scale
        let goalX = xOffset + (GameModel.width * scale - goalWidth) / 2
        context.stroke(Path(CGRect(x: goalX, y: 0, width: goalWidth, height: 8)), with: .color(theme.accent), lineWidth: 6)
        context.stroke(Path(CGRect(x: goalX, y: size.height - 8, width: goalWidth, height: 8)), with: .color(theme.accent), lineWidth: 6)
        circle(model.opponentMallet, radius: 44, color: theme.opponent)
        circle(model.playerMallet, radius: 44, color: theme.player)
        circle(model.puck, radius: model.puckRadius, color: theme.puck)
    }

    private func tablePoint(_ location: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(size.width / GameModel.width, size.height / GameModel.height)
        let xOffset = (size.width - GameModel.width * scale) / 2
        return CGPoint(
            x: min(max(Double((location.x - xOffset) / scale), 0), GameModel.width),
            y: min(max(Double(location.y / scale), 0), GameModel.height)
        )
    }
}
