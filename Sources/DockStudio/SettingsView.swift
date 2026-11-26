import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case dock, icons, behavior, themes, connections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dock: return "Dock"
        case .icons: return "Iconen"
        case .behavior: return "Gedrag"
        case .themes: return "Thema's"
        case .connections: return "Koppelingen"
        }
    }

    var symbol: String {
        switch self {
        case .dock: return "dock.rectangle"
        case .icons: return "square.grid.2x2"
        case .behavior: return "wand.and.stars"
        case .themes: return "paintpalette"
        case .connections: return "link"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ThemeStore
    @ObservedObject var ha = HAStore.shared
    @AppStorage("dockstudio.settingsFloating") private var floating = false
    @State private var tab: SettingsTab = .dock
    @State private var tokenInput = ""
    @State private var entityFilter = ""
    @FocusState private var searchFocused: Bool
    @State private var paletteIndex = 0
    @State private var paletteStyle: DockStyle = .glass
    @State private var wallpaperPalette: Palette?
    @State private var wallpaperMessage = ""

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 190, idealWidth: 210, maxWidth: 260)
            detail
                .frame(minWidth: 520)
        }
        .frame(minWidth: 780, minHeight: 720)
    }

    // MARK: Thema-lijst

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Thema's")
                    .font(.headline)
                Spacer()
                Text("\(store.themes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            List(selection: $store.selectedID) {
                ForEach(store.themes) { t in
                    ThemeRow(theme: t).tag(t.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 6) {
                Button { store.duplicateSelected() } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Dupliceer het geselecteerde thema")

                Button { store.deleteSelected() } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.themes.count <= 1)
                .help("Verwijder het geselecteerde thema")

                Spacer()

                Menu {
                    Button("Exporteer thema…") { store.exportSelected() }
                    Button("Importeer thema…") { store.importTheme() }
                    Divider()
                    Button("Herstel standaardthema's") { store.resetToPresets() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Importeren, exporteren en herstellen")
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    // MARK: Rechterkant: kopbalk, tabbladen, inhoud

    private var detail: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            tabBar
            Divider()
            Form { content }
                .formStyle(.grouped)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Naam", text: store.binding(\.name))
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Text("Je bewerkt het actieve thema. Wijzigingen zijn direct zichtbaar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                floating.toggle()
                SettingsWindow.apply()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: floating ? "pin.fill" : "pin")
                    if floating { Text("Vastgepind").font(.caption) }
                }
                .foregroundColor(floating ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Houd dit venster bovenop andere apps")
            VStack(alignment: .trailing, spacing: 2) {
                Toggle("Mijn dock tonen", isOn: $store.dockEnabled)
                    .toggleStyle(.switch)
                Text("Verbergt het echte Dock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { t in
                VStack(spacing: 3) {
                    Image(systemName: t.symbol)
                        .font(.system(size: 18))
                    Text(t.title)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundColor(tab == t ? .accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tab == t ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { tab = t }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .dock: dockTab
        case .icons: iconsTab
        case .behavior: behaviorTab
        case .themes: themesTab
        case .connections: connectionsTab
        }
    }

    // MARK: Tab: Dock

    @ViewBuilder
    private var dockTab: some View {
        Section {
            slider("Verticaal (afstand tot onderrand)", store.binding(\.bottomMargin), -150...300)
            slider("Horizontaal (0 = midden)", store.binding(\.offsetX), -1000...1000)
            note("Een negatieve waarde laat de dock deels onder de schermrand zakken. In de vakjes kun je ook een exacte waarde typen, buiten het bereik van de schuif.")
        } header: {
            sectionHeader("Positie", "arrow.up.and.down.and.arrow.left.and.right")
        }

        Section {
            Toggle("Dock-achtergrond tonen", isOn: store.binding(\.showBackground))
            note("Uit = alleen de iconen, zonder balk, rand en schaduw.")
        } header: {
            sectionHeader("Achtergrond", "rectangle.dashed")
        }

        Section {
            Picker("Vorm", selection: store.binding(\.shape)) {
                ForEach(DockShape.allCases) { Text($0.label).tag($0) }
            }
            slider("Hoekradius", store.binding(\.cornerRadius), 0...50)
        } header: {
            sectionHeader("Vorm", "square.on.circle")
        }
        .disabled(!store.theme.showBackground)

        Section {
            ColorPicker("Kleur", selection: store.colorBinding(\.colorA), supportsOpacity: true)
            Toggle("Kleurverloop", isOn: store.binding(\.useGradient))
            if store.theme.useGradient {
                ColorPicker("Tweede kleur", selection: store.colorBinding(\.colorB), supportsOpacity: true)
            }
            Toggle("Doorzichtige blur (glas)", isOn: store.binding(\.useBlur))
        } header: {
            sectionHeader("Kleur", "paintbrush")
        }
        .disabled(!store.theme.showBackground)

        Section {
            ColorPicker("Randkleur", selection: store.colorBinding(\.borderColor), supportsOpacity: true)
            slider("Randdikte", store.binding(\.borderWidth), 0...8, decimals: 1)
            slider("Schaduw", store.binding(\.shadowRadius), 0...40)
        } header: {
            sectionHeader("Rand en schaduw", "square.dashed")
        }
        .disabled(!store.theme.showBackground)
    }

    // MARK: Tab: Iconen

    @ViewBuilder
    private var iconsTab: some View {
        Section {
            slider("Icoongrootte", store.binding(\.iconSize), 24...96)
            slider("Ruimte tussen iconen", store.binding(\.spacing), 0...30)
        } header: {
            sectionHeader("Maten", "arrow.up.left.and.arrow.down.right")
        }

        Section {
            slider("Boven", store.binding(\.paddingTop), 0...40)
            slider("Onder", store.binding(\.paddingBottom), 0...40)
            slider("Links", store.binding(\.paddingLeft), 0...60)
            slider("Rechts", store.binding(\.paddingRight), 0...60)
        } header: {
            sectionHeader("Marges binnen de dock", "rectangle.inset.filled")
        }

        Section {
            Picker("Icoonvorm", selection: store.binding(\.iconShape)) {
                ForEach(IconShape.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Achtergrond achter iconen", isOn: store.binding(\.iconBackgroundEnabled))
            if store.theme.iconBackgroundEnabled {
                ColorPicker("Achtergrondkleur", selection: store.colorBinding(\.iconBackgroundColor), supportsOpacity: true)
            }
            slider("Binnenmarge icoon", store.binding(\.iconInset), 0...20)
            slider("Schaduw onder iconen", store.binding(\.iconShadow), 0...20)
        } header: {
            sectionHeader("Icoonvorm", "app")
        }

        Section {
            Toggle("Naam tonen bij hover", isOn: store.binding(\.showLabels))
            ColorPicker("Kleur actief-bolletje", selection: store.colorBinding(\.indicatorColor), supportsOpacity: true)
        } header: {
            sectionHeader("Labels en indicator", "tag")
        }
    }

    // MARK: Tab: Gedrag

    @ViewBuilder
    private var behaviorTab: some View {
        Section {
            slider("Vergroting (1 = uit)", store.binding(\.magnification), 1...2.5, decimals: 2)
            slider("Bereik van vergroting", store.binding(\.magnificationRange), 0.5...4, decimals: 1)
        } header: {
            sectionHeader("Vergroting", "plus.magnifyingglass")
        }

        Section {
            Toggle("Glow achter het icoon", isOn: store.binding(\.glowEnabled))
            if store.theme.glowEnabled {
                ColorPicker("Glow-kleur", selection: store.colorBinding(\.glowColor), supportsOpacity: true)
                slider("Glow-grootte", store.binding(\.glowSize), 0.6...2.5, decimals: 1)
                slider("Glow-sterkte", store.binding(\.glowIntensity), 0...1, decimals: 2)
            }
            Toggle("Andere iconen dimmen", isOn: store.binding(\.dimOthers))
            if store.theme.dimOthers {
                slider("Mate van dimmen", store.binding(\.dimAmount), 0...0.95, decimals: 2)
                Toggle("Ook kleur verminderen", isOn: store.binding(\.dimDesaturate))
            }
        } header: {
            sectionHeader("Hover-effecten", "sparkles")
        }

        Section {
            slider("Reactiesnelheid", store.binding(\.animResponse), 0.05...0.8, decimals: 2)
            slider("Veerkracht (laag = meer wiebel)", store.binding(\.animDamping), 0.3...1, decimals: 2)
            Toggle("Stuiteren bij openen van een app", isOn: store.binding(\.launchBounce))
            slider("Tijd voor verbergen/tonen (sec)", store.binding(\.fadeDuration), 0...1, decimals: 2)
        } header: {
            sectionHeader("Animatie", "waveform.path")
        }

        Section {
            Picker("Gedrag", selection: $store.windowMode) {
                ForEach(WindowMode.allCases) { Text($0.label).tag($0) }
            }
            switch store.windowMode {
            case .none:
                note("Vensters kunnen over de dock heen liggen.")
            case .reserve:
                note("Vensters worden kleiner of omhoog geschoven zodat ze niet onder de dock vallen.")
            case .smartHide:
                note("De dock verdwijnt als een venster erover ligt. Muis onderaan het scherm = dock terug.")
            }
            if !WindowAvoider.isTrusted {
                Text("Toegang nodig: zet DockStudio (of Terminal, als je met swift run start) aan onder Privacy en beveiliging > Toegankelijkheid.")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button("Vraag toegang") { WindowAvoider.requestTrust() }
                    Button("Open instellingen") { WindowAvoider.openSystemSettings() }
                    Button("Controleer opnieuw") { store.objectWillChange.send() }
                }
            }
        } header: {
            sectionHeader("Vensters van andere apps", "macwindow")
        }
    }

    // MARK: Tab: Thema's

    @ViewBuilder
    private var themesTab: some View {
        Section {
            Picker("Palet", selection: $paletteIndex) {
                ForEach(Array(Palettes.all.enumerated()), id: \.offset) { i, p in
                    Text(p.name).tag(i)
                }
            }
            swatches(Palettes.all[paletteIndex].palette)
            Picker("Stijl", selection: $paletteStyle) {
                ForEach(DockStyle.allCases) { Text($0.label).tag($0) }
            }
            Button("Maak dock-thema uit palet") {
                store.createFromPalette(Palettes.all[paletteIndex], style: paletteStyle)
            }
            note("Maakt een nieuw thema in de lijst. Daarna kun je het verder aanpassen.")
        } header: {
            sectionHeader("Palet", "swatchpalette")
        }

        Section {
            Button("Lees kleuren uit mijn wallpaper") {
                if let url = WallpaperPalette.currentWallpaperURL(),
                   let p = WallpaperPalette.extract(from: url) {
                    wallpaperPalette = p
                    wallpaperMessage = ""
                } else {
                    wallpaperPalette = nil
                    wallpaperMessage = "Kon het wallpaper niet lezen (bewegende wallpapers worden niet ondersteund)."
                }
            }
            if let wp = wallpaperPalette {
                swatches(wp)
                Button("Maak dock-thema uit wallpaper (stijl hierboven)") {
                    store.createFromPalette(NamedPalette(name: "Wallpaper", palette: wp), style: paletteStyle)
                }
            }
            if !wallpaperMessage.isEmpty { note(wallpaperMessage) }
            Toggle("Wallpaper automatisch volgen", isOn: $store.followWallpaper)
            if store.followWallpaper {
                Picker("Stijl bij volgen", selection: $store.followStyle) {
                    ForEach(DockStyle.allCases) { Text($0.label).tag($0) }
                }
                note("Bij elke wallpaper-wissel wordt het thema \"Wallpaper (auto)\" opnieuw gemaakt en gekozen. Eigen aanpassingen daaraan worden overschreven; dupliceer het thema om ze te bewaren.")
            }
        } header: {
            sectionHeader("Palet uit wallpaper", "photo")
        }

        Section {
            note("Map: ~/.config/dockstudio/themes. Gewone json-bestanden, handig voor je dotfiles.")
            HStack {
                Button("Open map") { store.openThemesFolder() }
                Button("Herlaad uit map") { store.loadFromFolder() }
                Button("Sla alle thema's op") { store.saveAllToFolder() }
            }
            if !store.status.isEmpty { note(store.status) }
        } header: {
            sectionHeader("Thema's als bestanden", "doc.text")
        }
    }

    // MARK: Tab: Koppelingen

    @ViewBuilder
    private var connectionsTab: some View {
        Section {
            Toggle("Scripts uitvoeren bij een themawissel", isOn: $store.hooksEnabled)
            note("Scripts in ~/.config/dockstudio/hooks krijgen de kleuren als variabelen (DOCKSTUDIO_BG, _FG, _ACCENT, …). Alleen uitvoerbare bestanden (chmod +x) draaien.")
            HStack {
                Button("Open hooks-map") {
                    HookRunner.ensureFolder()
                    NSWorkspace.shared.open(HookRunner.folder)
                }
                Button("Voer hooks nu uit") {
                    HookRunner.run(theme: store.theme, force: true)
                }
            }
        } header: {
            sectionHeader("Hooks bij themawissel", "terminal")
        }

        Section {
            Toggle("Home Assistant gebruiken", isOn: $ha.config.enabled)
            TextField("URL", text: $ha.config.baseURL)
            SecureField("Long-lived access token", text: $tokenInput)
            HStack {
                Button("Bewaar token") {
                    ha.saveToken(tokenInput)
                    tokenInput = ""
                }
                .disabled(tokenInput.isEmpty)
                Button("Test verbinding") { ha.testConnection() }
            }
            note(ha.tokenSaved
                 ? "Het token staat in de Sleutelhanger."
                 : "Nog geen token. Maak er een in Home Assistant: profiel > Beveiliging > Langdurige toegangstokens.")
            if !ha.status.isEmpty { note(ha.status) }
        } header: {
            sectionHeader("Home Assistant", "house")
        }

        Section {
            if ha.config.dockEntities.isEmpty && ha.config.themeLights.isEmpty && ha.config.themeScene.isEmpty {
                note("Nog niets gekozen. Zoek hieronder een lamp, schakelaar of scène.")
            }
            ForEach(ha.config.dockEntities) { e in
                selectedRow(symbol: HAIcon.symbol(for: e.domain), title: e.name, subtitle: e.id, badge: "Dock") {
                    ha.config.dockEntities.removeAll { $0.id == e.id }
                }
            }
            ForEach(ha.config.themeLights, id: \.self) { id in
                selectedRow(symbol: "lightbulb", title: ha.available.first { $0.id == id }?.name ?? id,
                            subtitle: id, badge: "Thema") {
                    ha.config.themeLights.removeAll { $0 == id }
                }
            }
            if !ha.config.themeScene.isEmpty {
                selectedRow(symbol: "sparkles",
                            title: ha.available.first { $0.id == ha.config.themeScene }?.name ?? ha.config.themeScene,
                            subtitle: ha.config.themeScene, badge: "Thema-scène") {
                    ha.config.themeScene = ""
                }
            }
        } header: {
            sectionHeader("Gekozen entiteiten", "checklist")
        }

        Section {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Zoek entiteit, bijv. woonkamer of light.", text: $entityFilter)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onAppear {
                        if ha.available.isEmpty && ha.tokenSaved && ha.config.enabled { ha.fetchEntities() }
                    }
                if !entityFilter.isEmpty {
                    Button { entityFilter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                Button { ha.fetchEntities() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Entiteiten opnieuw ophalen")
            }

            if ha.available.isEmpty {
                note(ha.tokenSaved
                     ? "Nog geen entiteiten geladen. Controleer de verbinding hierboven en klik op vernieuwen."
                     : "Sla eerst een token op om te kunnen zoeken.")
            } else if entityFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                note("Typ om te zoeken in \(ha.available.count) entiteiten.")
            } else {
                let found = searchResults
                if found.items.isEmpty {
                    note("Geen resultaten.")
                }
                ForEach(found.items) { e in
                    HStack(spacing: 8) {
                        Image(systemName: HAIcon.symbol(for: e.domain))
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(e.name)
                            Text(e.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(isOn: ha.dockBinding(e)) { Text("Dock") }
                            .toggleStyle(.button)
                        if e.domain == "light" {
                            Toggle(isOn: ha.lightBinding(e.id)) { Text("Thema") }
                                .toggleStyle(.button)
                        }
                        if e.domain == "scene" {
                            Toggle(isOn: ha.sceneBinding(e.id)) { Text("Thema-scène") }
                                .toggleStyle(.button)
                        }
                    }
                    .controlSize(.small)
                }
                if found.more > 0 {
                    note("Nog \(found.more) resultaten. Maak je zoekopdracht specifieker.")
                }
            }
        } header: {
            sectionHeader("Zoek entiteiten", "magnifyingglass")
        }

        Section {
            Toggle("Lampen en scène aanpassen bij een themawissel", isOn: $ha.config.syncTheme)
            Picker("Kleur voor de lampen", selection: $ha.config.themeColor) {
                ForEach(HAThemeColor.allCases) { Text($0.label).tag($0) }
            }
            slider("Helderheid (%)", $ha.config.themeBrightness, 5...100)
            note("Gekozen lampen: \(ha.config.themeLights.count)"
                 + (ha.config.themeScene.isEmpty ? "" : ", scène: \(ha.config.themeScene)"))
            Button("Test: stuur dit thema naar de lampen") {
                ha.applyTheme(store.theme, force: true)
            }
        } header: {
            sectionHeader("Lampen volgen het thema", "lightbulb")
        }
    }

    // MARK: Hulpjes

    /// Alle woorden uit de zoekopdracht moeten in de naam of het id voorkomen.
    private var searchResults: (items: [HAEntity], more: Int) {
        let words = entityFilter.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ([], 0) }
        let matches = ha.available.filter { e in
            let hay = (e.id + " " + e.name).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
        return (Array(matches.prefix(8)), max(matches.count - 8, 0))
    }

    private func selectedRow(symbol: String, title: String, subtitle: String, badge: String,
                             remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(badge)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            Button(action: remove) { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Verwijderen")
        }
    }

    private func sectionHeader(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func swatches(_ p: Palette) -> some View {
        let hexes = [p.background, p.surface, p.foreground, p.accent, p.secondary]
        return HStack(spacing: 6) {
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 5)
                    .fill(RGBA(hex: h).color)
                    .frame(width: 34, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2)))
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    /// Schuif met een invulveld: de waarde mag ook buiten het bereik van de schuif getypt worden.
    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        decimals: Int = 0) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            TextField("", value: value,
                      format: .number.precision(.fractionLength(0...decimals)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 64)
        }
    }
}

/// Rij in de themalijst: klein voorbeeld van het thema met naam en stijl.
struct ThemeRow: View {
    let theme: DockTheme

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 46, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name).lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if !theme.showBackground { return "Alleen iconen" }
        let fill = theme.useBlur ? "glas" : (theme.useGradient ? "verloop" : "solide")
        return "\(theme.shape.label.lowercased()) · \(fill)"
    }

    private var preview: some View {
        let shape = theme.makeShape()
        return ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.28))
            if theme.showBackground {
                shape
                    .fill(LinearGradient(
                        colors: [theme.colorA.color, (theme.useGradient ? theme.colorB : theme.colorA).color],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(shape.stroke(theme.borderColor.color, lineWidth: 1))
                    .padding(2)
            }
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == 1 && theme.glowEnabled ? theme.glowColor.color : theme.indicatorColor.color)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}
