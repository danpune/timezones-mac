import SwiftUI

// The same sun maths and sky colours as the website, so a tile here matches a tile there.
enum Sky {
    private static let rad = Double.pi / 180

    // Low-precision solar position (NOAA). The sun's altitude in degrees.
    static func sunAlt(_ t: Date, lat: Double, lon: Double) -> Double {
        let d = t.timeIntervalSince1970 / 86_400 + 2440587.5 - 2451545
        let g = (357.529 + 0.98560028 * d) * rad, q = (280.459 + 0.98564736 * d) * rad
        let L = q + (1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let e = (23.439 - 0.00000036 * d) * rad
        let ra = atan2(cos(e) * sin(L), cos(L)), dec = asin(sin(e) * sin(L))
        let ha = ((18.697374558 + 24.06570982441908 * d).truncatingRemainder(dividingBy: 24) * 15 + lon) * rad - ra
        return asin(sin(lat * rad) * sin(dec) + cos(lat * rad) * cos(dec) * cos(ha)) / rad
    }

    // Sunrise and sunset are where the sun's centre is 0.833° below the horizon (refraction + disc),
    // the same as the website, so the times match Apple's Weather and Clock to the minute.
    static let h0 = -0.833

    /// SF Symbol for the sky right now: sun up, sun low on the horizon (rising or setting), or night.
    static func symbol(_ t: Date, lat: Double, lon: Double) -> (name: String, words: String) {
        let a = sunAlt(t, lat: lat, lon: lon)
        if a >= h0 { return ("sun.max.fill", "daytime") }
        if a >= -6 {
            let rising = sunAlt(t.addingTimeInterval(600), lat: lat, lon: lon) > a
            return rising ? ("sunrise.fill", "dawn") : ("sunset.fill", "dusk")
        }
        return ("moon.stars.fill", "night")
    }

    /// The next sunrise or sunset after t, found in 10-minute steps and bisected to the second.
    /// Nil when neither happens in the next 30 hours (midnight sun or polar night).
    static func nextEvent(_ t: Date, lat: Double, lon: Double) -> (rise: Bool, at: Date)? {
        var lo = t, prev = sunAlt(t, lat: lat, lon: lon)
        for i in 1...180 {
            let hi = t.addingTimeInterval(Double(i) * 600), a = sunAlt(hi, lat: lat, lon: lon)
            if (prev < h0) != (a < h0) {
                var l = lo, h = hi
                for _ in 0..<12 {
                    let m = l.addingTimeInterval(h.timeIntervalSince(l) / 2)
                    if (sunAlt(m, lat: lat, lon: lon) < h0) == (prev < h0) { l = m } else { h = m }
                }
                return (prev < h0, h)
            }
            lo = hi; prev = a
        }
        return nil
    }

    // Night, twilights, golden hour, day.
    private static let stops: [(Double, UInt32)] = [
        (-90, 0x232c47), (-18, 0x293455), (-12, 0x34416c), (-6, 0x4e4b7f), (-3, 0x86617d),
        (0, 0xc47b56), (2, 0xdc9b5d), (5, 0xecc07f), (10, 0xb9d9ed), (25, 0x8dc3e9), (90, 0x79b7e5),
    ]

    static func rgb(_ a: Double) -> [Double] {
        var i = 0
        while i < stops.count - 2 && a > stops[i + 1].0 { i += 1 }
        let f = max(0, min(1, (a - stops[i].0) / (stops[i + 1].0 - stops[i].0)))
        let c = { (h: UInt32) in [Double(h >> 16 & 255), Double(h >> 8 & 255), Double(h & 255)] }
        let A = c(stops[i].1), B = c(stops[i + 1].1)
        return (0..<3).map { (A[$0] + (B[$0] - A[$0]) * f).rounded() }
    }

    static func color(_ a: Double) -> Color {
        let c = rgb(a)
        return Color(red: c[0] / 255, green: c[1] / 255, blue: c[2] / 255)
    }

    // Ink from the background's real luminance; 0.179 is where white and black contrast equally.
    static func ink(_ a: Double) -> Color {
        let l = rgb(a).map { v -> Double in let s = v / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2] < 0.179 ? .white : .black
    }
}
