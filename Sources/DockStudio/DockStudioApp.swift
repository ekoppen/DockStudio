import SwiftUI
import AppKit

/// Icoon voor Dokko in Cmd-Tab (getekend, geen bestand nodig).
enum AppIcon {
    static func make() -> NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let size = NSSize(width: 512, height: 512)
        let img = NSImage(size: size)
        img.lockFocus()

        let bg = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 432, height: 432),
                              xRadius: 96, yRadius: 96)
        NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.25, blue: 0.88, alpha: 1),
                            NSColor(srgbRed: 0.92, green: 0.30, blue: 0.62, alpha: 1)])?
            .draw(in: bg, angle: -60)

        let bar = NSBezierPath(roundedRect: NSRect(x: 92, y: 118, width: 328, height: 104),
                               xRadius: 44, yRadius: 44)
        NSColor.white.withAlphaComponent(0.88).setFill()
        bar.fill()

        for i in 0..<4 {
            let tile = NSBezierPath(
                roundedRect: NSRect(x: 118 + CGFloat(i) * 76, y: 140, width: 60, height: 60),
                xRadius: 16, yRadius: 16)
            NSColor(srgbRed: 0.30, green: 0.20, blue: 0.70, alpha: 0.92).setFill()
            tile.fill()
        }

        img.unlockFocus()
        return img
    }
}

/// Hulp voor het instellingenvenster.
enum SettingsWindow {
    static func isSettings(_ w: NSWindow) -> Bool {
        w.title == "Dokko" && !(w is NSPanel)
    }

    /// Past "vastpinnen" en gedrag bij wisselen van app toe op het instellingenvenster.
    static func apply() {
        let floating = UserDefaults.standard.bool(forKey: "dockstudio.settingsFloating")
        for w in NSApp.windows where isSettings(w) {
            w.hidesOnDeactivate = false
            w.level = floating ? .floating : .normal
            w.collectionBehavior = floating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // geen eigen icoon in het Dock
        NSApp.applicationIconImage = AppIcon.make()

        // Zolang het instellingenvenster open is, tonen we Dokko als gewone app
        // (Cmd-Tab, activeren), zodat het venster niet zoekraakt bij het wisselen van app.
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, SettingsWindow.isSettings(w) else { return }
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                // Na het wisselen van beleid pas activeren, anders krijgt het venster geen toetsenbord.
                DispatchQueue.main.async {
                    NSApp.applicationIconImage = AppIcon.make()
                    NSApp.activate(ignoringOtherApps: true)
                    w.makeKeyAndOrderFront(nil)
                }
            }
            SettingsWindow.apply()
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, SettingsWindow.isSettings(w) else { return }
            DispatchQueue.main.async {
                let stillOpen = NSApp.windows.contains { SettingsWindow.isSettings($0) && $0.isVisible && $0 != w }
                if !stillOpen { NSApp.setActivationPolicy(.accessory) }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        DockWindowController.shared.start()
        WindowAvoider.shared.start()
        WallpaperWatcher.shared.start()
        HAStore.shared.start()
        Updater.shared.checkOnLaunch()
        TileStore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Altijd het echte Dock terugzetten bij afsluiten.
        SystemDock.restore()
    }
}

@main
struct DockStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var store = ThemeStore.shared

    var body: some Scene {
        MenuBarExtra("Dokko", systemImage: "dock.rectangle") {
            MenuContent(store: store)
        }

        Window("Dokko", id: "settings") {
            SettingsView(store: store)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var store: ThemeStore
    @ObservedObject var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Mijn dock tonen", isOn: $store.dockEnabled)
        Button("Instellingen…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(updater.availableVersion.map { "Installeer update \($0)…" } ?? "Zoek naar updates…") {
            Task {
                if updater.availableVersion != nil { await updater.install() }
                else { await updater.check() }
            }
        }
        Divider()
        Button("Herstel echte Dock") {
            DockWindowController.shared.restoreNow()
        }
        Button("Stop Dokko") {
            NSApp.terminate(nil)
        }
    }
}
