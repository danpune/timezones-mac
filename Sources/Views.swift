import SwiftUI

struct Panel: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let t = store.instant
        let home = TimeZone.current.identifier
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Time Zones").font(.headline)
                Spacer()
                if store.planning {
                    Button("Back to now") { store.planned = nil; store.timeText = "" }.buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text("Live").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if store.askLogin {
                HStack(spacing: 8) {
                    Text("Open Time Zones automatically when you log in?").font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Not now") { store.answerLogin(false) }.controlSize(.small)
                    Button("Yes") { store.answerLogin(true) }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // A table, one city per row: the times sit in one right-aligned column so they compare at a glance.
            VStack(spacing: 0) {
                ForEach(Array(store.places.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Divider().padding(.leading, 4) }
                    Row(place: p, at: t)
                }
            }

            search

            if let o = store.overlap {
                let good = !(store.shared?.runs.isEmpty ?? true)
                Button { store.planShared() } label: { note(o, good ? Color(red: 0.086, green: 0.639, blue: 0.290) : .orange) }
                    .buttonStyle(.plain).disabled(!good).help(good ? "Plan this time" : "")
            }
            if let c = store.clockNote { note(c, Color(red: 0.851, green: 0.467, blue: 0.024)) }

            // Plan a moment: pick a day, type a time ("3pm", "15:30") or drag the slider through the day.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    DatePicker("Day", selection: Binding(get: { t }, set: { store.setDay($0) }), displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field).fixedSize()
                    TextField(store.clock(home, t), text: $store.timeText)
                        .textFieldStyle(.roundedBorder).frame(width: 84)
                        .onSubmit { if !store.applyTyped() { store.note = "Try a time like 3pm, 9:30 am or 15:30." } }
                        .help("Type a time, like 3pm or 15:30, then press Return")
                    Spacer()
                    Button { store.copyTimes() } label: { Label("Copy times", systemImage: "doc.on.doc") }
                        .controlSize(.small).help("Copy every city's time, ready to paste into a message")
                }
                Slider(value: Binding(get: { store.minuteOfDay }, set: { store.setMinuteOfDay(Int(($0 / 15).rounded()) * 15) }), in: 0...1425)
                    .accessibilityLabel("Time of day, your time")
                    .accessibilityValue(store.clock(home, t))
                // Green where everyone is free: drag the slider into the green.
                GeometryReader { g in
                    let inset: CGFloat = 10, w = g.size.width - 2 * inset
                    ForEach(Array((store.shared?.runs ?? []).enumerated()), id: \.offset) { _, r in
                        Capsule().fill(Color(red: 0.086, green: 0.639, blue: 0.290).opacity(store.shared?.work == true ? 0.9 : 0.55))
                            .frame(width: max(3, w * CGFloat(r.1 - r.0) * 60 / 1425), height: 4)
                            .offset(x: inset + w * CGFloat(r.0 * 60) / 1425)
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
                Text(store.planning
                     ? "Planning \(store.formatter(home, "EEE, MMM d").string(from: t)) at \(store.clock(home, t)) your time" + (store.planDistance.map { " · " + $0 } ?? "")
                     : "Pick a day, type a time or drag to plan. ← → move 15 minutes, Esc returns to now.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if store.editing { editor }

            Divider()
            HStack(spacing: 8) {
                Button(store.editing ? "Done" : "Nicknames and pins") { store.editing.toggle() }
                Spacer()
                Picker("Clock", selection: $store.h24) { Text("12h").tag(false); Text("24h").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 86)
                Picker("Temperature", selection: $store.fahrenheit) { Text("°F").tag(true); Text("°C").tag(false) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 72)
                Menu {
                    Toggle("Open at login", isOn: Binding(get: { store.launchAtLogin }, set: setLogin))
                    Toggle("Open with ⌃⌥T from any app", isOn: $store.hotkeyOn)
                    Divider()
                    Button("Copy times") { store.copyTimes() }
                    Button("Copy a link to this on the website") { store.copyLink() }
                    Button("Open the website") { store.openWebsite() }
                    Divider()
                    Button("Weather data: Open-Meteo.com") { if let u = URL(string: "https://open-meteo.com/") { NSWorkspace.shared.open(u) } }
                    Button("Quit Time Zones") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if let n = store.note ?? (store.askLogin ? "Drag a city to reorder. Click it to show or hide it in the menu bar. ⌃⌥T opens this from anywhere." : nil) {
                Text(n).font(.caption2).foregroundStyle(store.note == nil ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 430)
    }

    /// A note with a coloured edge and a bold label before the first colon, as on the website.
    private func note(_ s: String, _ edge: Color) -> some View {
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(edge).frame(width: 3)
            (Text(parts[0] + ":").bold() + Text(parts.count > 1 ? parts[1] : "")).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            try store.setLaunchAtLogin(on)
            store.note = on ? "Time Zones will open when you log in." : nil
        } catch {
            store.note = "macOS needs your OK: System Settings > General > Login Items."
        }
    }

    // Always visible: type a city, a country ("Thailand" gives Bangkok) or a zone word ("PST", "IST").
    @ViewBuilder private var search: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Add a city, country or time zone", text: $store.query)
                    .textFieldStyle(.plain)
                    .onSubmit { if let p = Catalog.shared.search(store.query).first { store.add(p) } }
                    .onExitCommand { if store.query.isEmpty { HotKey.togglePanel() } else { store.query = "" } }
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Clear")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            let results = Catalog.shared.search(store.query)
            if !store.query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                Text("No match. Try a city, a country, or a zone like PST.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(results.enumerated()), id: \.offset) { _, p in
                let have = store.places.contains { $0.zone == p.zone && $0.name == p.name }
                Button { store.add(p) } label: {
                    HStack(spacing: 8) {
                        Text(p.flag.isEmpty ? "🌐" : p.flag)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.name)
                            Text(p.cc.isEmpty ? p.zone : Catalog.shared.countryName(p.cc)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.time(p, at: store.instant) + " · " + store.gap(p, at: store.instant)).font(.caption).foregroundStyle(.secondary)
                        Image(systemName: have ? "checkmark" : "plus.circle").foregroundStyle(have ? Color.secondary : Color.accentColor)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(have)
                .help(have ? "Already in your list" : "Add \(p.name)")
            }
        }
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Text("A nickname like “Mom” shows in the list and in the menu bar.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Row: View {
    @EnvironmentObject var store: Store
    let place: Place
    let at: Date

    var body: some View {
        let alt = place.lat.flatMap { la in place.lon.map { Sky.sunAlt(at, lat: la, lon: $0) } }
        let clock = store.time(place, at: at)
        let parts = clock.split(separator: " ").map(String.init)
        let sky = place.lat.flatMap { la in place.lon.map { Sky.symbol(at, lat: la, lon: $0) } }
        let sun = store.sunText(place, at: at)
        let weather = store.wx(place, at: at)
        let sub = [store.gap(place, at: at), store.weekday(place, at: at), sun].compactMap { $0 }.joined(separator: " · ")
        let dragging = store.dragID == place.id
        HStack(spacing: 10) {
            Text(place.flag.isEmpty ? "🌐" : place.flag).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(place.shown).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if place.pinned || store.hoverID == place.id {
                        Image(systemName: place.pinned ? "pin.fill" : "pin").font(.system(size: 9)).foregroundStyle(.secondary).opacity(place.pinned ? 1 : 0.5)
                    }
                }
                // The next sunrise or sunset as its own symbol plus the time, so "tomorrow" still fits.
                (Text([store.gap(place, at: at), store.weekday(place, at: at)].compactMap { $0 }.joined(separator: " · "))
                 + (store.sunEvent(place, at: at).map { e in
                        Text(" · ") + Text(Image(systemName: e.rise ? "sunrise" : "sunset")) + Text(" " + e.time)
                    } ?? store.sunText(place, at: at).map { Text(" · " + $0) } ?? Text("")))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if store.hoverID == place.id && !dragging && store.places.count > 1 {
                Button { store.remove(place) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove \(place.shown)")
            }
            // Weather in its own column, so temperatures line up like the times.
            HStack(spacing: 3) {
                if let w = weather {
                    Image(systemName: w.symbol).symbolRenderingMode(.hierarchical).font(.system(size: 13))
                    Text("\(w.temp)°").font(.system(size: 13, weight: .medium)).monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 54, alignment: .trailing)
            .help(weather.map { $0.words.capitalized } ?? "")
            // Right-aligned with fixed-width digits and a fixed AM/PM slot, so every colon lines up.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let sky { Image(systemName: sky.name).font(.system(size: 12, weight: .semibold)).symbolRenderingMode(.hierarchical) }
                Text(parts[0]).font(.system(size: 20, weight: .bold)).monospacedDigit()
                if parts.count > 1 { Text(parts[1]).font(.system(size: 10, weight: .bold)).frame(width: 20, alignment: .leading) }
            }
            .foregroundStyle(alt.map(Sky.ink) ?? Color.primary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .frame(minWidth: store.h24 ? 94 : 122, alignment: .trailing)
            .background(alt.map(Sky.color) ?? Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .help(store.dayText(place, at: at) ?? "")
        }
        .frame(height: Store.rowHeight)
        .padding(.horizontal, 4)
        .background {
            if dragging {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            } else if store.hoverID == place.id {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
            }
        }
        .offset(y: dragging ? store.dragOffset : 0)
        .zIndex(dragging ? 1 : 0)
        .contentShape(Rectangle())
        // Global space: the row itself moves while dragging, so a local translation would jump.
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { store.drag(place.id, by: $0.translation.height) }
            .onEnded { _ in store.endDrag() })
        .onTapGesture { store.togglePin(place) }
        .onHover { inside in
            if inside { store.hoverID = place.id } else if store.hoverID == place.id { store.hoverID = nil }
        }
        .help("Drag to reorder. Click to \(place.pinned ? "hide it from" : "show it in") the menu bar.")
        .contextMenu {
            Button(place.pinned ? "Hide from menu bar" : "Show in menu bar") { store.togglePin(place) }
            Button("Move up") { store.move(place, by: -1) }.disabled(store.places.first?.id == place.id)
            Button("Move down") { store.move(place, by: 1) }.disabled(store.places.last?.id == place.id)
            Divider()
            Button("Remove \(place.shown)", role: .destructive) { store.remove(place) }.disabled(store.places.count == 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.shown), \(clock)\(sky.map { ", " + $0.words } ?? "")\(weather.map { ", \($0.temp) degrees, \($0.words)" } ?? ""), \(sub)\(place.pinned ? ", in the menu bar" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(place.pinned ? "Hides it from the menu bar" : "Shows it in the menu bar")
        .accessibilityAction { store.togglePin(place) }
        .accessibilityAction(named: "Move up") { store.move(place, by: -1) }
        .accessibilityAction(named: "Move down") { store.move(place, by: 1) }
        .accessibilityAction(named: "Remove") { store.remove(place) }
    }
}
