// ReconnectGuard: for a short window after wake or unlock, disconnects any
// audio device that reconnects by itself. After the window, connections work as normal.

import Foundation
import IOBluetooth

final class ReconnectGuard: NSObject {
    private var notification: IOBluetoothUserNotification?
    private var closeWork: DispatchWorkItem?
    private(set) var openUntil: Date?

    // Called with a summary after the guard disconnects a device.
    var onAction: (String) -> Void = { _ in }

    var isOpen: Bool { openUntil.map { $0 > Date() } ?? false }

    func open(seconds: Int, trigger: Trigger) {
        close()
        openUntil = Date().addingTimeInterval(TimeInterval(seconds))
        notification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                  selector: #selector(deviceConnected(_:device:)))
        Logger.log(trigger: trigger.rawValue, device: "-", result: "guard open for \(seconds) s")

        let work = DispatchWorkItem { [weak self] in
            self?.close()
            Logger.log(trigger: "guard", device: "-", result: "guard closed")
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
    }

    func close() {
        closeWork?.cancel()
        closeWork = nil
        notification?.unregister()
        notification = nil
        openUntil = nil
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard isOpen, BluetoothManager.isAudio(device) else { return }
        // Give the connection a moment to finish before closing it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.isOpen else { return }
            if let result = BluetoothManager.disconnect(device, trigger: "guard") {
                self.onAction(result)
            }
        }
    }
}
