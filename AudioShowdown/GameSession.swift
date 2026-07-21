import Combine
import Foundation

@MainActor
final class GameSession: ObservableObject {
    enum Mode: String, Codable {
        case singlePlayer
        case practice
        case multiplayer
    }

    enum Role: String, Codable {
        case local
        case host
        case guest
    }

    let model: GameModel
    let mode: Mode
    let role: Role

    private var cancellable: AnyCancellable?
    private var pendingInputs: [GameInput] = []
    private var pendingSnapshots: [GameSnapshot] = []
    private var pendingEvents: [GameEvent] = []
    private var incomingEvents: [GameEvent] = []

    var snapshot: GameSnapshot { model.snapshot }
    var isPaused: Bool { model.isPaused }
    var isGameOver: Bool { model.isGameOver }
    var scoreText: String { model.scoreText }

    var appliesLocalInputToModel: Bool {
        mode != .multiplayer || role != .guest
    }

    var appliesRemoteInputToModel: Bool {
        mode == .multiplayer && role == .host
    }

    var appliesRemoteSnapshotToModel: Bool {
        mode == .multiplayer && role == .guest
    }

    init(model: GameModel, mode: Mode, role: Role) {
        self.model = model
        self.mode = mode
        self.role = role
        cancellable = model.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    convenience init(settings: GameSettings, training: Bool, audio: GameAudioEngine) {
        let model = GameModel(settings: settings, training: training, audio: audio)
        self.init(model: model, mode: training ? .practice : .singlePlayer, role: .local)
    }

    func handleLocalInput(_ input: GameInput) {
        if mode == .multiplayer {
            pendingInputs.append(input)
        }
        if appliesLocalInputToModel {
            model.handleInput(input)
        }
    }

    func handleRemoteInput(_ input: GameInput) {
        guard appliesRemoteInputToModel else { return }
        model.handleInput(input)
    }

    func handleRemoteSnapshot(_ snapshot: GameSnapshot) {
        guard appliesRemoteSnapshotToModel else { return }
        model.applySnapshot(snapshot)
    }

    func handleRemoteEvents(_ events: [GameEvent]) {
        guard mode == .multiplayer else { return }
        incomingEvents.append(contentsOf: events)
    }

    func tick(_ date: Date) {
        model.tick(date)
        if mode == .multiplayer && role == .host {
            pendingSnapshots.append(model.snapshot)
        }
    }

    func drainOutgoingInputs() -> [GameInput] {
        defer { pendingInputs.removeAll() }
        return pendingInputs
    }

    func drainOutgoingSnapshots() -> [GameSnapshot] {
        defer { pendingSnapshots.removeAll() }
        return pendingSnapshots
    }

    func drainOutgoingEvents() -> [GameEvent] {
        let events = model.drainEvents()
        if mode == .multiplayer {
            pendingEvents.append(contentsOf: events)
            defer { pendingEvents.removeAll() }
            return pendingEvents
        }
        return events
    }

    func drainIncomingEvents() -> [GameEvent] {
        defer { incomingEvents.removeAll() }
        return incomingEvents
    }

    func announceInitialState() {
        model.announceInitialState()
    }

    func togglePause() {
        model.togglePause()
    }

    func stopContinuousAudio() {
        model.stopContinuousAudio()
    }
}
