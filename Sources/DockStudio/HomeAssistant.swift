import SwiftUI
import AppKit
import Security

// MARK: Sleutelhanger

enum Keychain {
    private static let service = "dockstudio.homeassistant"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func set(_ value: String, account: String = "token") {
        SecItemDelete(base(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = base(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(account: String = "token") -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: Modellen

enum HAThemeColor: String, Codable, CaseIterable, Identifiable {
    case accent, secondary, foreground, background
    var id: String { rawValue }
    var label: String {
        switch self {
        case .accent: return "Accent"
        case .secondary: return "Tweede accent"
        case .foreground: return "Voorgrond"
        case .background: return "Achtergrond"
        }
    }
}

struct HADockEntity: Codable, Equatable, Identifiable {
    var id: String          // entity_id, bijv. light.woonkamer
    var name: String
    var symbol: String? = nil   // eigen SF Symbol
    var color: RGBA? = nil      // eigen "aan"-kleur
    var domain: String { String(id.split(separator: ".").first ?? "") }
}

struct HAEntity: Identifiable, Equatable {
    var id: String
    var name: String
    var domain: String { String(id.split(separator: ".").first ?? "") }
}

enum HATile: String, Codable, CaseIterable {
    case rounded, circle, none
}

/// Uiterlijk van alle Home Assistant-iconen in de dock.
struct HAIconStyle: Codable, Equatable {
    var tile: HATile = .rounded
    var onColor = RGBA(1.0, 0.78, 0.24)
    var offColor = RGBA(0.30, 0.33, 0.38)
    var gradient = true
    var glyphSize = 0.55
    var useThemeAccent = false

    enum CodingKeys: String, CodingKey { case tile, onColor, offColor, gradient, glyphSize, useThemeAccent }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tile = (try? c.decode(HATile.self, forKey: .tile)) ?? .rounded
        onColor = (try? c.decode(RGBA.self, forKey: .onColor)) ?? RGBA(1.0, 0.78, 0.24)
        offColor = (try? c.decode(RGBA.self, forKey: .offColor)) ?? RGBA(0.30, 0.33, 0.38)
        gradient = (try? c.decode(Bool.self, forKey: .gradient)) ?? true
        glyphSize = (try? c.decode(Double.self, forKey: .glyphSize)) ?? 0.55
        useThemeAccent = (try? c.decode(Bool.self, forKey: .useThemeAccent)) ?? false
    }
}

struct HAConfig: Codable, Equatable {
    var enabled = false
    var baseURL = "http://homeassistant.local:8123"
    var dockEntities: [HADockEntity] = []
    var groupEntities: [HADockEntity]? = nil   // alleen in een groep gebruikt
    var iconStyle: HAIconStyle? = nil
    var syncTheme = false
    var themeLights: [String] = []
    var themeScene = ""
    var themeColor: HAThemeColor = .accent
    var themeBrightness = 70.0
}

enum HAError: LocalizedError {
    case badURL, noToken, http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Ongeldige URL"
        case .noToken: return "Geen token ingesteld"
        case .http(let c):
            return c == 401 ? "Token geweigerd (401)" : "Home Assistant antwoordde met code \(c)"
        }
    }
}

enum HAIcon {
    static func symbol(for domain: String) -> String {
        switch domain {
        case "light": return "lightbulb.fill"
        case "switch": return "power"
        case "scene": return "sparkles"
        case "script": return "play.circle.fill"
        case "fan": return "fan.fill"
        case "lock": return "lock.fill"
        case "cover": return "blinds.horizontal.closed"
        case "input_boolean": return "switch.2"
        case "automation": return "gearshape.2.fill"
        case "button": return "circle.circle.fill"
        default: return "house.fill"
        }
    }

    private static func ns(_ c: RGBA) -> NSColor {
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    /// Tekent het icoon van een HA-item: gekleurde tegel met symbool.
    static func make(domain: String, on: Bool, symbol: String? = nil, color: RGBA? = nil) -> NSImage {
        let st = HAStore.shared.config.iconStyle ?? HAIconStyle()
        let name = (symbol?.isEmpty == false ? symbol! : Self.symbol(for: domain))
        var onColor = color ?? st.onColor
        if color == nil && st.useThemeAccent {
            onColor = ThemeStore.shared.theme.effectivePalette.ac
        }
        let tile = ns(on ? onColor : st.offColor)
        let lum = 0.299 * tile.redComponent + 0.587 * tile.greenComponent + 0.114 * tile.blueComponent
        let glyph: NSColor = st.tile == .none ? tile : (lum > 0.62 ? NSColor(white: 0.12, alpha: 0.92) : .white)

        let s: CGFloat = 256
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "house.fill", accessibilityDescription: nil)
            ?? NSImage()
        let cfg = NSImage.SymbolConfiguration(pointSize: s * CGFloat(st.glyphSize), weight: .semibold)
        let sym = base.withSymbolConfiguration(cfg) ?? base

        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            let area = rect.insetBy(dx: 10, dy: 10)
            if st.tile != .none {
                let path = st.tile == .circle
                    ? NSBezierPath(ovalIn: area)
                    : NSBezierPath(roundedRect: area, xRadius: 58, yRadius: 58)
                if st.gradient,
                   let g = NSGradient(starting: tile.blended(withFraction: 0.18, of: .white) ?? tile,
                                      ending: tile.blended(withFraction: 0.22, of: .black) ?? tile) {
                    g.draw(in: path, angle: -90)
                } else {
                    tile.setFill()
                    path.fill()
                }
            }
            let gs = sym.size
            let tinted = NSImage(size: gs, flipped: false) { r in
                sym.draw(in: r)
                glyph.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: (s - gs.width) / 2, y: (s - gs.height) / 2,
                                   width: gs.width, height: gs.height))
            return true
        }
        return img
    }
}

