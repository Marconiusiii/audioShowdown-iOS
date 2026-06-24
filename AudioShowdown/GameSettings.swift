import Foundation
import Combine

enum HapticsLevel: String, CaseIterable, Identifiable {
    case off = "Off"
    case subtle = "Subtle"
    case intense = "Intense"
    var id: Self { self }
}

@MainActor
final class GameSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var airHockeyMode: Bool { didSet { save() } }
    @Published var opponentSkill: Double { didSet { save() } }
    @Published var gameSpeed: Double { didSet { save() } }
    @Published var puckSize: Int { didSet { save() } }
    @Published var puckSound: Int { didSet { save() } }
    @Published var pitchBehavior: Int { didSet { save() } }
    @Published var lowerPitchWhenCloser: Bool { didSet { save() } }
    @Published var pingRate: Int { didSet { save() } }
    @Published var speedsUpWhenApproaching: Bool { didSet { save() } }
    @Published var puckVolume: Double { didSet { save() } }
    @Published var centerCrossingSound: Bool { didSet { save() } }
    @Published var centerCrossingVolume: Double { didSet { save() } }
    @Published var movementSound: Int { didSet { save() } }
    @Published var strikeSound: Int { didSet { save() } }
    @Published var themeIndex: Int { didSet { save() } }
    @Published var volume: Double { didSet { save() } }
    @Published var reverbStyle: Int { didSet { save() } }
    @Published var haptics: HapticsLevel { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        airHockeyMode = defaults.bool(forKey: "airHockeyMode")
        opponentSkill = Self.clamp(defaults.object(forKey: "opponentSkill") as? Double ?? 5, 1...10)
        gameSpeed = Self.clamp(defaults.object(forKey: "gameSpeed") as? Double ?? 5, 1...10)
        puckSize = Self.clamp(defaults.object(forKey: "puckSize") as? Int ?? 0, 0...2)
        puckSound = Self.clamp(defaults.object(forKey: "puckSound") as? Int ?? 0, 0...14)
        pitchBehavior = Self.clamp(defaults.object(forKey: "pitchBehavior") as? Int ?? 0, 0...2)
        lowerPitchWhenCloser = defaults.bool(forKey: "lowerPitch")
        let savedPulseVersion = defaults.integer(forKey: "pulseSettingsVersion")
        if savedPulseVersion >= 2 {
            pingRate = Self.clamp(defaults.object(forKey: "pingRate") as? Int ?? 1, 0...2)
            speedsUpWhenApproaching = defaults.object(forKey: "speedsUpWhenApproaching") as? Bool ?? true
        } else {
            let oldPingRate = Self.clamp(defaults.object(forKey: "pingRate") as? Int ?? 0, 0...3)
            switch oldPingRate {
            case 1: pingRate = 2; speedsUpWhenApproaching = false
            case 2: pingRate = 1; speedsUpWhenApproaching = false
            case 3: pingRate = 0; speedsUpWhenApproaching = false
            default: pingRate = 1; speedsUpWhenApproaching = true
            }
        }
        puckVolume = Self.clamp(defaults.object(forKey: "puckVolume") as? Double ?? 0.8, 0...1)
        centerCrossingSound = defaults.object(forKey: "centerSound") as? Bool ?? true
        centerCrossingVolume = Self.clamp(defaults.object(forKey: "centerVolume") as? Double ?? 0.5, 0...1)
        movementSound = Self.clamp(defaults.object(forKey: "movementSound") as? Int ?? 1, 0...9)
        strikeSound = Self.clamp(defaults.object(forKey: "strikeSound") as? Int ?? 0, 0...9)
        themeIndex = Self.clamp(defaults.object(forKey: "theme") as? Int ?? 0, 0...8)
        volume = Self.clamp(defaults.object(forKey: "volume") as? Double ?? 0.8, 0...1)
        reverbStyle = Self.clamp(defaults.object(forKey: "reverbStyle") as? Int ?? 0, 0...3)
        haptics = HapticsLevel(rawValue: defaults.string(forKey: "haptics") ?? "") ?? .subtle
        if savedPulseVersion < 2 {
            defaults.set(pingRate, forKey: "pingRate")
            defaults.set(speedsUpWhenApproaching, forKey: "speedsUpWhenApproaching")
        }
        defaults.set(2, forKey: "pulseSettingsVersion")
    }

    private func save() {
        defaults.set(airHockeyMode, forKey: "airHockeyMode")
        defaults.set(opponentSkill, forKey: "opponentSkill")
        defaults.set(gameSpeed, forKey: "gameSpeed")
        defaults.set(puckSize, forKey: "puckSize")
        defaults.set(puckSound, forKey: "puckSound")
        defaults.set(pitchBehavior, forKey: "pitchBehavior")
        defaults.set(lowerPitchWhenCloser, forKey: "lowerPitch")
        defaults.set(pingRate, forKey: "pingRate")
        defaults.set(speedsUpWhenApproaching, forKey: "speedsUpWhenApproaching")
        defaults.set(2, forKey: "pulseSettingsVersion")
        defaults.set(puckVolume, forKey: "puckVolume")
        defaults.set(centerCrossingSound, forKey: "centerSound")
        defaults.set(centerCrossingVolume, forKey: "centerVolume")
        defaults.set(movementSound, forKey: "movementSound")
        defaults.set(strikeSound, forKey: "strikeSound")
        defaults.set(themeIndex, forKey: "theme")
        defaults.set(volume, forKey: "volume")
        defaults.set(reverbStyle, forKey: "reverbStyle")
        defaults.set(haptics.rawValue, forKey: "haptics")
    }

    private static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
