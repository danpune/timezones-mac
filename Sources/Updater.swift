import AppKit
import CryptoKit

/// Updates from GitHub Releases: checks the latest release at most every 12 hours, then installs it quietly
/// while the panel is closed and says so afterwards. Each release zip is signed with a key that lives only on
/// the owner's Mac (Tools/sign.swift), so nothing else can be installed; if the quiet install fails, the panel
/// offers the update as a button instead. A download made by the app itself carries no quarantine flag, so
/// there's no "Open Anyway" again.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let publicKey = "qVYpu4ctNu8qNKIU0XSSZnkqI13h1q4u5rwZPKYYf8g="
    static let latest = URL(string: "https://api.github.com/repos/danpune/timezones-mac/releases/latest")!

    struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    }

    enum Failure: Error { case missing, signature, contents }

    @Published private(set) var release: Release?
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    /// The version this launch was updated to, shown once in the panel.
    @Published private(set) var updated: String?
    /// Set by the status controller: nothing is installed under the user's nose while the panel is open.
    var idle: () -> Bool = { true }
    private var checked: Date?

    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private init() {
        let d = UserDefaults.standard
        if d.string(forKey: "announce") == Self.current { updated = Self.current }
        d.removeObject(forKey: "announce")
    }

    func checkIfDue() {
        if let c = checked, Date().timeIntervalSince(c) < 12 * 3600 { return }
        checked = Date()
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: Self.latest),
                  let r = try? JSONDecoder().decode(Release.self, from: data), Self.newer(r.version, than: Self.current) else { return }
            release = r
            installIfIdle()
        }
    }

    /// Quietly, while the panel is closed. Never twice for the same version: if that install didn't take
    /// (a version number that doesn't match its tag, say), the panel's Update button is left to the user.
    func installIfIdle() {
        guard let r = release, !busy, !failed, idle(), UserDefaults.standard.string(forKey: "installed") != r.version else { return }
        install()
    }

    /// The panel was closed: the "Updated" line has been seen, and a waiting update can go in now.
    func panelClosed() {
        updated = nil
        installIfIdle()
    }

    static func newer(_ a: String, than b: String) -> Bool { a.compare(b, options: .numeric) == .orderedDescending }

    func install() {
        guard let r = release, !busy else { return }
        busy = true
        failed = false
        Task {
            do {
                try await Self.replace(Bundle.main.bundleURL, with: r)
                UserDefaults.standard.set(r.version, forKey: "installed")   // don't install the same version twice
                UserDefaults.standard.set(r.version, forKey: "announce")    // the new copy says so once
                relaunch()
            } catch {
                busy = false
                failed = true
            }
        }
    }

    /// The release page: the one found by a check, or the tag of the version just installed.
    func openPage(_ version: String? = nil) {
        if let v = version, let u = URL(string: "https://github.com/danpune/timezones-mac/releases/tag/v" + v) { NSWorkspace.shared.open(u) }
        else if let r = release { NSWorkspace.shared.open(r.html_url) }
    }

    static func verified(_ zip: Data, _ sig: Data) -> Bool {
        guard let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(sig, for: zip)
    }

    /// Downloads the release, checks it and puts it where `app` is. Throws, leaving `app` untouched, if
    /// anything is off: a missing file, a bad signature, or a zip that isn't this app at that version.
    static func replace(_ app: URL, with r: Release) async throws {
        func asset(_ name: String) throws -> URL {
            guard let a = r.assets.first(where: { $0.name == name }) else { throw Failure.missing }
            return a.browser_download_url
        }
        let (zip, _) = try await URLSession.shared.data(from: asset("Time-Zones-mac.zip"))
        let (sig, _) = try await URLSession.shared.data(from: asset("Time-Zones-mac.zip.sig"))
        guard verified(zip, sig) else { throw Failure.signature }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("TimeZones-update-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("update.zip")
        try zip.write(to: file)
        let ditto = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", file.path, dir.path])
        ditto.waitUntilExit()
        let new = dir.appendingPathComponent("Time Zones.app")
        guard ditto.terminationStatus == 0, let b = Bundle(url: new), b.bundleIdentifier == "io.github.danpune.timezones",
              b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == r.version else { throw Failure.contents }
        _ = try fm.replaceItemAt(app, withItemAt: new)
    }

    /// Quits, then a tiny shell waits for this process to end and opens the new copy.
    private func relaunch() {
        let wait = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\""
        _ = try? Process.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", wait, Bundle.main.bundlePath])
        NSApp.terminate(nil)
    }
}