// MARK: Store + client

final class HAStore: ObservableObject {
    static let shared = HAStore()

    private let key = "dockstudio.ha"

    @Published var config: HAConfig {
        didSet {
            save()
            if oldValue.enabled != config.enabled || oldValue.dockEntities != config.dockEntities
                || oldValue.groupEntities != config.groupEntities
                || oldValue.iconStyle != config.iconStyle {
                DockModel.shared.reload()
            }
        }
    }
    @Published var available: [HAEntity] = []
    @Published var states: [String: String] = [:]
    @Published var status = ""
    @Published var tokenSaved = false

    private var cachedToken: String?
    private var polling = false

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode(HAConfig.self, from: data) {
            config = c
        } else {
            config = HAConfig()
        }
        cachedToken = Keychain.get()
        tokenSaved = cachedToken != nil
    }

    func start() {
        Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func saveToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(t)
        cachedToken = t.isEmpty ? nil : t
        tokenSaved = cachedToken != nil
        status = tokenSaved ? "Token opgeslagen." : "Token verwijderd."
    }

    func isOn(_ id: String) -> Bool {
        ["on", "open", "unlocked", "playing"].contains(states[id] ?? "")
    }

    // MARK: Netwerk

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let baseURL = URL(string: base) else { throw HAError.badURL }
        guard let token = cachedToken, !token.isEmpty else { throw HAError.noToken }

        var req = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 8)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw HAError.http(h.statusCode)
        }
        return data
    }

    private func callService(_ domain: String, _ service: String, _ payload: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("api/services/\(domain)/\(service)", method: "POST", body: body)
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.status = text }
    }

    func testConnection() {
        status = "Verbinden…"
        Task {
            do {
                _ = try await request("api/")
                setStatus("Verbonden met Home Assistant.")
            } catch {
                setStatus("Mislukt: \(error.localizedDescription)")
            }
        }
    }

    private static let usefulDomains: Set<String> = [
        "light", "switch", "scene", "script", "fan", "lock", "cover",
        "input_boolean", "automation", "button",
    ]

    func fetchEntities() {
        status = "Entiteiten ophalen…"
        Task {
            do {
                let data = try await request("api/states")
                guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    setStatus("Onverwacht antwoord van Home Assistant.")
                    return
                }
                var list: [HAEntity] = []
                for e in arr {
                    guard let id = e["entity_id"] as? String else { continue }
                    let domain = String(id.split(separator: ".").first ?? "")
                    guard Self.usefulDomains.contains(domain) else { continue }
                    let attrs = e["attributes"] as? [String: Any]
                    let name = (attrs?["friendly_name"] as? String) ?? id
                    list.append(HAEntity(id: id, name: name))
                }
                list.sort { ($0.domain, $0.name) < ($1.domain, $1.name) }
                let found = list
                await MainActor.run {
                    self.available = found
                    self.status = "\(found.count) entiteiten gevonden."
                }
            } catch {
                setStatus("Mislukt: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Status ophalen voor dock-items

    private func fetchState(_ id: String) async -> String? {
        guard let data = try? await request("api/states/\(id)"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["state"] as? String
    }

    private func poll() {
        let ids = (config.dockEntities + (config.groupEntities ?? [])).map { $0.id }
        guard config.enabled, tokenSaved, !ids.isEmpty, !polling else { return }
        polling = true
        Task {
            var result: [String: String] = [:]
            for id in ids {
                if let st = await fetchState(id) { result[id] = st }
            }
            let fetched = result
            await MainActor.run {
                self.polling = false
                var merged = self.states
                for (k, v) in fetched { merged[k] = v }
                if merged != self.states {
                    self.states = merged
                    DockModel.shared.reload()
                }
            }
        }
    }

    /// Zet een entiteit klaar voor gebruik in een groep (zonder dat hij los in de dock komt).
    func addGroupEntity(_ e: HAEntity) {
        guard !config.dockEntities.contains(where: { $0.id == e.id }) else { return }
        var list = config.groupEntities ?? []
        if !list.contains(where: { $0.id == e.id }) {
            list.append(HADockEntity(id: e.id, name: e.name))
            config.groupEntities = list
        }
        poll()
    }

    // MARK: Acties

    /// Klik op een HA-item in de dock.
    func activate(_ id: String) {
        let domain = String(id.split(separator: ".").first ?? "")
        let service: (String, String)
        switch domain {
        case "scene": service = ("scene", "turn_on")
        case "script": service = ("script", "turn_on")
        case "automation": service = ("automation", "trigger")
        case "button": service = ("button", "press")
        case "lock": service = ("lock", states[id] == "locked" ? "unlock" : "lock")
        default: service = ("homeassistant", "toggle")
        }

        // Meteen laten zien; de echte status volgt uit de volgende poll.
        if ["on", "off"].contains(states[id] ?? "") {
            states[id] = states[id] == "on" ? "off" : "on"
            DockModel.shared.reload()
        }

        Task {
            do {
                try await callService(service.0, service.1, ["entity_id": id])
            } catch {
                setStatus("Schakelen mislukt: \(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let st = await fetchState(id) {
                await MainActor.run {
                    self.states[id] = st
                    DockModel.shared.reload()
                }
            }
        }
    }

    /// Zet de gekozen lampen op de themakleur en start de gekozen scène.
    func applyTheme(_ theme: DockTheme, force: Bool = false) {
        guard force || (config.enabled && config.syncTheme), tokenSaved,
              !(config.themeLights.isEmpty && config.themeScene.isEmpty) else { return }

        let p = theme.effectivePalette
        let c: RGBA
        switch config.themeColor {
        case .accent: c = p.ac
        case .secondary: c = p.sc
        case .foreground: c = p.fg
        case .background: c = p.bg
        }
        let rgb = [Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded())]
        let lights = config.themeLights
        let scene = config.themeScene
        let brightness = Int(config.themeBrightness)

        Task {
            do {
                if !lights.isEmpty {
                    try await callService("light", "turn_on", [
                        "entity_id": lights,
                        "rgb_color": rgb,
                        "brightness_pct": brightness,
                        "transition": 2,
                    ])
                }
                if !scene.isEmpty {
                    try await callService("scene", "turn_on", ["entity_id": scene])
                }
                setStatus("Thema \"\(theme.name)\" naar Home Assistant gestuurd.")
            } catch {
                setStatus("Thema sturen mislukt: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Bindings voor de instellingen

    func dockBinding(_ e: HAEntity) -> Binding<Bool> {
        Binding(
            get: { self.config.dockEntities.contains { $0.id == e.id } },
            set: { on in
                if on {
                    if !self.config.dockEntities.contains(where: { $0.id == e.id }) {
                        self.config.dockEntities.append(HADockEntity(id: e.id, name: e.name))
                    }
                } else {
                    self.config.dockEntities.removeAll { $0.id == e.id }
                }
            })
    }

    func lightBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.config.themeLights.contains(id) },
            set: { on in
                if on {
                    if !self.config.themeLights.contains(id) { self.config.themeLights.append(id) }
                } else {
                    self.config.themeLights.removeAll { $0 == id }
                }
            })
    }

    func sceneBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.config.themeScene == id },
            set: { on in self.config.themeScene = on ? id : "" })
    }
}
