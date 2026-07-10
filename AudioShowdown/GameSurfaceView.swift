import SwiftUI

struct GameSurfaceView: View {
    @ObservedObject var model: GameModel
    let theme: GameTheme
    let bottomGestureClearance: CGFloat
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
                    .onEnded { value in
                        model.touchEnded(wasTap: !moved, at: tablePoint(value.location, in: geometry.size))
                        touchStart = nil
                        moved = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(model.isGameOver ? "Game over table. Double-tap to play again. Triple-tap to return home." : "Audio Showdown table")
            .accessibilityHint(model.isGameOver ? "Direct Touch area with replay and Home gestures." : "Direct Touch area. Touch and drag to play. Double-tap to pause the game.")
            .accessibilityDirectTouch(options: .silentOnTouch)
                .onChange(of: timeline.date) { _, date in model.tick(date) }
            }
        }
        .background(theme.table)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 3))
    }

    private func playableSize(from size: CGSize) -> CGSize {
        CGSize(width: size.width, height: max(1, size.height - bottomGestureClearance))
    }

    private func drawTable(context: inout GraphicsContext, size: CGSize) {
        let playableSize = playableSize(from: size)
        let scale = min(playableSize.width / GameModel.width, playableSize.height / GameModel.height)
        let xOffset = (size.width - GameModel.width * scale) / 2
        let tableWidth = GameModel.width * scale
        let tableHeight = GameModel.height * scale
        let tableRect = CGRect(x: xOffset, y: 0, width: tableWidth, height: tableHeight)
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: xOffset + x * scale, y: y * scale) }
        func filledCircle(_ disc: GameModel.Disc, radius: Double, color: Color, shadow: Color? = nil) {
            let center = point(disc.x, disc.y)
            let rect = CGRect(x: center.x - radius * scale, y: center.y - radius * scale, width: radius * 2 * scale, height: radius * 2 * scale)
            if let shadow {
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: shadow.opacity(0.9), radius: 12 * scale))
                    layer.fill(Path(ellipseIn: rect), with: .color(color))
                }
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        func strokedCircle(_ disc: GameModel.Disc, radius: Double, color: Color, lineWidth: Double) {
            let center = point(disc.x, disc.y)
            let rect = CGRect(x: center.x - radius * scale, y: center.y - radius * scale, width: radius * 2 * scale, height: radius * 2 * scale)
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lineWidth * scale)
        }

        context.fill(Path(tableRect), with: .color(theme.rink))
        context.stroke(Path(tableRect.insetBy(dx: 1, dy: 1)), with: .color(theme.line), lineWidth: 2)

        let centerY = GameModel.center * scale
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: xOffset, y: centerY))
        centerLine.addLine(to: CGPoint(x: xOffset + GameModel.width * scale, y: centerY))
        context.stroke(centerLine, with: .color(theme.line), lineWidth: 2)

        let centerCircleRect = CGRect(
            x: xOffset + tableWidth / 2 - 90 * scale,
            y: centerY - 90 * scale,
            width: 180 * scale,
            height: 180 * scale
        )
        context.stroke(Path(ellipseIn: centerCircleRect), with: .color(theme.line), lineWidth: 2)

        if !model.settings.airHockeyMode {
            context.drawLayer { layer in
                layer.opacity = 0.9
                layer.fill(Path(CGRect(x: xOffset, y: centerY - 5 * scale, width: tableWidth, height: 10 * scale)), with: .color(theme.accent))
                layer.fill(Path(CGRect(x: xOffset, y: centerY - 2 * scale, width: tableWidth, height: 4 * scale)), with: .color(theme.line))
            }
        }

        let goalWidth = GameModel.goalHalfWidth * 2 * scale
        let goalX = xOffset + (GameModel.width * scale - goalWidth) / 2
        context.stroke(Path(CGRect(x: goalX, y: 2, width: goalWidth, height: 1)), with: .color(theme.accent), lineWidth: 6)
        context.stroke(Path(CGRect(x: goalX, y: tableHeight - 2, width: goalWidth, height: 1)), with: .color(theme.accent), lineWidth: 6)

        strokedCircle(model.opponentMallet, radius: 44, color: theme.opponent, lineWidth: 4)
        filledCircle(model.playerMallet, radius: 44, color: theme.player)
        if model.phase != .waitingForServe || model.isGameOver || model.phase == .training {
            filledCircle(model.puck, radius: model.puckRadius, color: theme.puck, shadow: theme.puck)
        }
    }

    private func tablePoint(_ location: CGPoint, in size: CGSize) -> CGPoint {
        let playableSize = playableSize(from: size)
        let scale = min(playableSize.width / GameModel.width, playableSize.height / GameModel.height)
        let xOffset = (size.width - GameModel.width * scale) / 2
        return CGPoint(
            x: min(max(Double((location.x - xOffset) / scale), 0), GameModel.width),
            y: min(max(Double(min(location.y, playableSize.height) / scale), 0), GameModel.height)
        )
    }
}
