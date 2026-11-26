import Foundation

/// Voert scripts uit uit ~/.config/dockstudio/hooks bij een themawissel.
/// Alleen uitvoerbare bestanden (chmod +x) worden gestart, op alfabetische volgorde.
enum HookRunner {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dockstudio/hooks", isDirectory: true)
    }

    /// Maakt de map aan met een (niet-uitvoerbaar) voorbeeldscript.
    static func ensureFolder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let example = folder.appendingPathComponent("00-voorbeeld.sh")
        if !fm.fileExists(atPath: example.path) {
            let text = """
            #!/bin/bash
            # Voorbeeld-hook. Maak uitvoerbaar met: chmod +x 00-voorbeeld.sh
            # Wordt gestart bij elke themawissel, met deze variabelen:
            #   DOCKSTUDIO_THEME      naam van het thema
            #   DOCKSTUDIO_BG         achtergrondkleur   (#rrggbb)
            #   DOCKSTUDIO_SURFACE    vlakkleur
            #   DOCKSTUDIO_FG         voorgrondkleur
            #   DOCKSTUDIO_ACCENT     accentkleur
            #   DOCKSTUDIO_SECONDARY  tweede accentkleur
            #   DOCKSTUDIO_WALLPAPER  pad naar het wallpaper (alleen bij wallpaper volgen)

            echo "$(date): $DOCKSTUDIO_THEME accent=$DOCKSTUDIO_ACCENT" >> /tmp/dockstudio-hook.log
            """
            try? text.write(to: example, atomically: true, encoding: .utf8)
        }
    }

    static func run(theme: DockTheme, wallpaper: URL? = nil, force: Bool = false) {
        HAStore.shared.applyTheme(theme)
        guard force || ThemeStore.shared.hooksEnabled else { return }

        let p = theme.effectivePalette
        var env = ProcessInfo.processInfo.environment
        env["DOCKSTUDIO_THEME"] = theme.name
        env["DOCKSTUDIO_BG"] = p.background
        env["DOCKSTUDIO_SURFACE"] = p.surface
        env["DOCKSTUDIO_FG"] = p.foreground
        env["DOCKSTUDIO_ACCENT"] = p.accent
        env["DOCKSTUDIO_SECONDARY"] = p.secondary
        env["DOCKSTUDIO_WALLPAPER"] = wallpaper?.path ?? ""

        let dir = folder
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { return }
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where fm.isExecutableFile(atPath: f.path) {
                let proc = Process()
                proc.executableURL = f
                proc.environment = env
                proc.currentDirectoryURL = dir
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                do { try proc.run() } catch { continue }
                DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                    if proc.isRunning { proc.terminate() }
                }
                proc.waitUntilExit()
            }
        }
    }
}

extension DockTheme {
    /// Het palet van dit thema; zonder opgeslagen palet afgeleid uit de themakleuren.
    var effectivePalette: Palette {
        if let p = palette { return p }
        return Palette(background: colorA.hex,
                       surface: (useGradient ? colorB : colorA).hex,
                       foreground: "#ffffff",
                       accent: indicatorColor.hex,
                       secondary: glowColor.hex)
    }
}
