import SwiftUI

struct Panel: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let t = store.instant
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Time Zones").font(.headline)
                Spacer()
                if store.planning {
                    Button("Back to now") { store.offsetMin = 0 }.buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text("Live").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            let n = store.places.count
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: max(1, n == 4 ? 2 : min(3, n))), spacing: 6) {
                ForEach(store.places) { Tile(place: $0, at: t) }
            }

            if let o = store.overlap {
                let parts = o.split(separator: ":", maxSplits: 1).map(String.init)
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.086, green: 0.639, blue: 0.290)).frame(width: 3)
                    (Text(parts[0] + ":").bold() + Text(parts.count > 1 ? parts[1] : "")).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Slider(value: Binding(get: { store.offsetMin }, set: { store.offsetMin = ($0 / 15).rounded() * 15 }), in: -720...2160)
                Text(store.planning
                     ? "Planning \(store.formatter(TimeZone.current.identifier, "EEE").string(from: t)) \(store.clock(TimeZone.current.identifier, t)) your time"
                     : "Drag to plan a time")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if store.editing { editor }

            Divider()
            HStack {
                Button(store.editing ? "Done" : "Edit cities") { store.editing.toggle(); store.query = "" }
                Spacer()
                Picker("Clock", selection: $store.h24) { Text("12h").tag(false); Text("24h").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 92)
                Menu {
                    Toggle("Open at login", isOn: Binding(get: { store.launchAtLogin }, set: setLogin))
                    Button("Open the website") { store.openWebsite() }
                    Divider()
                    Button("Quit Time Zones") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            Text(store.note ?? "Click a city to show or hide it in the menu bar.")
                .font(.caption2).foregroundStyle(store.note == nil ? .secondary : .primary)
        }
        .padding(14)
        .frame(width: 372)
    }

    private func setLogin(_ on: Bool) {
        do {
            try store.setLaunchAtLogin(on)
            store.note = on ? "Time Zones will open when you log in." : nil
        } catch {
            store.note = "macOS needs your OK: System Settings > General > Login Items."
        }
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Add a city or country", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let p = Catalog.shared.search(store.query).first { store.add(p); store.query = "" } }
            let results = Catalog.shared.search(store.query)
            ForEach(Array(results.enumerated()), id: \.offset) { _, p in
                Button { store.add(p); store.query = "" } label: {
                    HStack {
                        Text(p.flag.isEmpty ? "🌐" : p.flag)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.name)
                            Text(p.cc.isEmpty ? p.zone : Catalog.shared.countryName(p.cc)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.gap(p, at: Date())).font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            List {
                ForEach($store.places) { $p in
                    HStack(spacing: 8) {
                        Text(p.flag.isEmpty ? "🌐" : p.flag)
                        Text(p.name).lineLimit(1)
                        TextField("Nickname", text: Binding(get: { p.label ?? "" }, set: { p.label = $0.isEmpty ? nil : String($0.prefix(24)) }))
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                        Spacer()
                        Button { p.pinned.toggle() } label: { Image(systemName: p.pinned ? "pin.fill" : "pin") }
                            .buttonStyle(.borderless).help(p.pinned ? "Hide from the menu bar" : "Show in the menu bar")
                        Button { store.remove(p) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).disabled(store.places.count == 1).help("Remove")
                    }
                }
                .onMove { store.places.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: CGFloat(min(store.places.count, 6)) * 32 + 8)
            Text("Drag a row to reorder. A nickname like “Mom” shows on the tile and in the menu bar.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Tile: View {
    @EnvironmentObject var store: Store
    let place: Place
    let at: Date

    var body: some View {
        let alt = place.lat.flatMap { la in place.lon.map { Sky.sunAlt(at, lat: la, lon: $0) } }
        let ink = alt.map(Sky.ink) ?? Color.primary
        let clock = store.time(place, at: at)
        let parts = clock.split(separator: " ").map(String.init)
        let sub = [store.gap(place, at: at), store.weekday(place, at: at)].compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(place.shown).lineLimit(1)
                Spacer(minLength: 0)
                if place.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
            }
            .font(.system(size: 11))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts[0]).font(.system(size: 21, weight: .bold)).monospacedDigit()
                if parts.count > 1 { Text(parts[1]).font(.system(size: 10, weight: .bold)) }
            }
            Text(sub).font(.system(size: 10.5)).lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alt.map(Sky.color) ?? Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(alt == nil ? 0.15 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { store.togglePin(place) }
        .help(place.pinned ? "\(place.name) is in the menu bar. Click to hide it." : "Click to show \(place.name) in the menu bar")
        .contextMenu {
            Button(place.pinned ? "Hide from menu bar" : "Show in menu bar") { store.togglePin(place) }
            Button("Remove \(place.shown)", role: .destructive) { store.remove(place) }.disabled(store.places.count == 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.shown), \(clock), \(sub)\(place.pinned ? ", in the menu bar" : "")")
    }
}
