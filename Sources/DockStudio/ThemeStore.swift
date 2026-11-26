import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    private let themesKey = "dockstudio.themes"
    private let selectedKey = "dockstudio.selected"
    private let enabledKey = "dockstudio.enabled"
    private let modeKey = "dockstudio.windowMode"
    private let followKey = "dockstudio.followWallpaper"
    private let followStyleKey = "dockstudio.followStyle"
    private let hooksKey = "dockstudio.hooksEnabled"

    @Published var themes: [DockTheme] { didSet { save() } }
    @Published var selectedID: UUID {
        didSet {
            save()
            if oldValue != selectedID {
                HookRunner.run(theme: theme)
                if HAStore.shared.config.iconStyle?.useThemeAccent == true { DockModel.shared.reload() }
            }
        }
    }
    @Published var dockEnabled: Bool { didSet { save() } }
    @Published var windowMode: WindowMode { didSet { save() } }
    @Published var status: String = ""
    @Published var followWallpaper: Bool { didSet { save() } }
    @Published var followStyle: DockStyle { didSet { save() } }
    @Published var hooksEnabled: Bool { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        var loaded = Presets.all
        if let data = d.data(forKey: themesKey),
           let decoded = try? JSONDecoder().decode([DockTheme].self, from: data),
           !decoded.isEmpty {
            loaded = decoded
        }
        var selected = loaded[0].id
        if let s = d.string(forKey: selectedKey), let u = UUID(uuidString: s),
           loaded.contains(where: { $0.id == u }) {
            selected = u
        }
        themes = loaded
        selectedID = selected
        dockEnabled = d.bool(forKey: enabledKey)
        windowMode = WindowMode(rawValue: d.string(forKey: modeKey) ?? "") ?? .reserve
        followWallpaper = d.bool(forKey: followKey)
        followStyle = DockStyle(rawValue: d.string(forKey: followStyleKey) ?? "") ?? .glass
        hooksEnabled = d.bool(forKey: hooksKey)
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(themes) { d.set(data, forKey: themesKey) }
        d.set(selectedID.uuidString, forKey: selectedKey)
        d.set(dockEnabled, forKey: enabledKey)
        d.set(windowMode.rawValue, forKey: modeKey)
        d.set(followWallpaper, forKey: followKey)
        d.set(followStyle.rawValue, forKey: followStyleKey)
        d.set(hooksEnabled, forKey: hooksKey)
    }

    var selectedIndex: Int? { themes.firstIndex { $0.id == selectedID } }
    var theme: DockTheme { selectedIndex.map { themes[$0] } ?? themes[0] }

    func binding<T>(_ kp: WritableKeyPath<DockTheme, T>) -> Binding<T> {
        Binding(
            get: { self.theme[keyPath: kp] },
            set: { if let i = self.selectedIndex { self.themes[i][keyPath: kp] = $0 } }
        )
    }

    func colorBinding(_ kp: WritableKeyPath<DockTheme, RGBA>) -> Binding<Color> {
        Binding(
            get: { self.theme[keyPath: kp].color },
            set: { if let i = self.selectedIndex { self.themes[i][keyPath: kp] = RGBA(color: $0) } }
        )
    }

    func duplicateSelected() {
        var copy = theme
        copy.id = UUID()
        copy.name += " kopie"
        themes.append(copy)
        selectedID = copy.id
    }

    func deleteSelected() {
        guard themes.count > 1, let i = selectedIndex else { return }
        themes.remove(at: i)
        selectedID = themes[max(0, i - 1)].id
    }

    func resetToPresets() {
        themes = Presets.all
        selectedID = themes[0].id
    }

    // MARK: Importeren / exporteren

    func exportSelected() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(theme.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(theme) {
            try? data.write(to: url)
        }
    }

    func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        var imported: [DockTheme] = []
        if let many = try? dec.decode([DockTheme].self, from: data) {
            imported = many
        } else if let one = try? dec.decode(DockTheme.self, from: data) {
            imported = [one]
        }
        guard !imported.isEmpty else { NSSound.beep(); return }
        for var t in imported {
            t.id = UUID()
            themes.append(t)
        }
        if let last = themes.last { selectedID = last.id }
    }
}
