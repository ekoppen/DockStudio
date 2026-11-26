import AppKit
import SwiftUI

struct DockItem: Identifiable {
    let id: String
    let name: String
    let url: URL
    let icon: NSImage
    let isRunning: Bool
    let isTrash: Bool
    var haEntity: String? = nil   // Home Assistant-item
}

/// Haalt de apps op die in het echte Dock staan, plus draaiende apps.
final class DockModel: ObservableObject {
    static let shared = DockModel()

    @Published var items: [DockItem] = []
    @Published var bouncing: Set<String> = []

    init() {
        reload()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            }
        }
    }

    func reload() {
        let running = NSWorkspace.shared.runningApplications
        let runningURLs = Set(running.compactMap { $0.bundleURL?.standardizedFileURL.path })

        var urls: [URL] = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        urls += Self.pinnedAppURLs()

        // Draaiende apps die niet vastgepind zijn
        let known = Set(urls.map { $0.standardizedFileURL.path })
        for app in running where app.activationPolicy == .regular {
            guard let u = app.bundleURL, u.path != Bundle.main.bundleURL.path else { continue }
            if !known.contains(u.standardizedFileURL.path) { urls.append(u) }
        }

        var seen = Set<String>()
        var result: [DockItem] = []
        for u in urls {
            let path = u.standardizedFileURL.path
            guard seen.insert(path).inserted,
                  FileManager.default.fileExists(atPath: path) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: path)
            result.append(DockItem(
                id: path,
                name: FileManager.default.displayName(atPath: path),
                url: u,
                icon: icon,
                isRunning: runningURLs.contains(path),
                isTrash: false
            ))
        }

        // Home Assistant-items
        let ha = HAStore.shared
        if ha.config.enabled {
            for e in ha.config.dockEntities {
                let on = ha.isOn(e.id)
                result.append(DockItem(
                    id: "ha:\(e.id)", name: e.name, url: URL(fileURLWithPath: "/"),
                    icon: HAIcon.make(domain: e.domain, on: on),
                    isRunning: on, isTrash: false, haEntity: e.id
                ))
            }
        }

        // Prullenmand
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        result.append(DockItem(
            id: "trash", name: "Prullenmand", url: trash,
            icon: NSWorkspace.shared.icon(forFile: trash.path),
            isRunning: false, isTrash: true
        ))

        items = result
        let runningIDs = Set(result.filter { $0.isRunning }.map { $0.id })
        bouncing = bouncing.subtracting(runningIDs)
    }

    /// Leest de vastgepinde apps uit de Dock-voorkeuren.
    static func pinnedAppURLs() -> [URL] {
        guard let apps = CFPreferencesCopyAppValue("persistent-apps" as CFString,
                                                   "com.apple.dock" as CFString) as? [[String: Any]]
        else { return [] }
        return apps.compactMap { entry in
            guard let tile = entry["tile-data"] as? [String: Any],
                  let file = tile["file-data"] as? [String: Any],
                  let str = file["_CFURLString"] as? String,
                  let url = URL(string: str) else { return nil }
            return url
        }
    }

    func open(_ item: DockItem) {
        if let entity = item.haEntity {
            HAStore.shared.activate(entity)
            return
        }
        if item.isTrash {
            NSWorkspace.shared.open(item.url)
        } else {
            if !item.isRunning && ThemeStore.shared.theme.launchBounce {
                bouncing.insert(item.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.bouncing.remove(item.id)
                }
            }
            NSWorkspace.shared.openApplication(at: item.url,
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
