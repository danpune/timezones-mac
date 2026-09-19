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
