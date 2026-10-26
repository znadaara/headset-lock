// AppDelegate: menu bar icon, menu, and the glue between events and Bluetooth.

import AppKit
import IOBluetooth
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let events = EventMonitor()
    private let reconnectGuard = ReconnectGuard()
    private let reconnector = Reconnector()
    private var rechecks: [DispatchWorkItem] = []
    private let mainWindow = MainWindowController()
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Headset Lock")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // v1 used a login item. The LaunchAgent replaces it, so remove it to avoid two copies.
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }

        events.onDisconnect = { [weak self] trigger in self?.handleDisconnect(trigger) }
        events.onWake = { [weak self] trigger in self?.handleWake(trigger) }
        reconnectGuard.onAction = { [weak self] result in self?.setLast(result, trigger: "guard") }
        reconnector.onAction = { [weak self] result in self?.setLast(result, trigger: "reconnect") }
        events.start()

        model.guardUntil = { [weak self] in
            guard let g = self?.reconnectGuard, g.isOpen else { return nil }
            return g.openUntil
        }
        model.disconnectAll = { [weak self] in self?.disconnectNow() }
        model.disconnectDevice = { [weak self] address in self?.disconnectDevice(address) }
        model.afterWakeChanged = { [weak self] mode in self?.setAfterWake(mode) }
        model.watchUntil = { [weak self] in
            guard let r = self?.reconnector, r.isWatching else { return nil }
            return r.watchUntil
        }
        model.takeBackChanged = { [weak self] on in self?.setTakeBack(on) }
        Logger.log(trigger: "launch", device: "-", result: "Headset Lock started")
        installLaunchAgentIfNeeded()
    }

    // A copy dragged in from the DMG has no LaunchAgent yet. Add one so it
    // starts at every login. build.sh --install adds it itself.
    private func installLaunchAgentIfNeeded() {
        guard Bundle.main.bundlePath == "/Applications/Headset Lock.app",
              let source = Bundle.main.url(forResource: "so.zackndr.headsetlock", withExtension: "plist") else { return }
        let agents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let target = agents.appendingPathComponent("so.zackndr.headsetlock.plist")
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            Logger.log(trigger: "install", device: "-", result: "added LaunchAgent, starts at login")
        } catch {
            Logger.log(trigger: "install", device: "-", result: "could not add LaunchAgent: \(error.localizedDescription)")
        }
    }

    // Opening the app again (Finder, Spotlight) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    // MARK: Actions

    private func setLast(_ text: String, trigger: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        model.lastAction = "\(text) (\(trigger), \(time))"
    }

    private func cancelRechecks() {
        rechecks.forEach { $0.cancel() }
        rechecks = []
    }

    private func handleDisconnect(_ trigger: Trigger) {
        reconnectGuard.close()
        reconnector.cancel()
        if let result = BluetoothManager.disconnectAll(trigger: trigger.rawValue, logWhenNone: true, remember: true) {
            setLast(result, trigger: trigger.rawValue)
        }
        // macOS sometimes reconnects audio a few seconds later. Check again.
        // These timers pause during sleep, so wake cancels them.
        cancelRechecks()
        for delay in [3, 8] {
            let work = DispatchWorkItem { [weak self] in
                let name = "\(trigger.rawValue)-recheck-\(delay)s"
                if let result = BluetoothManager.disconnectAll(trigger: name, logWhenNone: false, remember: true) {
                    self?.setLast(result, trigger: name)
                }
            }
            rechecks.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: work)
        }
    }

    private func handleWake(_ trigger: Trigger) {
        cancelRechecks()
        switch Settings.afterWake {
        case .reconnect:
            reconnector.start(trigger: trigger)
        case .keepOff:
            BluetoothManager.toReconnect.removeAll()
            reconnectGuard.open(seconds: Settings.guardSeconds, trigger: trigger)
        case .nothing:
            BluetoothManager.toReconnect.removeAll()
        }
    }

    private func setTakeBack(_ on: Bool) {
        Settings.takeBack = on
        if !on { reconnector.stopWatching() }
    }

    private func setAfterWake(_ mode: AfterWake) {
        Settings.afterWake = mode
        if mode != .keepOff { reconnectGuard.close() }
        if mode != .reconnect { reconnector.cancel() }
    }

    // MARK: Menu

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func toggleItem(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("Headset Lock"))
        menu.addItem(disabledItem("Last: \(model.lastAction)"))
        if let until = reconnectGuard.openUntil, reconnectGuard.isOpen {
            let left = Int(until.timeIntervalSinceNow.rounded(.up))
            menu.addItem(disabledItem("Guard open: \(left) s left"))
        }
        if let until = reconnector.watchUntil, reconnector.isWatching {
            let left = Int((until.timeIntervalSinceNow / 60).rounded(.up))
            menu.addItem(disabledItem("Waiting for your phone to let go (\(left) min left)"))
        }
        menu.addItem(.separator())

        menu.addItem(disabledItem("Connected audio devices"))
        let devices = BluetoothManager.connectedAudioDevices()
        if devices.isEmpty {
            menu.addItem(disabledItem("    None connected"))
        }
        for device in devices {
            let item = NSMenuItem(title: "    " + BluetoothManager.displayName(device), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let never = toggleItem("Never disconnect", on: BluetoothManager.isException(device),
                                   action: #selector(toggleException(_:)))
            never.representedObject = device.addressString
            sub.addItem(never)
            item.submenu = sub
            menu.addItem(item)
        }
        let saved = Settings.exceptions
        if !saved.isEmpty {
            let item = NSMenuItem(title: "Never disconnect list", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let names = Dictionary(BluetoothManager.pairedDevices().compactMap { d in
                d.addressString.map { ($0, BluetoothManager.displayName(d)) }
            }, uniquingKeysWith: { first, _ in first })
            for address in saved.sorted() {
                let entry = toggleItem(names[address] ?? address, on: true, action: #selector(toggleException(_:)))
                entry.representedObject = address
                sub.addItem(entry)
            }
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(toggleItem("Disconnect on lock", on: Settings.onLock, action: #selector(toggleLock)))
        menu.addItem(toggleItem("Disconnect on lid close and sleep", on: Settings.onSleep, action: #selector(toggleSleep)))
        menu.addItem(toggleItem("Disconnect on screen off", on: Settings.onScreenOff, action: #selector(toggleScreenOff)))
        menu.addItem(toggleItem("Disconnect on user switch", on: Settings.onSessionSwitch, action: #selector(toggleSessionSwitch)))
        menu.addItem(.separator())

        menu.addItem(disabledItem("After wake"))
        for mode in AfterWake.allCases {
            let item = toggleItem("    " + mode.title, on: Settings.afterWake == mode, action: #selector(chooseAfterWake(_:)))
            item.representedObject = mode.rawValue
            menu.addItem(item)
        }
        if Settings.afterWake == .reconnect {
            menu.addItem(toggleItem("    Take back from phone when free", on: Settings.takeBack,
                                    action: #selector(toggleTakeBack)))
        }
        if Settings.afterWake == .keepOff {
            let guardTime = NSMenuItem(title: "    Guard time", action: nil, keyEquivalent: "")
            let times = NSMenu()
            for seconds in Settings.guardChoices {
                let item = toggleItem("\(seconds) seconds", on: Settings.guardSeconds == seconds,
                                      action: #selector(chooseGuardTime(_:)))
                item.tag = seconds
                times.addItem(item)
            }
            guardTime.submenu = times
            menu.addItem(guardTime)
        }
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Headset Lock…", action: #selector(openWindow), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        let now = NSMenuItem(title: "Disconnect now", action: #selector(disconnectNow), keyEquivalent: "d")
        now.target = self
        menu.addItem(now)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Headset Lock", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Headset Lock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleException(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        var list = Settings.exceptions
        if list.contains(address) { list.remove(address) } else { list.insert(address) }
        Settings.exceptions = list
    }

    @objc private func toggleLock() { Settings.onLock.toggle() }
    @objc private func toggleSleep() { Settings.onSleep.toggle() }
    @objc private func toggleScreenOff() { Settings.onScreenOff.toggle() }
    @objc private func toggleSessionSwitch() { Settings.onSessionSwitch.toggle() }

    @objc private func toggleTakeBack() { setTakeBack(!Settings.takeBack) }

    @objc private func chooseAfterWake(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = AfterWake(rawValue: raw) else { return }
        setAfterWake(mode)
    }

    @objc private func chooseGuardTime(_ sender: NSMenuItem) { Settings.guardSeconds = sender.tag }

    @objc private func openWindow() { mainWindow.show() }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(string: "Created by \(Creator.name)\n",
                                                attributes: [.font: NSFont.systemFont(ofSize: 11)])
        credits.append(NSAttributedString(string: "LinkedIn", attributes: [.link: Creator.link,
                                                                          .font: NSFont.systemFont(ofSize: 11)]))
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        credits.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func disconnectDevice(_ address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        reconnector.forget(address)
        let result = BluetoothManager.disconnect(device, trigger: "manual")
        setLast(result ?? "Nothing to disconnect", trigger: "manual")
    }

    // A manual disconnect means you want them off, so nothing reconnects them.
    @objc private func disconnectNow() {
        reconnectGuard.close()
        reconnector.cancel()
        BluetoothManager.toReconnect.removeAll()
        let result = BluetoothManager.disconnectAll(trigger: "manual", logWhenNone: true)
        setLast(result ?? "No audio device to disconnect", trigger: "manual")
    }
}
