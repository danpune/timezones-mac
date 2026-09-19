import Foundation

struct Place: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var zone: String
    var lat: Double?
    var lon: Double?
    var cc: String
    var label: String?
    var pinned = false

    var shown: String { label.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? name }
    var tz: TimeZone { TimeZone(identifier: zone) ?? .current }
    var flag: String { Place.flag(cc) }

    // Menu bar code: a rename as typed, else "SF" / "NY" for two words, "MUM" / "LON" for one.
    var short: String {
        if let l = label?.trimmingCharacters(in: .whitespaces), !l.isEmpty { return String(l.prefix(8)) }
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        if words.count > 1 { return words.prefix(3).compactMap(\.first).map(String.init).joined().uppercased() }
        return String(name.prefix(3)).uppercased()
    }

    static func flag(_ cc: String) -> String {
        guard cc.count == 2, cc.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return "" }
        return String(String.UnicodeScalarView(cc.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }))
    }

    static func zoneCity(_ z: String) -> String { (z.split(separator: "/").last.map(String.init) ?? z).replacingOccurrences(of: "_", with: " ") }
}

// About 6,300 cities (GeoNames, CC BY 4.0): the website's cities.txt, most populous first.
// Line 1 is the zone table; rows are name|lat|lon|zoneIndex|CC|capital|state.
final class Catalog {
    static let shared = Catalog()

    struct Row { let place: Place; let key: String; let capital: Bool }
    private(set) var rows: [Row] = []
    private var countries: [(key: String, cc: String)] = []

    private init() {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let head = lines.first else { return }
        let zones = head.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        for line in lines.dropFirst() {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, let la = Double(f[1]), let lo = Double(f[2]), let zi = Int(f[3]), zi < zones.count else { continue }
            let p = Place(name: f[0], zone: zones[zi], lat: la, lon: lo, cc: f[4])
            rows.append(Row(place: p, key: Catalog.norm(f[0]), capital: f[5] == "1"))
        }
        let en = Locale(identifier: "en_US")
        var seen = Set<String>()
        for r in rows where seen.insert(r.place.cc).inserted {
            if let n = en.localizedString(forRegionCode: r.place.cc) { countries.append((Catalog.norm(n), r.place.cc)) }
        }
        for (alias, cc) in ["usa": "US", "us": "US", "america": "US", "uk": "GB", "britain": "GB", "england": "GB",
                            "scotland": "GB", "wales": "GB", "uae": "AE", "vietnam": "VN", "south korea": "KR",
                            "korea": "KR", "russia": "RU", "czechia": "CZ", "turkey": "TR", "holland": "NL"] {
            countries.append((alias, cc))
        }
    }

    static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
            .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    func countryName(_ cc: String) -> String { Locale(identifier: "en_US").localizedString(forRegionCode: cc) ?? cc }

    /// Countries resolve to their capital, then cities by prefix, then by substring.
    func search(_ q: String, limit: Int = 7) -> [Place] {
        let k = Catalog.norm(q)
        guard !k.isEmpty else { return [] }
        var out: [Place] = [], seen = Set<String>()
        func add(_ p: Place) {
            guard out.count < limit, seen.insert(p.name + "|" + p.zone).inserted else { return }
            out.append(p)
        }
        // "UTC+5:30", "GMT-3", "+9": a fixed offset (no daylight saving, no sky colour).
        if let m = k.wholeMatch(of: #/(?:utc|gmt)?\s*([+\-\u2212])\s*(\d{1,2})(?:[:.]?(\d{2}))?/#), let h = Int(m.2), h <= 14 {
            let mins = h * 60 + (m.3.flatMap { Int($0) } ?? 0), sign = m.1 == "+" ? 1 : -1
            let whole = mins % 60 == 0 && h <= 12
            // Etc/GMT names are sign-inverted (Etc/GMT-9 is UTC+9) but are real IANA zones the website accepts.
            let zone = whole ? (mins == 0 ? "Etc/UTC" : "Etc/GMT\(sign > 0 ? "-" : "+")\(h)") : TimeZone(secondsFromGMT: sign * mins * 60)?.identifier
            if let zone, TimeZone(identifier: zone) != nil {
                let label = "UTC" + (mins == 0 ? "" : (sign > 0 ? "+" : "\u{2212}") + "\(h)" + (mins % 60 == 0 ? "" : String(format: ":%02d", mins % 60)))
                add(Place(name: label, zone: zone, lat: nil, lon: nil, cc: ""))
            }
        }
        // Zone words people type: "PST", "Eastern", "IST". Each resolves to that zone's biggest city.
        if let z = Catalog.zoneWords[k] {
            add(city(inZone: z) ?? Place(name: z == "Etc/UTC" ? "UTC" : Place.zoneCity(z), zone: z, lat: nil, lon: nil, cc: ""))
        }
        for c in countries where c.key == k || (k.count >= 3 && c.key.hasPrefix(k)) {
            if let cap = rows.first(where: { $0.place.cc == c.cc && $0.capital }) ?? rows.first(where: { $0.place.cc == c.cc }) { add(cap.place) }
        }
        for r in rows where r.key.hasPrefix(k) { add(r.place); if out.count >= limit { break } }
        if k.count >= 3 { for r in rows where r.key.contains(k) { add(r.place); if out.count >= limit { break } } }
        // IANA zones as a last resort ("Etc/UTC", "Asia/Dubai"): no coordinates, so no sky colour.
        for z in TimeZone.knownTimeZoneIdentifiers where Catalog.norm(Place.zoneCity(z)).hasPrefix(k) || Catalog.norm(z) == k {
            add(Place(name: Place.zoneCity(z), zone: z, lat: nil, lon: nil, cc: ""))
        }
        return out
    }

    static let zoneWords: [String: String] = {
        var m: [String: String] = [:]
        for (z, ws) in ["America/New_York": ["est", "edt", "et", "eastern", "eastern time"],
                        "America/Chicago": ["cst", "cdt", "ct", "central", "central time"],
                        "America/Denver": ["mst", "mdt", "mt", "mountain", "mountain time"],
                        "America/Los_Angeles": ["pst", "pdt", "pt", "pacific", "pacific time"],
                        "Asia/Kolkata": ["ist", "india time"], "Europe/London": ["gmt", "bst", "uk time"],
                        "Europe/Paris": ["cet", "cest"], "Asia/Tokyo": ["jst"], "Australia/Sydney": ["aest", "aedt"],
                        "Etc/UTC": ["utc", "zulu"]] { for w in ws { m[w] = z } }
        return m
    }()

    /// The biggest city in a zone, for the viewer's own place.
    func city(inZone z: String) -> Place? { rows.first(where: { $0.place.zone == z })?.place }
}
