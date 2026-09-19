// Checks the updater against a real signed build: `./build.sh release` first, then
//   swiftc -swift-version 5 -parse-as-library Sources/Updater.swift Tests/Update.swift -o build/update-check && build/update-check
// It updates a copy of the app marked as an older version, and must refuse a tampered zip or signature.
import AppKit

@main
struct UpdateCheck {
    @MainActor static func main() async throws {
        precondition(Updater.newer("1.10", than: "1.9") && Updater.newer("1.2", than: "1.1.9") && !Updater.newer("1.1", than: "1.1"))

        let build = URL(fileURLWithPath: "build").standardizedFileURL
        let zip = build.appendingPathComponent("Time-Zones-mac.zip"), sig = build.appendingPathComponent("Time-Zones-mac.zip.sig")
        let data = try Data(contentsOf: zip), s = try Data(contentsOf: sig)
        precondition(Updater.verified(data, s), "the release signature checks out")
        var bad = data; bad[bad.count / 2] ^= 1
        precondition(!Updater.verified(bad, s), "a changed zip is refused")

        let version = Bundle(url: build.appendingPathComponent("Time Zones.app"))!.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        func release(_ zipURL: URL) throws -> Updater.Release {
            let json = """
            {"tag_name":"v\(version)","html_url":"https://example.com","assets":[
             {"name":"Time-Zones-mac.zip","browser_download_url":"\(zipURL.absoluteString)"},
             {"name":"Time-Zones-mac.zip.sig","browser_download_url":"\(sig.absoluteString)"}]}
            """
            return try JSONDecoder().decode(Updater.Release.self, from: Data(json.utf8))
        }

        // An "installed" copy that says it's older.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("update-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appendingPathComponent("Time Zones.app")
        try FileManager.default.copyItem(at: build.appendingPathComponent("Time Zones.app"), to: app)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let info = NSMutableDictionary(contentsOf: plist)!
        info["CFBundleShortVersionString"] = "1.0"
        info.write(to: plist, atomically: true)
        func installed() -> String { NSDictionary(contentsOf: plist)!["CFBundleShortVersionString"] as! String }

        let tampered = dir.appendingPathComponent("tampered.zip")
        try bad.write(to: tampered)
        do { try await Updater.replace(app, with: release(tampered)); preconditionFailure("tampered zip installed") }
        catch Updater.Failure.signature { precondition(installed() == "1.0", "left untouched") }

        try await Updater.replace(app, with: release(zip))
        precondition(installed() == version, "updated to \(version)")
        let v = try Process.run(URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["-v", app.path]); v.waitUntilExit()
        precondition(v.terminationStatus == 0, "signature of the installed app is intact")
        let q = try Process.run(URL(fileURLWithPath: "/usr/bin/xattr"), arguments: ["-p", "com.apple.quarantine", app.path]); q.waitUntilExit()
        precondition(q.terminationStatus != 0, "no quarantine flag, so no Open Anyway")
        print("ok: refused tampered zip, updated 1.0 -> \(version), codesign valid, no quarantine")
    }
}
