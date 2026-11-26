import AppKit

/// Haalt een kleurenpalet uit een afbeelding (k-means op een klein formaat).
enum WallpaperPalette {
    static func currentWallpaperURL() -> URL? {
        guard let screen = NSScreen.screens.first else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    static func extract(from url: URL) -> Palette? {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let w = 48, h = 48
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        var pixels: [SIMD3<Double>] = []
        for i in 0..<(w * h) where buf[i * 4 + 3] > 128 {
            pixels.append(SIMD3(Double(buf[i * 4]) / 255,
                                Double(buf[i * 4 + 1]) / 255,
                                Double(buf[i * 4 + 2]) / 255))
        }
        guard pixels.count > 50 else { return nil }

        // k-means met vaste, op helderheid gespreide startpunten (deterministisch)
        let k = 6
        let sorted = pixels.sorted { lum($0) < lum($1) }
        var centers = (0..<k).map { sorted[(2 * $0 + 1) * sorted.count / (2 * k)] }
        var counts = [Int](repeating: 0, count: k)

        for _ in 0..<10 {
            var sums = [SIMD3<Double>](repeating: .zero, count: k)
            counts = [Int](repeating: 0, count: k)
            for p in pixels {
                var best = 0
                var bd = Double.infinity
                for j in 0..<k {
                    let d = p - centers[j]
                    let dd = (d * d).sum()
                    if dd < bd { bd = dd; best = j }
                }
                sums[best] += p
                counts[best] += 1
            }
            for j in 0..<k where counts[j] > 0 {
                centers[j] = sums[j] / Double(counts[j])
            }
        }

        let total = Double(pixels.count)
        let cl: [(c: SIMD3<Double>, share: Double)] = (0..<k)
            .filter { counts[$0] > 0 }
            .map { (c: centers[$0], share: Double(counts[$0]) / total) }
        guard !cl.isEmpty else { return nil }

        // Achtergrond: donkerste grote cluster. Voorgrond: lichtste cluster.
        let bgC = (cl.filter { $0.share >= 0.04 }.min { lum($0.c) < lum($1.c) } ?? cl[0]).c
        var fgC = (cl.filter { $0.share >= 0.01 }.max { lum($0.c) < lum($1.c) } ?? cl[0]).c
        if lum(fgC) - lum(bgC) < 0.45 {
            fgC = lum(bgC) < 0.5 ? SIMD3(0.93, 0.93, 0.95) : SIMD3(0.1, 0.1, 0.12)
        }
        let surfaceC = bgC + (fgC - bgC) * 0.12

        // Accent: levendig en veel voorkomend. Secundair: andere tint.
        func score(_ e: (c: SIMD3<Double>, share: Double)) -> Double {
            let (_, s, b) = hsb(e.c)
            guard s > 0.25, b > 0.35 else { return 0 }
            return s * b * pow(e.share, 0.3)
        }
        let ranked = cl.sorted { score($0) > score($1) }
        let accentEntry = ranked.first.flatMap { score($0) > 0 ? $0 : nil }
        let accentC = accentEntry?.c ?? fgC

        var secondaryC: SIMD3<Double>?
        if let a = accentEntry {
            let ah = hsb(a.c).h
            secondaryC = ranked.dropFirst().first { e in
                guard score(e) > 0 else { return false }
                let d = abs(hsb(e.c).h - ah)
                return min(d, 1 - d) > 0.08
            }?.c
        }
        if secondaryC == nil {
            let (h, s, b) = hsb(accentC)
            let ns = NSColor(hue: (h + 0.12).truncatingRemainder(dividingBy: 1),
                             saturation: max(s, 0.3), brightness: max(b, 0.6), alpha: 1)
                .usingColorSpace(.sRGB)
            secondaryC = ns.map { SIMD3(Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent)) }
        }

        return Palette(background: hex(bgC), surface: hex(surfaceC), foreground: hex(fgC),
                       accent: hex(accentC), secondary: hex(secondaryC ?? accentC))
    }

    private static func lum(_ c: SIMD3<Double>) -> Double {
        0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }

    private static func hsb(_ c: SIMD3<Double>) -> (h: Double, s: Double, b: Double) {
        let ns = NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }

    private static func hex(_ c: SIMD3<Double>) -> String {
        RGBA(min(max(c.x, 0), 1), min(max(c.y, 0), 1), min(max(c.z, 0), 1)).hex
    }
}

/// Volgt het bureaublad en maakt zo nodig automatisch een nieuw thema.
final class WallpaperWatcher {
    static let shared = WallpaperWatcher()
    private var lastKey = ""
    private var busy = false

    func start() {
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let store = ThemeStore.shared
        guard store.followWallpaper, !busy, let url = WallpaperPalette.currentWallpaperURL() else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(mtime)|\(store.followStyle.rawValue)"
        guard key != lastKey else { return }
        lastKey = key
        busy = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let palette = WallpaperPalette.extract(from: url)
            DispatchQueue.main.async {
                self?.busy = false
                if let palette { store.applyWallpaperTheme(palette, wallpaper: url) }
            }
        }
    }
}
