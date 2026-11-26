import SwiftUI
import AppKit

/// Thema-bestand in ~/.config/dockstudio/themes
/// Of een volledig dock-thema ("dock"), of een palet met een stijl.
struct ThemeFile: Codable {
    var name: String?
    var style: DockStyle?
    var palette: Palette?
    var dock: DockTheme?
}

extension ThemeStore {
    static var themesFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dockstudio/themes", isDirectory: true)
    }

    func createFromPalette(_ np: NamedPalette, style: DockStyle) {
        let t = DockTheme.derived(name: "\(np.name) · \(style.label)",
                                  palette: np.palette, style: style)
        themes.append(t)
        selectedID = t.id
    }

    /// Maakt de map aan (met een voorbeeldbestand) en opent die in Finder.
    func openThemesFolder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.themesFolder, withIntermediateDirectories: true)
        let example = Self.themesFolder.appendingPathComponent("voorbeeld-gruvbox.json")
        if !fm.fileExists(atPath: example.path) {
            let text = """
            {
              "name": "Voorbeeld Gruvbox",
              "style": "neon",
              "palette": {
                "background": "#282828",
                "surface": "#3c3836",
                "foreground": "#ebdbb2",
                "accent": "#fabd2f",
                "secondary": "#fe8019"
              }
            }
            """
            try? text.write(to: example, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(Self.themesFolder)
    }

    func saveAllToFolder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.themesFolder, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        var count = 0
        for t in themes {
            let safe = t.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let url = Self.themesFolder.appendingPathComponent("\(safe).json")
            let file = ThemeFile(name: t.name, style: nil, palette: nil, dock: t)
            if let data = try? enc.encode(file), (try? data.write(to: url)) != nil { count += 1 }
        }
        status = "\(count) thema's opgeslagen in ~/.config/dockstudio/themes"
    }

    func loadFromFolder() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: Self.themesFolder,
                                                     includingPropertiesForKeys: nil) else {
            status = "De map bestaat nog niet. Klik op 'Open map'."
            return
        }
        let dec = JSONDecoder()
        var loaded = 0
        var skipped = 0

        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url) else { skipped += 1; continue }
            let fallbackName = url.deletingPathExtension().lastPathComponent
            var theme: DockTheme?

            if let f = try? dec.decode(ThemeFile.self, from: data) {
                let name = f.name ?? f.dock?.name ?? fallbackName
                if var d = f.dock {
                    d.name = name
                    theme = d
                } else if let p = f.palette {
                    theme = DockTheme.derived(name: name, palette: p, style: f.style ?? .glass)
                } else if String(data: data, encoding: .utf8)?.contains("\"colorA\"") == true,
                          var d = try? dec.decode(DockTheme.self, from: data) {
                    // Een los geëxporteerd dock-thema
                    d.name = name
                    theme = d
                }
            }

            guard var t = theme else { skipped += 1; continue }
            if let i = themes.firstIndex(where: { $0.name.lowercased() == t.name.lowercased() }) {
                t.id = themes[i].id
                themes[i] = t
            } else {
                t.id = UUID()
                themes.append(t)
            }
            loaded += 1
        }
        status = "\(loaded) geladen" + (skipped > 0 ? ", \(skipped) overgeslagen" : "")
    }

    /// Maakt of vernieuwt het thema "Wallpaper (auto)" en selecteert het.
    func applyWallpaperTheme(_ p: Palette, wallpaper: URL?) {
        let name = "Wallpaper (auto)"
        var t = DockTheme.derived(name: name, palette: p, style: followStyle)
        if let i = themes.firstIndex(where: { $0.name == name }) {
            t.id = themes[i].id
            themes[i] = t
        } else {
            themes.append(t)
        }
        let changed = selectedID != t.id
        selectedID = t.id                       // start de hooks als de selectie wisselt
        if !changed { HookRunner.run(theme: t, wallpaper: wallpaper) }
        status = "Wallpaper-thema bijgewerkt"
    }
}
