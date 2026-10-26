// BluetoothManager: finds connected audio devices and disconnects them.
// Only major class Audio (0x04) counts. Peripherals (0x05) are never touched.

import Foundation
import IOBluetooth

enum BluetoothManager {
    // kBluetoothDeviceClassMajorAudio
    static let audioMajorClass: BluetoothDeviceClassMajor = 0x04

    // Devices a trigger disconnected. Reconnector tries them after wake.
    static var toReconnect = Set<String>()

    // A disconnect takes a moment to finish, so a device can still look connected
    // right after closeConnection. Lock, sleep and screen off often fire together.
    private static var recentlyClosed: [String: Date] = [:]

    private static func closedJustNow(_ device: IOBluetoothDevice) -> Bool {
        guard let address = device.addressString, let time = recentlyClosed[address] else { return false }
        return Date().timeIntervalSince(time) < 2
    }

    static func isAudio(_ device: IOBluetoothDevice) -> Bool {
        device.deviceClassMajor == audioMajorClass
    }

    static func displayName(_ device: IOBluetoothDevice) -> String {
        device.name ?? device.addressString ?? "Unknown device"
    }

    static func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }

    static func connectedAudioDevices() -> [IOBluetoothDevice] {
        pairedDevices()
            .filter { $0.isConnected() && isAudio($0) }
            .sorted { displayName($0) < displayName($1) }
    }

    static func isException(_ device: IOBluetoothDevice) -> Bool {
        guard let address = device.addressString else { return false }
        return Settings.exceptions.contains(address)
    }

    // Disconnects one device if it is a connected audio device and not an exception.
    // Returns a short result, or nil when there was nothing to do.
    @discardableResult
    static func disconnect(_ device: IOBluetoothDevice, trigger: String, remember: Bool = false) -> String? {
        guard isAudio(device), device.isConnected(), !closedJustNow(device) else { return nil }
        let name = displayName(device)
        if isException(device) {
            Logger.log(trigger: trigger, device: name, result: "skipped (never disconnect)")
            return nil
        }
        let code = device.closeConnection()
        if code == kIOReturnSuccess, let address = device.addressString {
            recentlyClosed[address] = Date()
            if remember { toReconnect.insert(address) }
        }
        let result = code == kIOReturnSuccess ? "disconnected" : "failed (code \(code))"
        Logger.log(trigger: trigger, device: name, result: result)
        return "\(name) \(result)"
    }

    // Disconnects every connected audio device except the exceptions.
    // Returns a summary, or nil when nothing was connected.
    @discardableResult
    static func disconnectAll(trigger: String, logWhenNone: Bool, remember: Bool = false) -> String? {
        let results = connectedAudioDevices().compactMap { disconnect($0, trigger: trigger, remember: remember) }
        if results.isEmpty {
            if logWhenNone {
                Logger.log(trigger: trigger, device: "-", result: "no audio device to disconnect")
            }
            return nil
        }
        return results.joined(separator: ", ")
    }
}
