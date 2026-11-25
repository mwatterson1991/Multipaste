import Foundation

/// Off unless the app is started with MULTIPASTE_LOG set. The automatic build uses it to check that copies are being stacked.
enum Log {
    private static let enabled = ProcessInfo.processInfo.environment["MULTIPASTE_LOG"] != nil

    static func note(_ message: String) {
        guard enabled else { return }
        print(message)
        fflush(stdout)
    }
}
