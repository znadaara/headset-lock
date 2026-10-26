// AppModel: shared state for the app window. Settings live in UserDefaults (Settings.swift).

import Combine
import Foundation
import IOBluetooth

struct AudioDevice: Identifiable, Hashable {
    let id: String  // Bluetooth address
    let name: String
    let connected: Bool
    let never: Bool
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var lastAction = "No action yet"
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var guardLeft = 0
    @Published private(set) var watchMinutesLeft = 0

    // Wired up by AppDelegate.
    var guardUntil: () -> Date? = { nil }
    var disconnectAll: () -> Void = {}
    var disconnectDevice: (String) -> Void = { _ in }
    var afterWakeChanged: (AfterWake) -> Void = { _ in }
    var watchUntil: () -> Date? = { nil }
    var takeBackChanged: (Bool) -> Void = { _ in }

    private var timer: Timer?

    var connectedCount: Int { devices.filter(\.connected).count }

    // The window polls once a second while it is open.
    func startRefreshing() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let exceptions = Settings.exceptions
        devices = BluetoothManager.pairedDevices()
            .filter { BluetoothManager.isAudio($0) && $0.addressString != nil }
            .map { d in
                AudioDevice(id: d.addressString!, name: BluetoothManager.displayName(d),
                            connected: d.isConnected(), never: exceptions.contains(d.addressString!))
            }
            .sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
        let left = guardUntil().map { Int($0.timeIntervalSinceNow.rounded(.up)) } ?? 0
        guardLeft = max(0, left)
        let watch = watchUntil().map { Int(($0.timeIntervalSinceNow / 60).rounded(.up)) } ?? 0
        watchMinutesLeft = max(0, watch)
    }

    func setNever(_ address: String, _ on: Bool) {
        var list = Settings.exceptions
        if on { list.insert(address) } else { list.remove(address) }
        Settings.exceptions = list
        refresh()
    }

    // MARK: Settings as bindable properties

    var onLock: Bool {
        get { Settings.onLock }
        set { objectWillChange.send(); Settings.onLock = newValue }
    }

    var onSleep: Bool {
        get { Settings.onSleep }
        set { objectWillChange.send(); Settings.onSleep = newValue }
    }

    var onScreenOff: Bool {
        get { Settings.onScreenOff }
        set { objectWillChange.send(); Settings.onScreenOff = newValue }
    }

    var onSessionSwitch: Bool {
        get { Settings.onSessionSwitch }
        set { objectWillChange.send(); Settings.onSessionSwitch = newValue }
    }

    var afterWake: AfterWake {
        get { Settings.afterWake }
        set { objectWillChange.send(); afterWakeChanged(newValue) }
    }

    var takeBack: Bool {
        get { Settings.takeBack }
        set { objectWillChange.send(); takeBackChanged(newValue) }
    }

    var guardSeconds: Int {
        get { Settings.guardSeconds }
        set { objectWillChange.send(); Settings.guardSeconds = newValue }
    }
}
