// Logger: appends one line per action to ~/Library/Logs/HeadsetLock.log.

import Foundation

enum Logger {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/HeadsetLock.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // Format: time | trigger | device | result
    static func log(trigger: String, device: String, result: String) {
        let line = "\(formatter.string(from: Date())) | \(trigger) | \(device) | \(result)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
