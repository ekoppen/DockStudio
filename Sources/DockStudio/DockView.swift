import SwiftUI
import AppKit

/// Blur-achtergrond (zoals het echte Dock).
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: Muis-tracking

/// Positie van de muis binnen het dock-venster (nil = buiten).
final class DockHover: ObservableObject {
    static let shared = DockHover()
    @Published var mouse: CGPoint?
}

final class TrackerView: NSView {
    var onMove: ((CGPoint?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onMove?(nil)
    }
}

struct MouseTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let v = TrackerView()
        v.onMove = onMove
        return v
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onMove = onMove
    }
}

// MARK: Layout

enum DockLayout {
    static let dotArea: CGFloat = 8

    /// Hoogte van alleen de dock-balk (zonder ruimte voor vergroting/schaduw).
    static func barHeight(_ t: DockTheme) -> CGFloat {
        CGFloat(t.iconSize) + dotArea + CGFloat(t.paddingTop + t.paddingBottom)
    }

    /// Breedte van de balk zonder vergroting.
    static func barWidth(_ t: DockTheme, count: Int) -> CGFloat {
        barWidth(t, scales: [CGFloat](repeating: 1, count: max(count, 1)))
    }

    /// Breedte van de balk bij gegeven icoon-schalen.
    static func barWidth(_ t: DockTheme, scales: [CGFloat]) -> CGFloat {
        let icon = CGFloat(t.iconSize)
        let n = CGFloat(scales.count)
        return scales.reduce(0) { $0 + icon * $1 }
            + max(n - 1, 0) * CGFloat(t.spacing)
            + CGFloat(t.paddingLeft + t.paddingRight)
    }

    /// Hoogte die een icoon boven de balk uit kan steken (vergroting).
    static func overshoot(_ t: DockTheme) -> CGFloat {
        CGFloat(t.iconSize) * CGFloat(max(t.magnification - 1, 0))
    }

    /// Grootte van het hele dock-venster (incl. ruimte voor vergroting, stuiteren, labels en schaduw).
    static func panelSize(theme t: DockTheme, count: Int) -> CGSize {
        let n = CGFloat(max(count, 1))
        let icon = CGFloat(t.iconSize)
        let extra = overshoot(t)
        let barW = barWidth(t, count: count)
        let width = barW + extra * min(n, CGFloat(t.magnificationRange) * 2.5 + 1)
            + CGFloat(t.shadowRadius) * 2 + 40
        let height = barHeight(t) + extra + icon * 0.35 + max(CGFloat(t.bottomMargin), 0)
            + CGFloat(t.shadowRadius) + 12 + (t.showLabels ? 34 : 0)
        return CGSize(width: width, height: height)
    }

    /// Midden-x van elk icoon (balk staat gecentreerd in het venster).
    static func centers(_ t: DockTheme, scales: [CGFloat], panelWidth: CGFloat) -> [CGFloat] {
        let icon = CGFloat(t.iconSize)
        let total = barWidth(t, scales: scales)
        var x = (panelWidth - total) / 2 + CGFloat(t.paddingLeft)
        var out: [CGFloat] = []
        for s in scales {
            let w = icon * s
            out.append(x + w / 2)
            x += w + CGFloat(t.spacing)
        }
        return out
    }

    struct HoverResult {
        var scales: [CGFloat]
        var weights: [CGFloat]   // 0...1: hoe dicht de muis bij elk icoon is
        var active: Bool         // muis bevindt zich boven de dock
    }

