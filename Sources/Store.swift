import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var places: [Place] { didSet { save() } }
    @Published var h24: Bool { didSet { UserDefaults.standard.set(h24, forKey: "h24"); formatters = [:] } }
    @Published private(set) var now = Date()
    /// Planning: minutes past the current quarter hour. 0 means live.
    @Published var offsetMin: Double = 0
    // Panel state lives here: with only the Command Line Tools, SwiftUI's @State macro has no plugin.
    @Published var editing = false
    @Published var query = ""
    @Published var note: String?

    private var timer: Timer?
    private var formatters: [String: DateFormatter] = [:]

    init() {
        let d = UserDefaults.standard
        h24 = d.object(forKey: "h24") as? Bool
            ?? !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h").contains("a")
        if let data = d.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data), !saved.isEmpty {
            places = saved
        } else {
            places = Store.defaults()
        }
        schedule()
        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        for name in [NSNotification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in NSTimeZone.resetSystemTimeZone(); self?.formatters = [:]; self?.schedule() }
            }
        }
        // A sleeping Mac freezes timers; catch up the moment it wakes.
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        }
    }

    // Same defaults as the website. The Mac's own city leads if none of them shares its zone,
    // and the city furthest from it goes in the menu bar.
    static func defaults() -> [Place] {
        var ps = [
            Place(name: "Austin", zone: "America/Chicago", lat: 30.27, lon: -97.74, cc: "US"),
            Place(name: "San Francisco", zone: "America/Los_Angeles", lat: 37.77, lon: -122.42, cc: "US"),
            Place(name: "New York", zone: "America/New_York", lat: 40.71, lon: -74.01, cc: "US"),
            Place(name: "Mumbai", zone: "Asia/Kolkata", lat: 19.08, lon: 72.88, cc: "IN"),
            Place(name: "London", zone: "Europe/London", lat: 51.51, lon: -0.13, cc: "GB"),
        ]
        let home = TimeZone.current
        if let i = ps.firstIndex(where: { $0.zone == home.identifier }) {
            ps.insert(ps.remove(at: i), at: 0)
        } else if let me = Catalog.shared.city(inZone: home.identifier) {
            ps.insert(me, at: 0)
        }
        let now = Date()
        let gap = { (p: Place) in abs(p.tz.secondsFromGMT(for: now) - home.secondsFromGMT(for: now)) }
        if let far = ps.indices.max(by: { gap(ps[$0]) < gap(ps[$1]) }), gap(ps[far]) > 0 { ps[far].pinned = true }
        return ps
    }

    private func save() {
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: "places") }
    }

    /// Repaint exactly when the minute changes, not up to a minute late.
    func schedule() {
        timer?.invalidate()
        now = Date()
        let next = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        let t = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var planning: Bool { offsetMin != 0 }

    /// The instant everything shows: now, or a quarter-hour step from it while planning.
    var instant: Date {
        guard planning else { return now }
        let q = floor(now.timeIntervalSince1970 / 900) * 900
        return Date(timeIntervalSince1970: q + offsetMin * 60)
    }

    // MARK: formatting

    func formatter(_ zone: String, _ format: String) -> DateFormatter {
        let key = zone + "|" + format
        if let f = formatters[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: zone) ?? .current
        f.dateFormat = format
        formatters[key] = f
        return f
    }

    func time(_ p: Place, at t: Date) -> String { formatter(p.zone, h24 ? "HH:mm" : "h:mm a").string(from: t) }
    func clock(_ zone: String, _ t: Date) -> String { formatter(zone, h24 ? "HH:mm" : "h:mm a").string(from: t) }

    /// "your time", "−2h", "+10:30".
    func gap(_ p: Place, at t: Date) -> String {
        let d = (p.tz.secondsFromGMT(for: t) - TimeZone.current.secondsFromGMT(for: t)) / 60
        if d == 0 { return "your time" }
        let h = abs(d) / 60, m = abs(d) % 60
        return (d > 0 ? "+" : "\u{2212}") + "\(h)" + (m > 0 ? String(format: ":%02d", m) : "h")
    }

    /// Weekday only when it is a different day from yours.
    func weekday(_ p: Place, at t: Date) -> String? {
        let mine = formatter(TimeZone.current.identifier, "yyyyMMdd").string(from: t)
        return formatter(p.zone, "yyyyMMdd").string(from: t) == mine ? nil : formatter(p.zone, "EEE").string(from: t)
    }

    var menuTitle: String {
        places.filter(\.pinned).map { "\($0.short) \(time($0, at: now))" }.joined(separator: "   ")
    }

    // MARK: overlap, as on the website: every city at work 9–6, else every city awake 7 AM–10 PM

    var overlap: String? {
        guard places.count > 1 else { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: instant)
        let hours: [Date?] = (0..<24).map { cal.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
        func inHours(_ t: Date, _ z: TimeZone, _ lo: Int, _ hi: Int) -> Bool {
            var c = Calendar(identifier: .gregorian); c.timeZone = z
            let h = c.component(.hour, from: t); return h >= lo && h < hi
        }
        func cols(_ lo: Int, _ hi: Int) -> [Int] {
            (0..<24).filter { j in
                guard let t = hours[j] else { return false }
                return places.allSatisfy { inHours(t, $0.tz, lo, hi) && inHours(t.addingTimeInterval(3540), $0.tz, lo, hi) }
            }
        }
        let work = cols(9, 18)
        let use = work.isEmpty ? cols(7, 22) : work
        guard !use.isEmpty else { return "No shared time: there is no hour when every city is between \(h24 ? "07:00 and 22:00" : "7 AM and 10 PM")" }
        var runs: [(Int, Int)] = []
        for j in use { if let r = runs.last, r.1 == j { runs[runs.count - 1].1 = j + 1 } else { runs.append((j, j + 1)) } }
        let zone = TimeZone.current.identifier
        let end = { (k: Int) -> Date in k < 24 ? (hours[k] ?? day) : (hours[23] ?? day).addingTimeInterval(3600) }
        let range = { (a: Date, b: Date) -> String in
            let fa = self.clock(zone, a), fb = self.clock(zone, b)
            if !self.h24, fa.suffix(2) == fb.suffix(2) { return fa.dropLast(3) + "–" + fb }
            return fa + "–" + fb
        }
        let span = runs.compactMap { r in hours[r.0].map { range($0, end(r.1)) } }.joined(separator: ", ")
        return "Everyone is \(work.isEmpty ? "awake" : "at work"): \(span) your time (\(use.count)h)"
    }

    // MARK: actions

    func add(_ p: Place) {
        guard !places.contains(where: { $0.zone == p.zone && $0.name == p.name }) else { return }
        places.append(p)
    }

    func togglePin(_ p: Place) {
        if let i = places.firstIndex(where: { $0.id == p.id }) { places[i].pinned.toggle() }
    }

    func remove(_ p: Place) { places.removeAll { $0.id == p.id } }

    /// Open the full website with these cities, in the long link form it understands for any city.
    func openWebsite() {
        let tok = { (s: String) -> String in
            var o = ""
            for ch in s { o += ",&~#@%".contains(ch) ? (String(ch).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") : (ch == " " ? "_" : String(ch)) }
            return o
        }
        let list = places.map { p -> String in
            var s = tok(p.name)
            if let la = p.lat, let lo = p.lon { s += "@\(la):\(lo):\(p.zone)" + (p.cc.isEmpty ? "" : ":\(p.cc)") }
            if let l = p.label, !l.isEmpty { s += "~" + (l.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
            return s
        }.joined(separator: ",")
        let hash = list.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? list
        if let url = URL(string: "https://danpune.github.io/timezones/#" + hash) { NSWorkspace.shared.open(url) }
    }

    // MARK: launch at login (asks macOS; the user can turn it off in System Settings > Login Items)

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        objectWillChange.send()
    }
}
