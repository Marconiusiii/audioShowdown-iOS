import Foundation

struct GameInput: Codable, Equatable {
    enum Phase: String, Codable {
        case began
        case moved
        case ended
    }

    var phase: Phase
    var x: Double
    var y: Double
    var wasTap: Bool?
}
