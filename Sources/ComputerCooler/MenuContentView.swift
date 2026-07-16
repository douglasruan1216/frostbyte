import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var cool: CoolController
    @State private var appsExpanded = true
    @State private var launchExpanded = false
    @State private var savingsExpanded = false
    @State private var regionSearch = ""
    @State private var licenseField = ""

    // Small "🔒 Pro" tag shown next to locked controls.
    @ViewBuilder private func proTag() -> some View {
        Text("🔒 Pro").font(.caption2.bold()).foregroundStyle(.orange)
    }

    private var afkText: String {
        cool.afkSeconds < 60 ? "\(cool.afkSeconds)s"
                             : String(format: "%.0f min", Double(cool.afkSeconds) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            heatMeter
            Divider()
            if cool.anyTargetRunning { actionButton }
            Divider()
            settings
            Divider()
            awaySection
            Divider()
            appsSection
            Divider()
            launchSection
            Divider()
            energySection
            Divider()
            fpsSection
            Divider()
            phoneSection
            Divider()
            proSection
            Divider()
            Button("Quit FrostByte") { NSApp.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(cool.menuBarEmoji).font(.title3)
            Text("FrostByte").font(.headline)
            Spacer()
        }
    }

    // ── Heat meter (total CPU + graph of all apps) ────────────────────────
    private var heatMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cool.statusLine)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("All apps").font(.caption.bold())
                Spacer()
                Text(String(format: "%.0f%% CPU", cool.totalCPU))
                    .font(.caption).monospacedDigit().foregroundStyle(heatColor)
            }
            Sparkline(data: cool.cpuHistory)
                .frame(height: 34).frame(maxWidth: .infinity)
        }
    }

    private var heatColor: Color {
        switch cool.hottestCPU {
        case ..<35: return .green
        case ..<80: return .yellow
        default:    return .orange
        }
    }

    private var actionButton: some View {
        Group {
            if cool.isCoolingAny {
                Button { cool.resumeAll() } label: {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large).keyboardShortcut(.defaultAction)
            } else {
                Button { cool.coolNow() } label: {
                    Label("Cool down now", systemImage: "snowflake").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto-cool when I go AFK", isOn: $cool.enabled).toggleStyle(.switch)
            if cool.isPro {
                Picker("Cooling", selection: $cool.mode) {
                    ForEach(CoolController.Mode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text(cool.mode.blurb).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Text("Cooling: Cool").font(.caption)
                    Spacer()
                    Text("Deep Freeze").font(.caption).foregroundStyle(.secondary)
                    proTag()
                }
            }
            Stepper(value: $cool.afkSeconds, in: 15...900, step: 15) {
                Text("Wait \(afkText) before cooling").font(.caption)
            }
            HStack {
                Toggle("Emergency Chill", isOn: $cool.emergencyChill)
                    .toggleStyle(.switch).disabled(!cool.isPro)
                if !cool.isPro { proTag() }
            }
            Text("Cools a managed game even while you’re playing if it runs hot for a while — trades a little smoothness for a quieter, cooler Mac.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if cool.emergencyChill && cool.isPro {
                Stepper(value: $cool.emergencyCPU, in: 100...600, step: 25) {
                    Text("Cool when above \(Int(cool.emergencyCPU))% CPU").font(.caption)
                }
                Stepper(value: $cool.emergencySeconds, in: 30...600, step: 30) {
                    Text("…held for \(emergencyTimeText)").font(.caption)
                }
            }
        }
    }

    private var emergencyTimeText: String {
        cool.emergencySeconds < 60 ? "\(cool.emergencySeconds)s"
                                   : String(format: "%.0f min", Double(cool.emergencySeconds) / 60)
    }

    // ── Cool these apps (each with live CPU%) ─────────────────────────────
    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            collapseHeader("COOL THESE APPS", $appsExpanded)
            if appsExpanded {
                if cool.apps.isEmpty {
                    Text("No apps found.").font(.caption2).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(cool.apps) { app in
                            HStack(spacing: 6) {
                                Toggle(isOn: Binding(
                                    get: { app.managed },
                                    set: { _ in cool.toggleTarget(bid: app.bid, name: app.name) }
                                )) {
                                    Text(app.name).font(.caption).lineLimit(1)
                                }
                                .toggleStyle(.checkbox)
                                Spacer(minLength: 4)
                                Text(app.running ? String(format: "%.0f%%", app.cpu) : "—")
                                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(cool.apps.count) * 22, 200))
                if cool.isPro {
                    Text("Tick any app to have it cooled while you’re away.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("Free: cool 1 app. Unlimited with").font(.caption2).foregroundStyle(.secondary)
                        proTag()
                    }
                }
            }
        }
    }

    // ── Open FrostByte for these apps (auto-launch triggers) ──────────────
    private var launchList: [(bid: String, name: String, running: Bool)] {
        cool.launchApps.map { (bid, name) in
            (bid: bid, name: name, running: cool.runningLaunchBids.contains(bid))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            collapseHeader("OPEN FROSTBYTE FOR THESE", $launchExpanded)
            if launchExpanded {
                if cool.launchApps.isEmpty {
                    Text("No apps yet — add one below.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(launchList, id: \.bid) { item in
                            HStack(spacing: 6) {
                                Text(item.name).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(item.running ? "open" : "—")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Button {
                                    cool.removeLaunchApp(bid: item.bid)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    Button {
                        cool.addLaunchAppFromPanel()
                    } label: {
                        Label("Add app…", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .disabled(!cool.isPro)
                    if !cool.isPro { proTag() }
                }
                Text(cool.isPro
                     ? "Pick any app in Finder. FrostByte opens when it opens, and stays open until all your picks close."
                     : "FrostByte still auto-opens for Roblox. Add your own apps with Pro.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── Energy / money saved (all estimated) ──────────────────────────────
    private var kWh: Double { cool.whSavedTotal / 1000 }
    private var kWhWeek: Double { cool.whSavedWeek / 1000 }

    private var energyText: String {
        cool.whSavedTotal < 1000 ? String(format: "%.2f Wh", cool.whSavedTotal)
                                 : String(format: "%.3f kWh", kWh)
    }
    private var hoursText: String {
        let h = cool.coolSecondsTotal / 3600
        return h < 1 ? String(format: "%.0f min", cool.coolSecondsTotal / 60)
                     : String(format: "%.1f h", h)
    }
    private var moneyText: String { String(format: "$%.4f", kWh * cool.electricityRate) }
    private var co2Text: String { String(format: "%.3f lb", kWh * 0.4 * 2.20462) }
    // "Enough to ___" reference under each saved amount.
    private var energyRef: String {
        let charges = kWh / 0.019            // ~19 Wh per phone charge
        if charges >= 1 { return "Enough to charge a phone \(Int(charges.rounded())) times 🔋" }
        let bulbHours = kWh * 100            // 10W LED bulb
        if bulbHours >= 1 { return "Enough to run an LED bulb for \(Int(bulbHours.rounded())) h 💡" }
        return ""
    }
    private var moneyRef: String {
        let robux = (kWh * cool.electricityRate) / 0.0125    // ~1.25¢ per Robux
        if robux >= 1 { return "Enough to buy \(Int(robux.rounded())) Robux 🎮" }
        return ""
    }
    private var co2Ref: String {
        let miles = (kWh * 0.4) / 0.404      // ~0.404 kg CO₂ per car-mile
        if miles >= 1 { return String(format: "Enough to skip %.1f mi of driving 🚗", miles) }
        let meters = miles * 1609.34
        if meters >= 1 { return "Enough to skip \(Int(meters.rounded())) m of driving 🚗" }
        return ""
    }

    @ViewBuilder private func refRow(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text).font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private func collapseHeader(_ title: String, _ expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Regions filtered by the search box (current region always kept so the
    // Picker never shows blank while you're typing).
    private var filteredRegions: [(name: String, rate: Double)] {
        let q = regionSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return CoolController.regionRates }
        return CoolController.regionRates.filter {
            $0.name.lowercased().contains(q) || $0.name == cool.region
        }
    }

    private func statRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack {
            Text(icon)
            Text(label).font(.caption)
            Spacer()
            Text(value).font(.caption.bold()).monospacedDigit()
        }
    }

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            collapseHeader("AMOUNTS SAVED (ESTIMATED)", $savingsExpanded)
            if savingsExpanded {
                statRow("⏱️", "Kept cool", hoursText)
                statRow("⚡️", "Saved Energy", energyText)
                refRow(energyRef)
                statRow("💰", "Saved Money", moneyText)
                refRow(moneyRef)
                statRow("🌱", "Saved CO₂", co2Text)
                refRow(co2Ref)
                Text(String(format: "This week: %.0f Wh · %.1f h",
                            cool.whSavedWeek, cool.coolSecondsWeek / 3600))
                    .font(.caption2).foregroundStyle(.secondary)
                TextField("Search region…", text: $regionSearch)
                    .textFieldStyle(.roundedBorder).font(.caption)
                HStack {
                    Picker("", selection: Binding(
                        get: { cool.region }, set: { cool.setRegion($0) }
                    )) {
                        ForEach(filteredRegions, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    Spacer()
                    Text(String(format: "$%.2f/kWh", cool.electricityRate))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                if cool.region == "Custom…" {
                    HStack {
                        Text("Your rate").font(.caption)
                        Spacer()
                        TextField("", value: $cool.electricityRate,
                                  format: .number.precision(.fractionLength(0...3)))
                            .frame(width: 64).multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                        Text("$/kWh").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("Find this on your power bill (US average is about $0.17).")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var awaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STEP AWAY").font(.caption2.bold()).foregroundStyle(.secondary)
            Toggle("Keep Mac awake (stay online)", isOn: $cool.keepAwake)
                .toggleStyle(.switch)
            Button {
                cool.sleepDisplay()
            } label: {
                Label("Turn off display", systemImage: "moon.fill").frame(maxWidth: .infinity)
            }
            Text(cool.keepAwake
                 ? "Screen off, Mac stays awake — games stay connected."
                 : "Mac may sleep on its own and disconnect online games.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PHONE CONTROL").font(.caption2.bold()).foregroundStyle(.secondary)
                if !cool.isPro { proTag() }
            }
            Toggle("Control from my phone (same Wi-Fi)", isOn: $cool.webEnabled)
                .toggleStyle(.switch).disabled(!cool.isPro)
            if cool.webEnabled && cool.isPro {
                if let url = cool.webURL {
                    Text("Open this in your phone's browser:")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(url)
                        .font(.caption).foregroundStyle(.blue)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Anyone on your Wi-Fi with this link can control it.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Couldn’t find your Wi-Fi address — are you online?")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // ── FrostByte Pro (unlock / licensing) ────────────────────────────────
    private var proSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FROSTBYTE PRO").font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(cool.isPro ? "Unlocked ✓" : "Locked 🔒")
                    .font(.caption2.bold())
                    .foregroundStyle(cool.isPro ? .green : .orange)
            }
            if cool.earlyAdopter {
                Text("Early access — every feature is unlocked, and it stays that way on this Mac forever. Thanks for being early! 💙")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if cool.trialActive && !cool.licensed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Free trial — \(cool.trialDaysLeft) day\(cool.trialDaysLeft == 1 ? "" : "s") left. Everything's unlocked.")
                        .font(.caption2.bold()).foregroundStyle(.orange)
                    Text("No card, no account — when it ends FrostByte just goes back to the free tier and keeps working. Nothing gets charged.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    licenseBox
                }
            } else if cool.isPro {
                Text("Thanks for going Pro! 💙 Every feature is unlocked.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Every install starts a trial, so "locked" always means the
                // trial has run out — say that instead of a generic pitch.
                Text("Your 7-day free trial has ended. FrostByte still cools one app for free, forever.")
                    .font(.caption2.bold()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pro brings back Emergency Chill, Deep Freeze, the phone remote, custom auto-launch, and cooling unlimited apps.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                licenseBox
            }
        }
    }

    /// Shared by the trial and locked states — both need a way to enter a key.
    /// The buy button comes first: someone without a key needs somewhere to go,
    /// and a bare "paste your key" box is a dead end if you've never bought one.
    @ViewBuilder private var licenseBox: some View {
        if cool.canBuy {
            Button { cool.openStore() } label: {
                Label("Get Pro — $4.99", systemImage: "cart.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            Text("Opens the store in your browser. You'll get a license key by email — paste it below.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            TextField("License key", text: $licenseField)
                .textFieldStyle(.roundedBorder).font(.caption)
            Button(cool.licenseChecking ? "Checking…" : "Unlock") {
                cool.activateLicense(licenseField)
            }
            .disabled(cool.licenseChecking)
        }
        if let err = cool.licenseError {
            Text(err).font(.caption2).foregroundStyle(.red)
        }
    }

    private var fpsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ROBLOX FPS CAP").font(.caption2.bold()).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { cool.fpsCap ?? 0 },
                set: { cool.setFPSCap($0 == 0 ? nil : $0) }
            )) {
                Text("Off").tag(0); Text("30").tag(30); Text("60").tag(60); Text("120").tag(120)
            }.pickerStyle(.segmented).labelsHidden()
            Text(cool.fpsCap == nil
                 ? "Unlimited — Roblox runs as hot as it can while playing."
                 : "Capped at \(cool.fpsCap!) FPS. Restart Roblox to apply. Cools active play.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Auto-scaling line chart of recent total-CPU samples.
struct Sparkline: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(100.0, data.max() ?? 100)
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06))
                if data.count > 1 {
                    let w = geo.size.width, h = geo.size.height
                    Path { p in
                        let step = w / CGFloat(data.count - 1)
                        for (i, v) in data.enumerated() {
                            let x = CGFloat(i) * step
                            let y = h - CGFloat(min(v, maxV) / maxV) * h
                            i == 0 ? p.move(to: .init(x: x, y: y)) : p.addLine(to: .init(x: x, y: y))
                        }
                    }
                    .stroke(LinearGradient(colors: [.green, .yellow, .orange],
                                           startPoint: .bottom, endPoint: .top),
                            style: .init(lineWidth: 1.8, lineJoin: .round))
                }
            }
        }
    }
}
