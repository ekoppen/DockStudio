import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: Gegevens

enum GroupLayout: String, Codable, CaseIterable { case grid, list }
enum GroupBackground: String, Codable, CaseIterable { case theme, glass, none }

/// Opmaak van de inhoud van een groep.
struct GroupStyle: Codable, Equatable {
    var layout: GroupLayout = .grid
    var columns: Int = 0            // 0 = automatisch
    var iconSize: Double = 56
    var showNames: Bool = true
    var background: GroupBackground = .theme

    enum CodingKeys: String, CodingKey { case layout, columns, iconSize, showNames, background }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decode(GroupLayout.self, forKey: .layout)) ?? .grid
        columns = (try? c.decode(Int.self, forKey: .columns)) ?? 0
        iconSize = (try? c.decode(Double.self, forKey: .iconSize)) ?? 56
        showNames = (try? c.decode(Bool.self, forKey: .showNames)) ?? true
        background = (try? c.decode(GroupBackground.self, forKey: .background)) ?? .theme
    }
}

struct DockGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var members: [String]   // app-paden of "ha:<entity_id>"
    var style = GroupStyle()

    enum CodingKeys: String, CodingKey { case id, name, members, style }

    init(id: UUID = UUID(), name: String, members: [String], style: GroupStyle = GroupStyle()) {
        self.id = id
        self.name = name
        self.members = members
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Groep"
        members = (try? c.decode([String].self, forKey: .members)) ?? []
        style = (try? c.decode(GroupStyle.self, forKey: .style)) ?? GroupStyle()
    }
}

/// Eigen indeling van Dokko: groepen en welke apps getoond worden (los van het echte Dock).
final class DockPrefs: ObservableObject {
    static let shared = DockPrefs()

    @Published var groups: [DockGroup] { didSet { save() } }
    @Published var hidden: [String] { didSet { save() } }   // vastgepinde apps die Dokko verbergt
    @Published var extra: [String] { didSet { save() } }    // extra vastgezette apps

    private let key = "dockstudio.dockprefs"
    private struct Blob: Codable {
        var groups: [DockGroup]
        var hidden: [String]
        var extra: [String]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let b = try? JSONDecoder().decode(Blob.self, from: data) {
            groups = b.groups
            hidden = b.hidden
            extra = b.extra
        } else {
            groups = []
            hidden = []
            extra = []
        }
    }

    private func save() {
        let b = Blob(groups: groups, hidden: hidden, extra: extra)
        if let data = try? JSONEncoder().encode(b) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    @discardableResult
    func newGroup(with path: String?) -> UUID {
        var g = DockGroup(name: "Groep \(groups.count + 1)", members: [])
        if let path {
            removeFromAllGroups(path)
            g.members = [path]
        }
        groups.append(g)
        return g.id
    }

    func add(_ path: String, to id: UUID) {
        removeFromAllGroups(path)
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].members.append(path)
    }

    func remove(_ path: String, from id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].members.removeAll { $0 == path }
    }

    /// Zet `path` voor `target` in de groep (ook vanuit een andere groep of de dock).
    func place(_ path: String, before target: String, in id: UUID) {
        guard path != target else { return }
        removeFromAllGroups(path)
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let at = groups[i].members.firstIndex(of: target) ?? groups[i].members.count
        groups[i].members.insert(path, at: at)
    }

    func move(_ path: String, in id: UUID, by offset: Int) {
        guard let i = groups.firstIndex(where: { $0.id == id }),
              let from = groups[i].members.firstIndex(of: path) else { return }
        let to = from + offset
        guard to >= 0, to < groups[i].members.count else { return }
        groups[i].members.swapAt(from, to)
    }

    func delete(_ id: UUID) {
        groups.removeAll { $0.id == id }
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].name = name
    }

    private func removeFromAllGroups(_ path: String) {
        for i in groups.indices { groups[i].members.removeAll { $0 == path } }
    }

    // Vastzetten / verwijderen uit de dock (alleen binnen Dokko)

    func isInDock(_ path: String) -> Bool {
        if extra.contains(path) { return true }
        let pinned = Set(DockModel.pinnedAppURLs().map { $0.standardizedFileURL.path })
        return pinned.contains(path) && !hidden.contains(path)
    }

    func pin(_ path: String) {
        hidden.removeAll { $0 == path }
        let pinned = Set(DockModel.pinnedAppURLs().map { $0.standardizedFileURL.path })
        if !pinned.contains(path), !extra.contains(path) { extra.append(path) }
    }

    func unpin(_ path: String) {
        extra.removeAll { $0 == path }
        removeFromAllGroups(path)
        let pinned = Set(DockModel.pinnedAppURLs().map { $0.standardizedFileURL.path })
        if pinned.contains(path), !hidden.contains(path) { hidden.append(path) }
    }

    func promptRename(_ id: UUID) {
        guard let g = groups.first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hernoem groep"
        alert.addButton(withTitle: "Bewaar")
        alert.addButton(withTitle: "Annuleer")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = g.name
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { rename(id, to: name) }
        }
    }
}