    /// Schaal en gewicht per icoon op basis van de muispositie (zachte klokvorm, zoals het echte Dock).
    static func hover(theme t: DockTheme, count n: Int, panelWidth W: CGFloat, mouse: CGPoint?) -> HoverResult {
        var s = [CGFloat](repeating: 1, count: n)
        var w = [CGFloat](repeating: 0, count: n)
        let inactive = HoverResult(scales: s, weights: w, active: false)
        guard n > 0, let m = mouse else { return inactive }

        let icon = CGFloat(t.iconSize)
        let mag = CGFloat(max(t.magnification, 1))
        let range = max(icon * CGFloat(t.magnificationRange), 1)
        let top = max(CGFloat(t.bottomMargin), 0) + barHeight(t) + icon * (mag - 1)

        let baseW = barWidth(t, scales: s)
        let margin = icon * 0.5 + icon * (mag - 1) * 1.5
        let left = (W - baseW) / 2 - margin
        let right = (W + baseW) / 2 + margin
        guard m.y <= top, m.x >= left, m.x <= right else { return inactive }

        // Een paar iteraties: de balk wordt breder, dus de iconen schuiven op.
        for _ in 0..<3 {
            let cs = centers(t, scales: s, panelWidth: W)
            w = cs.map { c in
                let d = Double((m.x - c) / range)
                return CGFloat(exp(-d * d))
            }
            s = w.map { 1 + (mag - 1) * $0 }
        }
        return HoverResult(scales: s, weights: w, active: true)
    }

    /// Welk icoon staat onder de muis (voor het label)?
    static func hoveredIndex(theme t: DockTheme, scales: [CGFloat], panelWidth: CGFloat, mouse: CGPoint?) -> Int? {
        guard let m = mouse, !scales.isEmpty else { return nil }
        let icon = CGFloat(t.iconSize)
        let top = max(CGFloat(t.bottomMargin), 0) + barHeight(t) + overshoot(t)
        guard m.y <= top else { return nil }
        let cs = centers(t, scales: scales, panelWidth: panelWidth)
        for (i, c) in cs.enumerated() {
            let w = icon * scales[i]
            if abs(m.x - c) <= (w + CGFloat(t.spacing)) / 2 { return i }
        }
        return nil
    }
}

// MARK: Views

struct DockBackground: View {
    let theme: DockTheme

    var body: some View {
        let shape = theme.makeShape()
        ZStack {
            if theme.useBlur { VisualEffectBlur() }
            if theme.useGradient {
                LinearGradient(colors: [theme.colorA.color, theme.colorB.color],
                               startPoint: .top, endPoint: .bottom)
            } else {
                theme.colorA.color
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(theme.borderColor.color, lineWidth: theme.borderWidth))
        .shadow(color: .black.opacity(0.35), radius: theme.shadowRadius, y: 4)
    }
}

struct DockIconView: View {
    let item: DockItem
    let theme: DockTheme
    let scale: CGFloat
    let weight: CGFloat
    let dimActive: Bool
    let isBouncing: Bool
    let showLabel: Bool
    let onTap: () -> Void

