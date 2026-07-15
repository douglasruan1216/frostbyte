import Foundation

/// Caps Roblox's frame rate by writing the `DFIntTaskSchedulerTargetFps` fast
/// flag into Roblox's client settings. This is a normal config file (not
/// automation) — it just tells the engine to stop rendering more frames than
/// asked, which cuts GPU/CPU heat a lot while you're actively playing.
///
/// Takes effect the next time Roblox launches.
enum FPSCap {
    static let path = ("~/Library/Roblox/ClientSettings/ClientAppSettings.json" as NSString)
        .expandingTildeInPath
    static let flag = "DFIntTaskSchedulerTargetFps"

    /// The currently configured cap, or nil if uncapped.
    static func current() -> Int? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let n = obj[flag] as? Int { return n }
        if let d = obj[flag] as? Double { return Int(d) }
        if let s = obj[flag] as? String, let n = Int(s) { return n }
        return nil
    }

    /// Set the cap (nil removes it / goes back to unlimited). Preserves any
    /// other flags already in the file. Returns true on success.
    @discardableResult
    static func set(_ fps: Int?) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var obj: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = existing
        }
        if let fps { obj[flag] = fps } else { obj.removeValue(forKey: flag) }

        guard let out = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return false }
        return (try? out.write(to: URL(fileURLWithPath: path))) != nil
    }
}
