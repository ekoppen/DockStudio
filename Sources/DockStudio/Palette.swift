import SwiftUI

extension RGBA {
    /// "#rrggbb" of "#rrggbbaa"
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt64(h, radix: 16) ?? 0
        if h.count == 8 {
            self.init(Double((v >> 24) & 255) / 255, Double((v >> 16) & 255) / 255,
                      Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
        } else {
            self.init(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255,
                      Double(v & 255) / 255, 1)
        }
    }

    func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    var hex: String {
        String(format: "#%02x%02x%02x",
               Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// Kleurenpalet: de basis waar een thema van wordt afgeleid.
struct Palette: Codable, Equatable {
    var background: String
    var surface: String
    var foreground: String
    var accent: String
    var secondary: String

    enum CodingKeys: String, CodingKey {
        case background, surface, foreground, accent, secondary
    }

    init(background: String, surface: String, foreground: String, accent: String, secondary: String) {
        self.background = background
        self.surface = surface
        self.foreground = foreground
        self.accent = accent
        self.secondary = secondary
    }

    /// surface en secondary mogen in een bestand ontbreken.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode(String.self, forKey: .background)
        foreground = try c.decode(String.self, forKey: .foreground)
        accent = try c.decode(String.self, forKey: .accent)
        surface = try c.decodeIfPresent(String.self, forKey: .surface) ?? background
        secondary = try c.decodeIfPresent(String.self, forKey: .secondary) ?? accent
    }

    var bg: RGBA { RGBA(hex: background) }
    var sf: RGBA { RGBA(hex: surface) }
    var fg: RGBA { RGBA(hex: foreground) }
    var ac: RGBA { RGBA(hex: accent) }
    var sc: RGBA { RGBA(hex: secondary) }
}

struct NamedPalette: Identifiable {
    let name: String
    let palette: Palette
    var id: String { name }
}

enum Palettes {
    static let all: [NamedPalette] = [
        NamedPalette(name: "Catppuccin Mocha", palette: Palette(
            background: "#1e1e2e", surface: "#313244", foreground: "#cdd6f4",
            accent: "#cba6f7", secondary: "#94e2d5")),
        NamedPalette(name: "Catppuccin Latte", palette: Palette(
            background: "#eff1f5", surface: "#ccd0da", foreground: "#4c4f69",
            accent: "#8839ef", secondary: "#1e66f5")),
        NamedPalette(name: "Gruvbox Dark", palette: Palette(
            background: "#282828", surface: "#3c3836", foreground: "#ebdbb2",
            accent: "#fabd2f", secondary: "#fe8019")),
        NamedPalette(name: "Tokyo Night", palette: Palette(
            background: "#1a1b26", surface: "#24283b", foreground: "#c0caf5",
            accent: "#7aa2f7", secondary: "#bb9af7")),
        NamedPalette(name: "Nord", palette: Palette(
            background: "#2e3440", surface: "#3b4252", foreground: "#eceff4",
            accent: "#88c0d0", secondary: "#81a1c1")),
        NamedPalette(name: "Rosé Pine", palette: Palette(
            background: "#191724", surface: "#26233a", foreground: "#e0def4",
            accent: "#ebbcba", secondary: "#c4a7e7")),
        NamedPalette(name: "Dracula", palette: Palette(
            background: "#282a36", surface: "#44475a", foreground: "#f8f8f2",
            accent: "#bd93f9", secondary: "#ff79c6")),
        NamedPalette(name: "Everforest", palette: Palette(
            background: "#2d353b", surface: "#3d484d", foreground: "#d3c6aa",
            accent: "#a7c080", secondary: "#e69875")),
        NamedPalette(name: "Kanagawa", palette: Palette(
            background: "#1f1f28", surface: "#2a2a37", foreground: "#dcd7ba",
            accent: "#7e9cd8", secondary: "#e6c384")),
    ]
}

enum DockStyle: String, Codable, CaseIterable, Identifiable {
    case glass, solid, neon, iconsOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Glas"
        case .solid: return "Solide"
        case .neon: return "Neon"
        case .iconsOnly: return "Alleen iconen"
        }
    }
}

extension DockTheme {
    /// Bouwt een compleet dock-thema uit een palet en een stijl.
    static func derived(name: String, palette p: Palette, style: DockStyle, id: UUID = UUID()) -> DockTheme {
        var t = DockTheme(id: id, name: name)
        t.palette = p
        t.indicatorColor = p.ac
        t.glowColor = p.ac.withAlpha(0.9)

        switch style {
        case .glass:
            t.shape = .rounded
            t.cornerRadius = 24
            t.colorA = p.bg.withAlpha(0.35)
            t.useBlur = true
            t.borderColor = p.fg.withAlpha(0.25)
            t.borderWidth = 1
            t.glowEnabled = true
            t.glowIntensity = 0.7

        case .solid:
            t.shape = .rounded
            t.cornerRadius = 20
            t.colorA = p.sf.withAlpha(0.97)
            t.useGradient = true
            t.colorB = p.bg.withAlpha(0.97)
            t.useBlur = false
            t.borderColor = p.ac.withAlpha(0.6)
            t.borderWidth = 1.5
            t.dimOthers = true
            t.dimAmount = 0.4

        case .neon:
            t.shape = .capsule
            t.colorA = p.bg.withAlpha(0.92)
            t.useBlur = false
            t.borderColor = p.ac
            t.borderWidth = 2.5
            t.shadowRadius = 22
            t.indicatorColor = p.sc
            t.iconShape = .circle
            t.iconBackgroundEnabled = true
            t.iconBackgroundColor = p.sf
            t.iconInset = 6
            t.paddingLeft = 16
            t.paddingRight = 16
            t.glowEnabled = true
            t.glowColor = p.sc.withAlpha(0.95)

        case .iconsOnly:
            t.showBackground = false
            t.iconShadow = 8
            t.paddingTop = 0
            t.paddingBottom = 0
            t.glowEnabled = true
            t.dimOthers = true
            t.dimAmount = 0.6
            t.dimDesaturate = true
        }
        return t
    }
}
