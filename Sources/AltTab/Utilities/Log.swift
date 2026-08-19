import Foundation

/// Opt-in tracing: `ALTTAB_DEBUG=1 /Applications/AltTab.app/Contents/MacOS/AltTab`
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["ALTTAB_DEBUG"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write("[AltTab] \(message())\n".data(using: .utf8)!)
    }
}