    var body: some View {
        let size = CGFloat(theme.iconSize) * scale

        VStack(spacing: 0) {
            TimelineView(.animation(paused: !isBouncing)) { ctx in
                iconBody(size)
                    .shadow(color: .black.opacity(0.45), radius: CGFloat(theme.iconShadow),
                            y: CGFloat(theme.iconShadow) / 3)
                    .offset(y: bounceOffset(ctx.date))
            }
            .frame(width: size, height: size)
            .background { glowView(size) }

            Circle()
                .fill(theme.indicatorColor.color)
                .frame(width: 4, height: 4)
                .opacity(item.isRunning ? 1 : 0)
                .frame(height: DockLayout.dotArea)
        }
        .frame(width: size)
        .opacity(dimOpacity)
        .saturation(dimSaturation)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .overlay(alignment: .top) {
            if showLabel {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .offset(y: -30)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 0 = andere iconen niet gedimd, 1 = volledig gedimd
    private var dimFactor: CGFloat {
        guard theme.dimOthers, dimActive else { return 0 }
        return CGFloat(theme.dimAmount) * (1 - weight)
    }

    private var dimOpacity: Double { Double(1 - dimFactor) }

    private var dimSaturation: Double {
        theme.dimDesaturate ? Double(1 - dimFactor) : 1
    }

    @ViewBuilder
    private func glowView(_ size: CGFloat) -> some View {
        if theme.glowEnabled && weight > 0.01 {
            let d = size * CGFloat(theme.glowSize) * 1.5
            Circle()
                .fill(RadialGradient(
                    colors: [theme.glowColor.color, theme.glowColor.color.opacity(0)],
                    center: .center, startRadius: 0, endRadius: d / 2))
                .frame(width: d, height: d)
                .opacity(Double(weight) * theme.glowIntensity)
                .allowsHitTesting(false)
        }
    }

    private func bounceOffset(_ date: Date) -> CGFloat {
        guard isBouncing else { return 0 }
        let t = date.timeIntervalSinceReferenceDate * 7
        return -CGFloat(abs(sin(t))) * CGFloat(theme.iconSize) * 0.35
    }

    @ViewBuilder
    private func iconBody(_ size: CGFloat) -> some View {
        let inset = CGFloat(theme.iconInset) * scale
        let shape = theme.iconShape.makeShape(size: size)
        let content = ZStack {
            if theme.iconBackgroundEnabled {
                shape.fill(theme.iconBackgroundColor.color)
            }
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .padding(inset)
        }
        .frame(width: size, height: size)

        if theme.iconShape == .original {
            content
        } else {
            content.clipShape(shape)
        }
    }
}

struct DockView: View {
    @ObservedObject var store: ThemeStore
    @ObservedObject var model: DockModel
    @ObservedObject var hover = DockHover.shared

    private func tapped(_ item: DockItem, index: Int, panelWidth: CGFloat) {
        guard item.groupID != nil else { model.open(item); return }
        let t = store.theme
        let rest = [CGFloat](repeating: 1, count: model.items.count)
        let cs = DockLayout.centers(t, scales: rest, panelWidth: panelWidth)
        guard index < cs.count, let f = DockWindowController.shared.panelFrame else { return }
        GroupPopup.shared.toggle(item,
                                 anchorX: f.minX + cs[index],
                                 anchorY: f.minY + max(CGFloat(t.bottomMargin), 0) + DockLayout.barHeight(t) + 10)
    }

    var body: some View {
        let t = store.theme
        let items = model.items
        let size = DockLayout.panelSize(theme: t, count: items.count)
        let hv = DockLayout.hover(theme: t, count: items.count,
                                  panelWidth: size.width, mouse: hover.mouse)
        let scales = hv.scales
        let hovered = DockLayout.hoveredIndex(theme: t, scales: scales,
                                              panelWidth: size.width, mouse: hover.mouse)
        let barW = DockLayout.barWidth(t, scales: scales)

        ZStack(alignment: .bottom) {
            if t.showBackground {
                DockBackground(theme: t)
                    .frame(width: barW, height: DockLayout.barHeight(t))
            } else {
                Color.clear
                    .frame(width: barW, height: DockLayout.barHeight(t))
            }

            HStack(alignment: .bottom, spacing: CGFloat(t.spacing)) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    DockIconView(
                        item: item,
                        theme: t,
                        scale: i < scales.count ? scales[i] : 1,
                        weight: i < hv.weights.count ? hv.weights[i] : 0,
                        dimActive: hv.active,
                        isBouncing: model.bouncing.contains(item.id),
                        showLabel: t.showLabels && hovered == i
                    ) { tapped(item, index: i, panelWidth: size.width) }
                    .contextMenu { ItemContextMenu(item: item) }
                }
            }
            .padding(.bottom, CGFloat(t.paddingBottom))
            .offset(x: CGFloat(t.paddingLeft - t.paddingRight) / 2)
        }
        .padding(.bottom, max(CGFloat(t.bottomMargin), 0))
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .animation(.spring(response: max(t.animResponse, 0.01), dampingFraction: t.animDamping),
                   value: hover.mouse)
        .background(MouseTracker { hover.mouse = $0 })
    }
}
