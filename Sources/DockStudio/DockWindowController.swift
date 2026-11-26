import AppKit
import SwiftUI
import Combine

/// Beheert het zwevende dock-venster onderaan het scherm.
final class DockWindowController {
    static let shared = DockWindowController()

    private var panel: NSPanel?
    private var bag = Set<AnyCancellable>()
    private var systemDockHidden = false
    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var panelHidden = false

    // Slim verbergen
    private var wantsHidden = false
    private var revealed = false
    private var fullScreenHidden = false

    private let store = ThemeStore.shared
    private let model = DockModel.shared

    var panelFrame: NSRect? { panel?.frame }

    func start() {
        store.objectWillChange
            .merge(with: model.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &bag)

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.mouseMoved()
        }
        // Zolang het venster muisevents accepteert komen die via de lokale monitor binnen.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.mouseMoved()
            return event
        }

        apply()
    }

    /// Past venster en systeem-Dock aan op de huidige instellingen.
    func apply() {
        if store.dockEnabled {
            if panel == nil { createPanel() }
            if !systemDockHidden {
                systemDockHidden = true
                SystemDock.hide()
            }
            panel?.orderFrontRegardless()
            reposition()
            updateVisibility()
        } else {
            wantsHidden = false
            revealed = false
            fullScreenHidden = false
            panel?.alphaValue = 1
            panel?.orderOut(nil)
            if systemDockHidden {
                systemDockHidden = false
                SystemDock.restore()
            }
        }
    }

    func restoreNow() {
        store.dockEnabled = false
        systemDockHidden = false
        SystemDock.restore()
    }

    // MARK: Slim verbergen

    func setWantsHidden(_ v: Bool) {
        guard wantsHidden != v else { return }
        wantsHidden = v
        if !v { revealed = false }
        updateVisibility()
    }

    func setFullScreenHidden(_ v: Bool) {
        guard fullScreenHidden != v else { return }
        fullScreenHidden = v
        updateVisibility()
    }

    private func updateVisibility() {
        guard let panel else { return }
        let hide = fullScreenHidden || (wantsHidden && !revealed)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = store.theme.fadeDuration
            panel.animator().alphaValue = hide ? 0 : 1
        }
        panelHidden = hide
        refreshHitTest()
    }

    /// Het venster is groter dan de zichtbare dock (ruimte voor vergroting, labels, schaduw).
    /// Alleen op de dock zelf vangt het venster muisevents; daarboven gaat alles door naar de apps eronder.
    private func refreshHitTest() {
        guard let panel else { return }
        let t = store.theme
        let f = panel.frame
        let loc = NSEvent.mouseLocation
        let hovering = DockHover.shared.mouse != nil

        let icon = CGFloat(t.iconSize)
        let mag = CGFloat(max(t.magnification, 1))
        let baseW = DockLayout.barWidth(t, count: model.items.count)
        let extraX = hovering ? icon * 0.5 + icon * (mag - 1) * 1.5 : 6
        let bottom = max(CGFloat(t.bottomMargin), 0)
        let barTop = bottom + DockLayout.barHeight(t)
        let top = barTop + (hovering ? DockLayout.overshoot(t) : 4)
        let yMin = hovering ? f.minY : f.minY + max(bottom - 4, 0)
        let rect = NSRect(x: f.midX - baseW / 2 - extraX, y: yMin,
                          width: baseW + extraX * 2, height: f.minY + top - yMin)

        let ignore = panelHidden || !rect.contains(loc)
        if panel.ignoresMouseEvents != ignore {
            panel.ignoresMouseEvents = ignore
            if ignore { DockHover.shared.mouse = nil }
        }
    }

    private func mouseMoved() {
        refreshHitTest()
        guard wantsHidden, let panel, let screen = NSScreen.screens.first else { return }
        let loc = NSEvent.mouseLocation
        let f = panel.frame
        if !revealed {
            if loc.y <= screen.frame.minY + 2, loc.x >= f.minX, loc.x <= f.maxX {
                revealed = true
                updateVisibility()
            }
        } else if loc.y > f.maxY + 10 {
            revealed = false
            updateVisibility()
        }
    }

    // MARK: Venster

    private func createPanel() {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.acceptsMouseMovedEvents = true
        p.contentView = NSHostingView(rootView: DockView(store: store, model: model))
        panel = p
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let size = DockLayout.panelSize(theme: store.theme, count: model.items.count)
        let t = store.theme
        let frame = NSRect(x: screen.frame.midX - size.width / 2 + CGFloat(t.offsetX),
                           y: screen.frame.minY + min(CGFloat(t.bottomMargin), 0),
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }
}