// MARK: Groepsicoon

enum GroupIcon {
    /// Tekent een icoon met de eerste vier apps van de groep in een raster.
    static func make(members: [NSImage]) -> NSImage {
        let s: CGFloat = 256
        return NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 56, yRadius: 56)
            NSColor(white: 0, alpha: 0.35).setFill()
            bg.fill()
            NSColor(white: 1, alpha: 0.4).setStroke()
            bg.lineWidth = 3
            bg.stroke()
            let inset: CGFloat = 36, gap: CGFloat = 12
            let cell = (s - inset * 2 - gap) / 2
            for (i, img) in members.prefix(4).enumerated() {
                let col = CGFloat(i % 2), row = CGFloat(i / 2)
                let r = NSRect(x: inset + col * (cell + gap),
                               y: s - inset - cell - row * (cell + gap),
                               width: cell, height: cell)
                img.draw(in: r)
            }
            return true
        }
    }
}

// MARK: Rechtermuisknop-menu

struct ItemContextMenu: View {
    let item: DockItem
    var inGroup: UUID? = nil
    @ObservedObject var prefs = DockPrefs.shared

    private var runningApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL.path == item.id
        }
    }

    @ViewBuilder
    private var groupMenu: some View {
        Menu("Voeg toe aan groep") {
            ForEach(prefs.groups) { g in
                Button(g.name) { prefs.add(item.id, to: g.id) }
            }
            if !prefs.groups.isEmpty { Divider() }
            Button("Nieuwe groep") { prefs.newGroup(with: item.id) }
        }
        if let gid = inGroup {
            Button("Haal uit groep") { prefs.remove(item.id, from: gid) }
        }
    }

    var body: some View {
        if let gid = item.groupID {
            Button("Hernoem groep…") { prefs.promptRename(gid) }
            Button("Verwijder groep") { prefs.delete(gid) }
        } else if item.haEntity != nil {
            Button("Schakel om") { DockModel.shared.open(item) }
            Divider()
            groupMenu
        } else if item.isTrash {
            Button("Open") { DockModel.shared.open(item) }
        } else {
            Button(item.isRunning ? "Toon" : "Open") { DockModel.shared.open(item) }
            Button("Toon in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if item.isRunning, let app = runningApp {
                Divider()
                Button("Verberg") { app.hide() }
                Button("Stop") { app.terminate() }
                Button("Forceer stop") { app.forceTerminate() }
            }
            Divider()
            groupMenu
            if prefs.isInDock(item.id) {
                Button("Verwijder uit dock") { prefs.unpin(item.id) }
            } else {
                Button("Houd in dock") { prefs.pin(item.id) }
            }
        }
    }
}

// MARK: Groep-venster

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class GroupPopup {
    static let shared = GroupPopup()

    private var panel: NSPanel?
    private var currentID: UUID?
    private var monitors: [Any] = []
    private var lastClosed: (id: UUID, at: Date)?

    func toggle(_ item: DockItem, anchorX: CGFloat, anchorY: CGFloat) {
        guard let gid = item.groupID else { return }
        if currentID == gid, panel != nil { close(); return }
        if let last = lastClosed, last.id == gid, Date().timeIntervalSince(last.at) < 0.4 { return }
        close()

        let theme = ThemeStore.shared.theme
        let style = DockPrefs.shared.groups.first(where: { $0.id == gid })?.style ?? GroupStyle()
        let size = GroupPopupView.size(count: item.members.count, style: style)
        let view = GroupPopupView(initial: item, theme: theme) { [weak self] member in
            DockModel.shared.open(member)
            self?.close()
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)

        let p = PopupPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.contentView = host

        var x = anchorX - size.width / 2
        if let screen = NSScreen.screens.first {
            x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        }
        p.setFrameOrigin(NSPoint(x: x, y: anchorY))
        p.orderFrontRegardless()
        panel = p
        currentID = gid

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                     handler: { [weak self] _ in self?.close() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                    handler: { [weak self] event in
            if let self, event.window !== self.panel { self.close() }
            return event
        }) {
            monitors.append(m)
        }
    }

    func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        if let id = currentID { lastClosed = (id, Date()) }
        panel?.orderOut(nil)
        panel = nil
        currentID = nil
    }
}

struct GroupPopupView: View {
    let initial: DockItem
    let theme: DockTheme
    let onOpen: (DockItem) -> Void
    @ObservedObject var model = DockModel.shared
    @ObservedObject var prefs = DockPrefs.shared

    static let pad: CGFloat = 16
    static let titleHeight: CGFloat = 26

    /// Actuele groep uit het model, zodat het venster meebeweegt na het verslepen.
    private var group: DockItem {
        model.items.first(where: { $0.groupID == initial.groupID }) ?? initial
    }

    private var style: GroupStyle {
        prefs.groups.first(where: { $0.id == initial.groupID })?.style ?? GroupStyle()
    }

