import Foundation

enum AppInfo {
    /// Read from Info.plist so renaming the app means changing one place.
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Multipaste"
}
