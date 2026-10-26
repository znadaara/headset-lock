// EventMonitor: listens for lock, sleep, screen off, session switch, wake and unlock.

import AppKit

enum Trigger: String {
    case lock
    case sleep
    case screenOff = "screen-off"
    case sessionSwitch = "session-switch"
    case wake
    case unlock
    case screenOn = "screen-on"
    case sessionReturn = "session-return"
}

final class EventMonitor: NSObject {
    // Called when a disconnect trigger fires. Runs synchronously on the main thread.
    var onDisconnect: (Trigger) -> Void = { _ in }
    // Called after wake, unlock, screen on or switching back to this user.
    var onWake: (Trigger) -> Void = { _ in }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(locked),
                                name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(unlocked),
                                name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResigned),
                              name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
        // Screen off and user switch can disconnect without a sleep or lock,
        // so their opposites must reconnect too.
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionReturned),
                              name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func locked() {
        if Settings.onLock { onDisconnect(.lock) }
    }

    // Lid close and sleep. The disconnect runs before this method returns,
    // because the Mac may sleep as soon as it does.
    @objc private func willSleep() {
        if Settings.onSleep { onDisconnect(.sleep) }
    }

    @objc private func screensDidSleep() {
        if Settings.onScreenOff { onDisconnect(.screenOff) }
    }

    @objc private func sessionResigned() {
        if Settings.onSessionSwitch { onDisconnect(.sessionSwitch) }
    }

    @objc private func didWake() { onWake(.wake) }

    @objc private func unlocked() { onWake(.unlock) }

    @objc private func screensDidWake() { onWake(.screenOn) }

    @objc private func sessionReturned() { onWake(.sessionReturn) }
}