    static func metrics(count n: Int, style s: GroupStyle) -> (cols: Int, cell: CGSize) {
        let icon = CGFloat(s.iconSize)
        switch s.layout {
        case .grid:
            let cols = s.columns > 0 ? min(s.columns, max(n, 1)) : max(1, min(n, 4))
            return (cols, CGSize(width: max(icon + 36, 72), height: icon + (s.showNames ? 38 : 20)))
        case .list:
            return (1, CGSize(width: icon + (s.showNames ? 190 : 24), height: max(icon, 28) + 12))
        }
    }

    static func size(count n: Int, style s: GroupStyle) -> CGSize {
        let m = metrics(count: n, style: s)
        let rows = max(1, (n + m.cols - 1) / m.cols)
        return CGSize(width: CGFloat(m.cols) * m.cell.width + pad * 2,
                      height: CGFloat(rows) * m.cell.height + pad * 2 + titleHeight)
    }

    var body: some View {
        let g = group
        let st = style
        let m = Self.metrics(count: g.members.count, style: st)
        let total = Self.size(count: g.members.count, style: st)
        VStack(spacing: 0) {
            Text(g.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 2)
                .frame(height: Self.titleHeight)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(m.cell.width), spacing: 0), count: m.cols),
                      spacing: 0) {
                ForEach(g.members) { item in
                    GroupCell(item: item, theme: theme, groupID: g.groupID, style: st, cell: m.cell) {
                        onOpen(item)
                    }
                }
            }
        }
        .padding(Self.pad)
        .background { backdrop(st) }
        .frame(width: total.width, height: total.height)
    }

    @ViewBuilder
    private func backdrop(_ st: GroupStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        switch st.background {
        case .theme:
            ZStack {
                VisualEffectBlur()
                theme.colorA.color.opacity(0.45)
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 1))
        case .glass:
            VisualEffectBlur()
                .clipShape(shape)
                .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 1))
        case .none:
            Color.clear
        }
    }
}

struct GroupCell: View {
    let item: DockItem
    let theme: DockTheme
    let groupID: UUID?
    let style: GroupStyle
    let cell: CGSize
    let onTap: () -> Void
    @State private var hovering = false

    private var icon: some View {
        Image(nsImage: item.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: CGFloat(style.iconSize), height: CGFloat(style.iconSize))
            .scaleEffect(hovering && style.layout == .grid ? 1.12 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }

    private var dot: some View {
        Circle()
            .fill(theme.indicatorColor.color)
            .frame(width: 4, height: 4)
            .opacity(item.isRunning ? 1 : 0)
    }

    var body: some View {
        Group {
            if style.layout == .list {
                HStack(spacing: 10) {
                    icon
                    if style.showNames {
                        Text(item.name)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        dot
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: cell.width, height: cell.height, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.14 : 0)))
            } else {
                VStack(spacing: 4) {
                    icon
                    if style.showNames {
                        Text(item.name)
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .lineLimit(1)
                            .frame(width: cell.width - 8)
                    }
                    dot
                }
                .frame(width: cell.width, height: cell.height)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .onDrag { NSItemProvider(object: item.id as NSString) }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            guard let gid = groupID else { return false }
            return DockDrop.place(providers, before: item.id, in: gid)
        }
        .contextMenu { ItemContextMenu(item: item, inGroup: groupID) }
    }
}

// MARK: Slepen

enum DockDrop {
    /// Zet een gesleept item voor een ander item in dezelfde groep.
    static func place(_ providers: [NSItemProvider], before target: String, in gid: UUID) -> Bool {
        var accepted = false
        for p in providers where p.canLoadObject(ofClass: NSString.self) {
            accepted = true
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let id = (obj as? NSString) as String?,
                      id.hasPrefix("/") || id.hasPrefix("ha:") else { return }
                DispatchQueue.main.async { DockPrefs.shared.place(id, before: target, in: gid) }
            }
        }
        return accepted
    }

    /// Verwerkt gesleepte items (uit de dock zelf of .app-bestanden uit Finder) op een groep.
    static func handle(_ providers: [NSItemProvider], into gid: UUID) -> Bool {
        var accepted = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier("public.file-url") {
                accepted = true
                p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    var url: URL?
                    if let d = data as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                    else if let u = data as? URL { url = u }
                    guard let path = url?.standardizedFileURL.path, path.hasSuffix(".app") else { return }
                    DispatchQueue.main.async {
                        DockPrefs.shared.pin(path)
                        DockPrefs.shared.add(path, to: gid)
                    }
                }
            } else if p.canLoadObject(ofClass: NSString.self) {
                accepted = true
                _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let id = (obj as? NSString) as String?,
                          id.hasPrefix("/") || id.hasPrefix("ha:") else { return }
                    DispatchQueue.main.async { DockPrefs.shared.add(id, to: gid) }
                }
            }
        }
        return accepted
    }
}
