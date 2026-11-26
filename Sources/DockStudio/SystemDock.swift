import Foundation

/// Verbergt het echte Dock (autohide met enorme vertraging) en zet het terug.
enum SystemDock {
    private static let modifiedKey = "dockstudio.didModifyDock"
    private static let prevAutohideKey = "dockstudio.prevAutohide"

    static func hide() {
        let d = UserDefaults.standard
        if !d.bool(forKey: modifiedKey) {
            let prev = CFPreferencesCopyAppValue("autohide" as CFString,
                                                 "com.apple.dock" as CFString) as? Bool ?? false
            d.set(prev, forKey: prevAutohideKey)
            d.set(true, forKey: modifiedKey)
        }
        defaults(["write", "com.apple.dock", "autohide", "-bool", "true"])
        defaults(["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        defaults(["write", "com.apple.dock", "autohide-time-modifier", "-float", "0"])
        restartDock()
    }

    static func restore() {
        let d = UserDefaults.standard
        guard d.bool(forKey: modifiedKey) else { return }
        defaults(["delete", "com.apple.dock", "autohide-delay"])
        defaults(["delete", "com.apple.dock", "autohide-time-modifier"])
        if d.bool(forKey: prevAutohideKey) {
            defaults(["write", "com.apple.dock", "autohide", "-bool", "true"])
        } else {
            defaults(["delete", "com.apple.dock", "autohide"])
        }
        d.set(false, forKey: modifiedKey)
        restartDock()
    }

    private static func defaults(_ args: [String]) {
        run("/usr/bin/defaults", args)
    }

    private static func restartDock() {
        run("/usr/bin/killall", ["Dock"])
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
