import Foundation
import AppKit

/// Zoekt nieuwe releases op GitHub en installeert ze (vervangt de app en start opnieuw).
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "ekoppen/DockStudio"
    private let autoKey = "dockstudio.autoCheckUpdates"
    private let tokenAccount = "github"

    @Published var status = ""
    @Published var busy = false
    @Published var availableVersion: String?
    @Published var tokenSaved: Bool
    @Published var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: autoKey) }
    }

    private var assetURL: URL?
    private var cachedToken: String?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private init() {
        let d = UserDefaults.standard
        autoCheck = d.object(forKey: autoKey) == nil ? true : d.bool(forKey: autoKey)
        let t = Keychain.get(account: tokenAccount)
        cachedToken = t
        tokenSaved = t != nil
    }

    func saveToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(t, account: tokenAccount)
        cachedToken = t.isEmpty ? nil : t
        tokenSaved = cachedToken != nil
        status = tokenSaved ? "GitHub-token opgeslagen." : "GitHub-token verwijderd."
    }

    func checkOnLaunch() {
        guard autoCheck else { return }
        Task { await check(silent: true) }
    }

    // MARK: Zoeken

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let url: String }
        let tag_name: String
        let draft: Bool
        let assets: [Asset]
    }

    private func makeRequest(_ url: URL, accept: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("DockStudio", forHTTPHeaderField: "User-Agent")
        if let t = cachedToken { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        r.timeoutInterval = 20
        return r
    }

    func check(silent: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if !silent { status = "Zoeken naar updates…" }
        do {
            let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases?per_page=10")!
            let (data, resp) = try await URLSession.shared.data(
                for: makeRequest(url, accept: "application/vnd.github+json"))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                if !silent {
                    status = (code == 404 || code == 401 || code == 403)
                        ? "Geen toegang tot GitHub (\(code)). De repo is privé: vul hieronder een token in."
                        : "GitHub gaf fout \(code)."
                }
                return
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            let arch = Self.arch
            guard let rel = releases.first(where: { !$0.draft }),
                  let asset = rel.assets.first(where: { $0.name.hasSuffix(".zip") && $0.name.contains(arch) })
                        ?? rel.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                if !silent { status = "Geen release gevonden." }
                return
            }
            let latest = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if Self.isNewer(latest, than: currentVersion) {
                availableVersion = latest
                assetURL = URL(string: asset.url)
                status = "Versie \(latest) is beschikbaar (je hebt \(currentVersion))."
            } else {
                availableVersion = nil
                assetURL = nil
                if !silent { status = "Je hebt de nieuwste versie (\(currentVersion))." }
            }
        } catch {
            if !silent { status = "Zoeken mislukt: \(error.localizedDescription)" }
        }
    }

    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Installeren

    func install() async {
        guard !busy, let assetURL, let version = availableVersion else { return }
        busy = true
        defer { busy = false }
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            status = "Updaten kan alleen vanuit een DockStudio.app (niet met swift run)."
            return
        }
        do {
            status = "Downloaden van \(version)…"
            let (tmp, resp) = try await URLSession.shared.download(
                for: makeRequest(assetURL, accept: "application/octet-stream"))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { status = "Download mislukt (fout \(code))."; return }

            status = "Uitpakken…"
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("dockstudio-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tmp, to: zip)
            let out = work.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path]) == 0 else {
                status = "Uitpakken mislukt."
                return
            }
            let newApp = out.appendingPathComponent("DockStudio.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                status = "DockStudio.app zat niet in de download."
                return
            }
            guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
                status = "Geen schrijfrechten op \(appURL.deletingLastPathComponent().path)."
                return
            }

            // Hulpscript: wacht tot deze app stopt, vervangt hem en start de nieuwe.
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
            rm -rf "\(appURL.path)"
            ditto "\(newApp.path)" "\(appURL.path)"
            xattr -dr com.apple.quarantine "\(appURL.path)" 2>/dev/null
            open "\(appURL.path)"
            rm -rf "\(work.path)"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script]
            try p.run()
            status = "Herstarten…"
            NSApp.terminate(nil)
        } catch {
            status = "Updaten mislukt: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
