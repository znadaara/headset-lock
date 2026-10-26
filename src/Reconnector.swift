// Reconnector: after wake or unlock, reconnects the audio devices a trigger disconnected.
// Single-link earbuds that are on your phone refuse the connection, so the phone keeps them.
// With Take back on, it keeps trying every 10 s for up to an hour, so the earbuds
// come back to the Mac as soon as you disconnect them from your phone.

import Foundation
import IOBluetooth

final class Reconnector: NSObject {
    // Bluetooth needs a moment after wake, so try a few times.
    private let delays = [1, 4, 10]
    private var work: [DispatchWorkItem] = []
    private var inFlight = Set<String>()
    private var finalRound = false
    private var watchTimer: Timer?
    private(set) var watchUntil: Date?

    var isWatching: Bool { watchUntil.map { $0 > Date() } ?? false }

    // Called with a summary after a device reconnects.
    var onAction: (String) -> Void = { _ in }

    func start(trigger: Trigger) {
        cancel()
        let count = BluetoothManager.toReconnect.count
        guard count > 0 else { return }
        Logger.log(trigger: trigger.rawValue, device: "-", result: "reconnecting \(count) device(s) if free")
        let last = delays.count - 1
        for (index, delay) in delays.enumerated() {
            let item = DispatchWorkItem { [weak self] in
                self?.tryAll(final: index == last)
            }
            work.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: item)
        }
    }

    func cancel() {
        work.forEach { $0.cancel() }
        work = []
        finalRound = false
        stopWatching()
    }

    // Stops waiting for the phone to let go. The devices stay remembered for the next wake.
    func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        watchUntil = nil
    }

    // Forget one device, for example after you disconnect it by hand.
    func forget(_ address: String) {
        BluetoothManager.toReconnect.remove(address)
        if BluetoothManager.toReconnect.isEmpty { cancel() }
    }

    private func startWatching() {
        guard watchTimer == nil, !BluetoothManager.toReconnect.isEmpty else { return }
        watchUntil = Date().addingTimeInterval(TimeInterval(Settings.takeBackMinutes * 60))
        let names = BluetoothManager.toReconnect.compactMap { IOBluetoothDevice(addressString: $0) }
            .map(BluetoothManager.displayName).sorted().joined(separator: ", ")
        Logger.log(trigger: "take-back", device: names,
                   result: "not free, trying every \(Int(Settings.takeBackInterval)) s for \(Settings.takeBackMinutes) min")
        watchTimer = Timer.scheduledTimer(withTimeInterval: Settings.takeBackInterval, repeats: true) { [weak self] _ in
            self?.watchTick()
        }
    }

    private func watchTick() {
        guard let until = watchUntil, until > Date(), Settings.takeBack else {
            let names = BluetoothManager.toReconnect.compactMap { IOBluetoothDevice(addressString: $0) }
                .map(BluetoothManager.displayName).sorted().joined(separator: ", ")
            Logger.log(trigger: "take-back", device: names.isEmpty ? "-" : names, result: "stopped trying")
            BluetoothManager.toReconnect.removeAll()
            stopWatching()
            return
        }
        tryAll(final: false)
    }

    private func tryAll(final: Bool) {
        finalRound = final
        for address in BluetoothManager.toReconnect {
            guard let device = IOBluetoothDevice(addressString: address) else {
                BluetoothManager.toReconnect.remove(address)
                continue
            }
            if device.isConnected() {
                finished(device, result: "reconnected")
                continue
            }
            guard !inFlight.contains(address) else { continue }
            inFlight.insert(address)
            // Async: the result arrives in connectionComplete(_:status:).
            let code = device.openConnection(self)
            if code != kIOReturnSuccess {
                inFlight.remove(address)
                if final { notFree(device, code: code) }
            }
        }
        if BluetoothManager.toReconnect.isEmpty { cancel() }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard let device, let address = device.addressString else { return }
        inFlight.remove(address)
        guard BluetoothManager.toReconnect.contains(address) else { return }
        if status == kIOReturnSuccess {
            finished(device, result: "reconnected")
        } else if finalRound && !isWatching {
            notFree(device, code: status)
        }
    }

    private func finished(_ device: IOBluetoothDevice, result: String) {
        guard let address = device.addressString else { return }
        BluetoothManager.toReconnect.remove(address)
        let name = BluetoothManager.displayName(device)
        Logger.log(trigger: "reconnect", device: name, result: result)
        onAction("\(name) \(result)")
        if BluetoothManager.toReconnect.isEmpty { cancel() }
    }

    // The wake attempts failed: the device is on your phone or switched off.
    private func notFree(_ device: IOBluetoothDevice, code: IOReturn) {
        guard let address = device.addressString else { return }
        if Settings.takeBack {
            startWatching()
            return
        }
        BluetoothManager.toReconnect.remove(address)
        Logger.log(trigger: "reconnect", device: BluetoothManager.displayName(device),
                   result: "not free, left alone (on your phone or switched off, code \(code))")
    }
}
