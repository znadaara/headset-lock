// Settings: UserDefaults keys and default values.

import Foundation

// What happens to the devices the app disconnected, once the Mac wakes or unlocks.
enum AfterWake: String, CaseIterable {
    case reconnect          // reconnect them if they are free (not on your phone)
    case keepOff = "guard"  // block reconnects for the guard time
    case nothing

    var title: String {
        switch self {
        case .reconnect: return "Reconnect if free"
        case .keepOff: return "Keep them off (guard)"
        case .nothing: return "Do nothing"
        }
    }
}

// Who made the app. Shown in About and the app window.
enum Creator {
    static let name = "zackndr"
    static let link = URL(string: "https://www.linkedin.com/in/zackndr/")!
}

enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let onLock = "disconnectOnLock"
        static let onSleep = "disconnectOnSleep"
        static let onScreenOff = "disconnectOnScreenOff"
        static let onSessionSwitch = "disconnectOnSessionSwitch"
        static let afterWake = "afterWake"
        static let takeBack = "takeBackWhenFree"
        static let guardSeconds = "guardSeconds"
        static let exceptions = "neverDisconnect"
    }

    static let guardChoices = [30, 60, 120]

    // Take back from phone: how often to try, and for how long.
    static let takeBackInterval: TimeInterval = 10
    static let takeBackMinutes = 60

    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    static var onLock: Bool {
        get { bool(Key.onLock, default: true) }
        set { defaults.set(newValue, forKey: Key.onLock) }
    }

    static var onSleep: Bool {
        get { bool(Key.onSleep, default: true) }
        set { defaults.set(newValue, forKey: Key.onSleep) }
    }

    static var onScreenOff: Bool {
        get { bool(Key.onScreenOff, default: true) }
        set { defaults.set(newValue, forKey: Key.onScreenOff) }
    }

    static var onSessionSwitch: Bool {
        get { bool(Key.onSessionSwitch, default: true) }
        set { defaults.set(newValue, forKey: Key.onSessionSwitch) }
    }

    static var afterWake: AfterWake {
        get { AfterWake(rawValue: defaults.string(forKey: Key.afterWake) ?? "") ?? .reconnect }
        set { defaults.set(newValue.rawValue, forKey: Key.afterWake) }
    }

    // Keep trying to reconnect, so the earbuds come back once your phone lets go.
    // Off by default: earbuds that connect to two devices, and AirPods, may accept
    // the Mac while they are on the phone and lose the call audio.
    static var takeBack: Bool {
        get { bool(Key.takeBack, default: false) }
        set { defaults.set(newValue, forKey: Key.takeBack) }
    }

    static var guardSeconds: Int {
        get {
            let value = defaults.integer(forKey: Key.guardSeconds)
            return guardChoices.contains(value) ? value : 30
        }
        set { defaults.set(newValue, forKey: Key.guardSeconds) }
    }

    // Addresses of audio devices marked "Never disconnect".
    static var exceptions: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.exceptions) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.exceptions) }
    }
}
