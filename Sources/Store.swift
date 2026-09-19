import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var places: [Place] { didSet { save(); loadWeather() } }
    @Published var h24: Bool { didSet { UserDefaults.standard.set(h24, forKey: "h24"); formatters = [:] } }
    @Published private(set) var now = Date()
    /// A planned moment, or nil for live. Set from the date picker, the slider or a typed time.
    @Published var planned: Date?
    @Published var timeText = ""
    /// Asked once on first run: Apple's rules say launch at login must be the user's choice.
    @Published var askLogin = !UserDefaults.standard.bool(forKey: "askedLogin")
    @Published var fahrenheit: Bool { didSet { UserDefaults.standard.set(fahrenheit, forKey: "fahrenheit") } }
    @Published private(set) var weather: [String: Wx] = [:]
    private var wxBusy = false
    private var wxFailed: Date?
    @Published var hotkeyOn: Bool { didSet { UserDefaults.standard.set(hotkeyOn, forKey: "hotkey"); applyHotKey() } }
    // Panel state lives here: with only the Command Line Tools, SwiftUI's @State macro has no plugin.
    @Published var editing = false
    @Published var query = ""
    @Published var note: String? {
        didSet {
            guard let n = note else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: n, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            Task { @MainActor [weak self] in try? await Task.sleep(nanoseconds: 4_000_000_000); if self?.note == n { self?.note = nil } }
        }
    }
    private var closedAt: Date?
    @Published var hoverID: UUID?
    // Mouse reordering in the table: the dragged row follows the pointer and the list reorders
    // each time it crosses half a row, so the order is right the moment the mouse is released.
    @Published var dragID: UUID?
    @Published var dragOffset: CGFloat = 0
    private var dragFrom = 0
    static let rowHeight: CGFloat = 46
    static let rowStep: CGFloat = rowHeight + 1   // plus the divider

    private var timer: Timer?
    private var formatters: [String: DateFormatter] = [:]

    init() {
        let d = UserDefaults.standard
        h24 = d.object(forKey: "h24") as? Bool
            ?? !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h").contains("a")
        if let data = d.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data), !saved.isEmpty {
            // Lists saved before state flags existed: recover each city's state from the defaults or the catalogue.
            places = saved.map { p in
                guard p.st == nil, ["US", "CA", "AU"].contains(p.cc) else { return p }
                var q = p
                q.st = Store.defaults().first(where: { $0.name == p.name && $0.zone == p.zone })?.st ?? Catalog.shared.match(p)?.st
                return q
            }
        } else {
            places = Store.defaults()
        }
        hotkeyOn = d.object(forKey: "hotkey") as? Bool ?? true
        fahrenheit = d.object(forKey: "fahrenheit") as? Bool ?? (Locale.current.measurementSystem == .us)
        schedule()
        if launchAtLogin { askLogin = false }
        HotKey.action = { HotKey.togglePanel() }
        installKeys()
        applyHotKey()
        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        for name in [NSNotification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in NSTimeZone.resetSystemTimeZone(); self?.formatters = [:]; self?.schedule() }
            }
        }
        // A plan is for now-ish: reopening the panel more than 5 minutes after closing it goes back to live,
        // so a glance never shows an old plan as if it were the current time.
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.closedAt = Date() }
        }
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let c = self.closedAt, Date().timeIntervalSince(c) > 300 else { return }
                self.planned = nil; self.timeText = ""; self.query = ""
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
            Place(name: "Austin", zone: "America/Chicago", lat: 30.27, lon: -97.74, cc: "US", st: "TX"),
            Place(name: "San Francisco", zone: "America/Los_Angeles", lat: 37.77, lon: -122.42, cc: "US", st: "CA"),
            Place(name: "New York", zone: "America/New_York", lat: 40.71, lon: -74.01, cc: "US", st: "NY"),
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
            Task { @MainActor in self?.now = Date(); self?.loadWeather() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var planning: Bool { planned != nil }

    /// The instant everything shows: now, or the planned moment.
    var instant: Date { planned ?? now }

    // MARK: planning, in your own time (the Mac's zone)

    var minuteOfDay: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: instant)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Same day, new time. A time inside a spring-forward gap moves to the next valid minute.
    func setMinuteOfDay(_ m: Int, on day: Date? = nil) {
        let cal = Calendar.current, base = cal.startOfDay(for: day ?? instant)
        let m = max(0, min(1439, m))
        planned = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: base, matchingPolicy: .nextTime, direction: .forward)
            ?? base.addingTimeInterval(Double(m) * 60)
    }

    /// New day, same time of day.
    func setDay(_ d: Date) { setMinuteOfDay(Int(minuteOfDay), on: d) }

    /// "3pm", "3:30 pm", "15:30", "1530", "9". Same rules as the website's time box.
    static func parseTime(_ v: String) -> Int? {
        let s = v.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
        guard let m = s.wholeMatch(of: #/(\d{1,2})(?::?(\d{2}))?(am|pm|a|p)?/#) else { return nil }
        var h = Int(m.1) ?? 0
        let mi = m.2.flatMap { Int($0) } ?? 0
        guard mi <= 59 else { return nil }
        if let ap = m.3 {
            guard (1...12).contains(h) else { return nil }
            h = h % 12 + (ap.hasPrefix("p") ? 12 : 0)
        } else if h > 23 { return nil }
        return h * 60 + mi
    }

    /// Returns false when the text isn't a time, so the field can say so.
    func applyTyped() -> Bool {
        guard let m = Store.parseTime(timeText) else { return timeText.isEmpty }
        let wasLive = !planning
        setMinuteOfDay(m); timeText = ""
        if wasLive, let p = planned, p < now { planned = Calendar.current.date(byAdding: .day, value: 1, to: p) }
        return true
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
    /// "tomorrow" / "yesterday" when the city's date differs from yours (offsets never reach two days).
    func weekday(_ p: Place, at t: Date) -> String? {
        let mine = formatter(TimeZone.current.identifier, "yyyyMMdd").string(from: t)
        let theirs = formatter(p.zone, "yyyyMMdd").string(from: t)
        return theirs == mine ? nil : theirs > mine ? "tomorrow" : "yesterday"
    }

    /// "in 5h 15m", "2h ago", "in 1d 4h" for the planning readout.
    var planDistance: String? {
        guard planning else { return nil }
        let m = Int((instant.timeIntervalSince(now) / 60).rounded())
        guard abs(m) >= 1 else { return nil }
        let a = abs(m), d = a / 1440, h = a % 1440 / 60, mi = a % 60
        let s = d > 0 ? "\(d)d" + (h > 0 ? " \(h)h" : "") : h > 0 ? "\(h)h" + (mi > 0 ? " \(mi)m" : "") : "\(mi)m"
        return m > 0 ? "in " + s : s + " ago"
    }

    /// Shift the planned time by whole minutes (arrow keys), starting from now when live.
    func nudge(_ minutes: Int) {
        let base = planned ?? Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 900).rounded(.down) * 900)
        planned = base.addingTimeInterval(Double(minutes) * 60)
    }

    /// Tooltip on the time: "Sunrise 6:12 AM · Sunset 6:37 PM · 12h 25m of daylight" for that city's day.
    func dayText(_ p: Place, at t: Date) -> String? {
        guard let la = p.lat, let lo = p.lon else { return nil }
        var c = Calendar(identifier: .gregorian); c.timeZone = p.tz
        let d = Sky.day(from: c.startOfDay(for: t), lat: la, lon: lo)
        let f = { (x: Date) in self.clock(p.zone, x) }
        switch (d.rise, d.set) {
        case let (r?, s?) where s > r:
            let m = Int(s.timeIntervalSince(r) / 60)
            return "Sunrise \(f(r)) · Sunset \(f(s)) · \(m / 60)h \(m % 60)m of daylight"
        case let (r?, _): return "Sunrise \(f(r)) · no sunset that day"
        case let (_, s?): return "Sunset \(f(s)) · no sunrise that day"
        default: return Sky.sunAlt(t, lat: la, lon: lo) >= Sky.h0 ? "Sun up all day" : "Sun down all day"
        }
    }

    /// ← → move the planned time 15 minutes, Esc returns to now: only when no text field is being typed in.
    func installKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !(NSApp.keyWindow?.firstResponder is NSText) else { return e }
            switch e.keyCode {
            case 123: self.nudge(-15); return nil   // ←
            case 124: self.nudge(15); return nil    // →
            case 53: if self.planning { self.planned = nil; self.timeText = "" } else { HotKey.togglePanel() }; return nil   // Esc
            default: return e
            }
        }
    }

    /// "sunset 7:20" / "sunrise 6:26" in the city's own time; AM/PM is left off because the word says which.
    /// The next sunrise (rise true) or sunset in the city's own time, without AM/PM.
    func sunEvent(_ p: Place, at t: Date) -> (rise: Bool, time: String)? {
        guard let la = p.lat, let lo = p.lon, let e = Sky.nextEvent(t, lat: la, lon: lo) else { return nil }
        return (e.rise, formatter(p.zone, h24 ? "HH:mm" : "h:mm").string(from: e.at))
    }

    func sunText(_ p: Place, at t: Date) -> String? {
        guard let la = p.lat, let lo = p.lon else { return nil }
        guard let e = Sky.nextEvent(t, lat: la, lon: lo) else {
            return Sky.sunAlt(t, lat: la, lon: lo) >= Sky.h0 ? "sun up all day" : "sun down all day"
        }
        return (e.rise ? "sunrise " : "sunset ") + formatter(p.zone, h24 ? "HH:mm" : "h:mm").string(from: e.at)
    }

    var menuTitle: String {
        let pins = places.filter(\.pinned)
        let flags = pins.map(\.flag)
        return pins.map { p in
            let unique = !p.flag.isEmpty && flags.filter { $0 == p.flag }.count == 1
            let tag = pins.count == 1 ? (p.flag.isEmpty ? p.short : p.flag + " " + p.short) : unique ? p.flag : p.short
            return tag + " " + time(p, at: now)
        }.joined(separator: "  ")
    }

    // MARK: clock changes, as on the website: a zone's offset changes within a week before or two weeks after

    private static func clockChange(_ t: Date, _ z: TimeZone) -> (at: Date, d: Int)? {
        let day = 86_400.0, off = { (x: Date) in z.secondsFromGMT(for: x) / 60 }
        var a = t.addingTimeInterval(-7 * day), oa = off(a)
        var b = a.addingTimeInterval(day)
        while b <= t.addingTimeInterval(14 * day) {
            let ob = off(b)
            if ob != oa {
                var lo = a, hi = b
                while hi.timeIntervalSince(lo) > 60 { let m = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2); if off(m) == oa { lo = m } else { hi = m } }
                return (hi, ob - oa)
            }
            a = b; oa = ob; b = b.addingTimeInterval(day)
        }
        return nil
    }

    var clockNote: String? {
        let t = instant
        let cs = places.map { Store.clockChange(t, $0.tz) }
        struct G { let when: String; let at: Date; let d: Int; let past: Bool; var names: [String] }
        var groups: [G] = []
        for (p, c) in zip(places, cs) {
            guard let c else { continue }
            let when = formatter(p.zone, "EEE, MMM d").string(from: c.at), past = c.at <= t
            if let i = groups.firstIndex(where: { $0.when == when && $0.d == c.d && $0.past == past }) { groups[i].names.append(p.shown) }
            else { groups.append(G(when: when, at: c.at, d: c.d, past: past, names: [p.shown])) }
        }
        guard !groups.isEmpty else { return nil }
        let list = ListFormatter(); list.locale = Locale(identifier: "en_GB")
        let amt = { (d: Int) in abs(d) % 60 != 0 ? "\(abs(d)) min" : "\(abs(d) / 60)h" }
        let text = groups.sorted { $0.at < $1.at }.map { g in
            (list.string(from: g.names) ?? g.names.joined(separator: ", ")) + " "
                + (g.past ? "went" : g.names.count > 1 ? "go" : "goes") + (g.d > 0 ? " forward " : " back ") + amt(g.d) + " on " + g.when
        }.joined(separator: "; ")
        let first = cs.first ?? nil
        let shift = places.count > 1 && cs.contains { c in
            guard let c, let f = first else { return true }
            return c.d != f.d || abs(c.at.timeIntervalSince(f.at)) > 86_400
        }
        return "Clocks change: " + text + (shift ? ". The time differences between these cities change too." : ".")
    }

    // MARK: sharing

    /// "Sat, Sep 19" then "Austin: 9:00 AM", one city per line, the weekday when it differs ("Mumbai: 7:30 AM Sun").
    var timesText: String {
        let t = instant, home = TimeZone.current.identifier
        let lines = places.map { p -> String in
            let dd = weekday(p, at: t) == nil ? "" : " " + formatter(p.zone, "EEE").string(from: t)
            return "\(p.shown): \(time(p, at: t))" + dd
        }
        return ([formatter(home, "EEE, MMM d").string(from: t)] + lines).joined(separator: "\n")
    }

    private func copy(_ s: String, _ what: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        note = "Copied \(what)."
    }
    func copyTimes() { copy(timesText, "the times") }
    func copyLink() { if let u = websiteURL() { copy(u.absoluteString, "a link to the website with these cities") } }

    // MARK: weather from Open-Meteo (free, no key, CC BY 4.0), as on the website

    struct Wx { let t0: Double; let temp: [Double?]; let code: [Int?]; let fetched: Date }

    private func wxKey(_ p: Place) -> String? {
        guard let la = p.lat, let lo = p.lon, abs(la) <= 90, abs(lo) <= 180 else { return nil }
        return String(format: "%.2f,%.2f", la, lo)
    }

    /// One request for every city, hourly from yesterday to a week out, so a planned time shows
    /// that hour's forecast. Refreshed hourly; after a failure, retried in 10 minutes.
    func loadWeather() {
        guard !wxBusy, wxFailed.map({ Date().timeIntervalSince($0) > 600 }) ?? true else { return }
        let keys = Array(Set(places.compactMap(wxKey))).filter { weather[$0].map { Date().timeIntervalSince($0.fetched) > 3600 } ?? true }
        guard !keys.isEmpty else { return }
        let lat = keys.map { $0.split(separator: ",")[0] }.joined(separator: ","), lon = keys.map { $0.split(separator: ",")[1] }.joined(separator: ",")
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&hourly=temperature_2m,weather_code&past_days=1&forecast_days=7&timeformat=unixtime&timezone=GMT") else { return }
        wxBusy = true
        URLSession.shared.dataTask(with: url) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            let items = (json as? [[String: Any]]) ?? (json as? [String: Any]).map { [$0] } ?? []
            var got: [String: Wx] = [:]
            if ok, items.count == keys.count {
                for (k, it) in zip(keys, items) {
                    guard let h = it["hourly"] as? [String: Any], let times = h["time"] as? [Double], let t0 = times.first else { continue }
                    got[k] = Wx(t0: t0, temp: (h["temperature_2m"] as? [Any] ?? []).map { $0 as? Double },
                                code: (h["weather_code"] as? [Any] ?? []).map { $0 as? Int }, fetched: Date())
                }
            }
            Task { @MainActor in
                self.wxBusy = false
                // cities added while this request was out are fetched straight away, not at the next minute
                if got.isEmpty { self.wxFailed = Date() } else { self.weather.merge(got) { $1 }; self.loadWeather() }
            }
        }.resume()
    }

    /// Temperature in the chosen unit and an SF Symbol for the hour nearest t.
    func wx(_ p: Place, at t: Date) -> (temp: Int, symbol: String, words: String)? {
        guard let k = wxKey(p), let w = weather[k] else { return nil }
        let i = Int(((t.timeIntervalSince1970 - w.t0) / 3600).rounded())
        guard i >= 0, i < w.temp.count, i < w.code.count, let c = w.temp[i], let code = w.code[i] else { return nil }
        let day = (p.lat.flatMap { la in p.lon.map { Sky.sunAlt(t, lat: la, lon: $0) } } ?? 0) >= Sky.h0
        let look: (String, String) = code == 0 ? (day ? "sun.max.fill" : "moon.stars.fill", "clear")
            : code <= 2 ? (day ? "cloud.sun.fill" : "cloud.moon.fill", "partly cloudy")
            : code == 3 ? ("cloud.fill", "cloudy") : code <= 48 ? ("cloud.fog.fill", "fog")
            : code <= 57 ? ("cloud.drizzle.fill", "drizzle") : code <= 67 || (80...82).contains(code) ? ("cloud.rain.fill", "rain")
            : code <= 86 ? ("cloud.snow.fill", "snow") : ("cloud.bolt.rain.fill", "thunderstorm")
        return (Int((fahrenheit ? c * 9 / 5 + 32 : c).rounded()), look.0, look.1)
    }

    // MARK: keyboard shortcut ⌃⌥T

    private func applyHotKey() { if hotkeyOn { HotKey.register() } else { HotKey.unregister() } }

    // MARK: overlap, as on the website: every city at work 9–6, else every city awake 7 AM–10 PM

    /// Hours of your day (the day being shown) when everyone is at work, else when everyone is awake.
    /// Work hours skip a city's weekend, using its country's own weekend (Fri–Sat where that applies).
    var shared: (work: Bool, runs: [(Int, Int)], hours: [Date?])? {
        guard places.count > 1 else { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: instant)
        let hours: [Date?] = (0..<24).map { cal.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
        func inHours(_ t: Date, _ p: Place, _ lo: Int, _ hi: Int, work: Bool) -> Bool {
            var c = Calendar(identifier: .gregorian); c.timeZone = p.tz
            if !p.cc.isEmpty { c.locale = Locale(identifier: "en_" + p.cc) }
            if work && c.isDateInWeekend(t) { return false }
            let h = c.component(.hour, from: t); return h >= lo && h < hi
        }
        func cols(_ lo: Int, _ hi: Int, work: Bool) -> [Int] {
            (0..<24).filter { j in
                guard let t = hours[j] else { return false }
                return places.allSatisfy { inHours(t, $0, lo, hi, work: work) && inHours(t.addingTimeInterval(3540), $0, lo, hi, work: work) }
            }
        }
        let work = cols(9, 18, work: true)
        let use = work.isEmpty ? cols(7, 22, work: false) : work
        var runs: [(Int, Int)] = []
        for j in use { if let r = runs.last, r.1 == j { runs[runs.count - 1].1 = j + 1 } else { runs.append((j, j + 1)) } }
        return (!work.isEmpty, runs, hours)
    }

    var overlap: String? {
        guard let s = shared else { return nil }
        let runs = s.runs, hours = s.hours, day = Calendar.current.startOfDay(for: instant)
        guard !runs.isEmpty else { return "No shared time: there is no hour when every city is between \(h24 ? "07:00 and 22:00" : "7 AM and 10 PM")" }
        let zone = TimeZone.current.identifier
        let end = { (k: Int) -> Date in k < 24 ? (hours[k] ?? day) : (hours[23] ?? day).addingTimeInterval(3600) }
        let range = { (a: Date, b: Date) -> String in
            let fa = self.clock(zone, a), fb = self.clock(zone, b)
            if !self.h24, fa.suffix(2) == fb.suffix(2) { return fa.dropLast(3) + "–" + fb }
            return fa + "–" + fb
        }
        let span = runs.compactMap { r in hours[r.0].map { range($0, end(r.1)) } }.joined(separator: ", ")
        let total = runs.reduce(0) { $0 + $1.1 - $1.0 }
        return "Everyone is \(s.work ? "at work" : "awake"): \(span) your time (\(total)h)"
    }

    // MARK: actions

    func add(_ p: Place) {
        query = ""
        guard !places.contains(where: { $0.zone == p.zone && $0.name == p.name }) else { return }
        places.append(p)
        note = "Added \(p.name)."
    }

    func togglePin(_ p: Place) {
        if let i = places.firstIndex(where: { $0.id == p.id }) { places[i].pinned.toggle() }
    }

    func remove(_ p: Place) { guard places.count > 1 else { return }; places.removeAll { $0.id == p.id } }

    func move(_ p: Place, by d: Int) {
        guard let i = places.firstIndex(where: { $0.id == p.id }), places.indices.contains(i + d) else { return }
        places.swapAt(i, i + d)
    }

    /// Click the shared-time note to plan its first hour; while live, a time already gone means tomorrow.
    func planShared() {
        guard let s = shared, let first = s.runs.first, let t = s.hours[first.0] else { return }
        planned = !planning && t < now ? Calendar.current.date(byAdding: .day, value: 1, to: t) : t
    }

    func drag(_ id: UUID, by dy: CGFloat) {
        guard let cur = places.firstIndex(where: { $0.id == id }) else { return }
        if dragID != id { dragID = id; dragFrom = cur }
        let target = max(0, min(places.count - 1, dragFrom + Int((dy / Store.rowStep).rounded())))
        if target != cur { places.move(fromOffsets: IndexSet(integer: cur), toOffset: target > cur ? target + 1 : target) }
        dragOffset = dy - CGFloat(target - dragFrom) * Store.rowStep
    }

    func endDrag() { dragID = nil; dragOffset = 0 }

    func openWebsite() { if let u = websiteURL() { NSWorkspace.shared.open(u) } }

    /// The website with these cities, in the long link form it understands for any city,
    /// plus the planned date and time (in the first city's time, the site's default base).
    func websiteURL() -> URL? {
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
        var hash = list.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? list
        if planning, let first = places.first {
            hash += "&d=" + formatter(first.zone, "yyyy-MM-dd").string(from: instant) + "&t=" + formatter(first.zone, "HH:mm").string(from: instant)
        }
        return URL(string: "https://danpune.github.io/timezones/#" + hash)
    }

    // MARK: launch at login (asks macOS; the user can turn it off in System Settings > Login Items)

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        objectWillChange.send()
    }

    func answerLogin(_ yes: Bool) {
        UserDefaults.standard.set(true, forKey: "askedLogin")
        askLogin = false
        guard yes else { return }
        do { try setLaunchAtLogin(true); note = "Time Zones will open when you log in." }
        catch { note = "macOS needs your OK: System Settings > General > Login Items." }
    }
}
