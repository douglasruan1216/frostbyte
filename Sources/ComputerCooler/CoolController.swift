import AppKit
import Combine
import IOKit.pwr_mgt
import UniformTypeIdentifiers

/// One running app we can show / cool.
struct AppInfo: Identifiable {
    let bid: String
    let name: String
    let cpu: Double
    let managed: Bool
    let running: Bool
    var id: String { bid }
}

/// Watches the apps you've chosen to manage. When one is running but you've
/// clicked away for a while, it cools it down; when you come back it warms it up.
/// Also tracks every app's CPU for the menu-bar heat meter and total-CPU graph,
/// and can cap Roblox's frame rate.
@MainActor
final class CoolController: ObservableObject {
    static let shared = CoolController()
    static let robloxBundleID = "com.roblox.RobloxPlayer"

    // ── Pro / licensing ───────────────────────────────────────────────────
    /// EARLY ACCESS: while this is true every Pro feature is free, and each Mac
    /// that runs the app gets permanently stamped as an `earlyAdopter`.
    ///
    /// ⚠️ LAUNCH TODO: flip to `false` once the GitHub download counter passes
    /// 100, then cut a release. Everyone who already installed keeps Pro
    /// forever (their `earlyAdopter` stamp is already on disk) — only new
    /// installs see the lock. That promise is on the landing page, so never
    /// clear the stamp.
    static let freeLaunch = true
    /// Set once, on this Mac, the first time the app runs during early access.
    /// Survives the `freeLaunch` flip — that's the whole point.
    @Published private(set) var earlyAdopter = false
    /// Free tier can cool this many apps; Pro is unlimited.
    static let freeAppLimit = 1
    /// Set to your store product's permalink/id at launch to enable real
    /// online license verification (left empty until payment is set up).
    ///
    /// There is deliberately NO built-in owner/master key: this source is
    /// public, so any such string would be public too — and git history would
    /// keep it forever even after a delete. The `earlyAdopter` stamp above is
    /// how this Mac stays unlocked.
    private static let storeProductID = ""
    /// Your public Gumroad product page — where the in-app "Get Pro" button
    /// sends people. Empty until the store exists, and the button HIDES itself
    /// while it is, so it can never dead-end someone who wants to pay.
    /// ⚠️ LAUNCH TODO: fill this in at the same time as storeProductID.
    private static let storeURL = ""
    /// Only show a buy button once there's somewhere to buy.
    var canBuy: Bool { !Self.storeURL.isEmpty }
    func openStore() {
        guard let u = URL(string: Self.storeURL) else { return }
        NSWorkspace.shared.open(u)
    }

    /// Try to unlock Pro with a license key, verified online against the store
    /// (once storeProductID is set).
    func activateLicense(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        licenseError = nil
        guard !key.isEmpty else { licenseError = "Enter a license key."; return }
        guard !Self.storeProductID.isEmpty else {
            licenseError = "That key didn’t work — check for typos."; return
        }
        licenseChecking = true
        Task { await verifyWithGumroad(key) }
    }

    /// Verify a license key with Gumroad's API and unlock Pro on success.
    /// Docs: POST https://api.gumroad.com/v2/licenses/verify
    private func verifyWithGumroad(_ key: String) async {
        let enc = { (s: String) in
            s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
        }
        var req = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("product_id=\(enc(Self.storeProductID))&license_key=\(enc(key))&increment_uses_count=true".utf8)
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            var ok = (obj?["success"] as? Bool) ?? false
            // Reject refunded / charged-back purchases.
            if let p = obj?["purchase"] as? [String: Any] {
                if (p["refunded"] as? Bool) == true { ok = false }
                if (p["chargebacked"] as? Bool) == true { ok = false }
            }
            licenseChecking = false
            if ok { licenseKey = key; licensed = true; licenseError = nil }
            else  { licenseError = "That key didn’t work — check for typos." }
        } catch {
            licenseChecking = false
            licenseError = "Couldn’t reach the license server — check your internet."
        }
    }

    /// Drops a purchased licence, but never revokes an early-adopter's Pro.
    func deactivateLicense() { licensed = false; licenseKey = ""; licenseError = nil }

    // ── Free trial ────────────────────────────────────────────────────────
    /// Everything unlocked for this many days after the first launch. No card,
    /// no account, no signup — when it lapses the app simply settles into the
    /// free tier and keeps working. Nothing is ever charged: there is no
    /// payment code in this app and no server to hold a card on.
    static let trialDays = 7
    /// First-launch date, resolved from both markers in resolveTrialStart().
    private var trialStart: Date?

    /// The install date is written in TWO places and we always trust the
    /// EARLIER one, so clearing just one doesn't hand out a fresh trial.
    /// Re-downloading the app resets nothing by itself — neither marker lives
    /// inside the .app bundle.
    ///
    /// This is a speed bump, not a lock: the source is public, so anyone who
    /// wants to can bypass it. That's fine — see PUBLISHING.md. Don't add
    /// keychain checks or obfuscation on top; it would only make the app look
    /// sketchy to the honest majority, who are the only people paying.
    private var markerURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrostByte", isDirectory: true)
        return base.appendingPathComponent("install-date")
    }
    private func readMarkerFile() -> Date? {
        guard let s = try? String(contentsOf: markerURL, encoding: .utf8),
              let t = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: t)
    }
    private func writeMarkers(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "trialStart")
        try? FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? String(date.timeIntervalSince1970).write(to: markerURL, atomically: true, encoding: .utf8)
    }

    /// Resolve the install date from both markers, healing whichever is missing.
    private func resolveTrialStart() {
        let now = Date()
        var found: [Date] = []
        let stored = UserDefaults.standard.double(forKey: "trialStart")
        if stored > 0 { found.append(Date(timeIntervalSince1970: stored)) }
        if let f = readMarkerFile() { found.append(f) }
        // Earliest wins; a date in the future means a rolled-back clock, so
        // treat it as "now" rather than letting it extend the trial forever.
        var start = found.min() ?? now
        if start > now { start = now }
        trialStart = start
        writeMarkers(start)          // re-write both, healing a deleted one
        updateTrial()
    }
    /// Recomputed every tick so the trial lapses live, without a restart.
    private func updateTrial() {
        guard let start = trialStart else { return }
        let active = Date() < start.addingTimeInterval(Double(Self.trialDays) * 86_400)
        if trialActive != active { trialActive = active }
    }
    /// Whole days left, for the UI. 0 once it's over.
    var trialDaysLeft: Int {
        guard let start = trialStart else { return 0 }
        let end = start.addingTimeInterval(Double(Self.trialDays) * 86_400)
        return max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
    }

    /// Free tier may manage only `freeAppLimit` apps (already-managed ones and
    /// Pro users are always allowed).
    func canManageMore(bid: String) -> Bool {
        isPro || targets[bid] != nil || targets.count < Self.freeAppLimit
    }

    enum Mode: String, CaseIterable, Identifiable {
        case throttle = "Cool"
        case freeze   = "Deep Freeze"
        var id: String { rawValue }

        /// Fraction of time the app runs while cooled (nil = fully paused).
        /// Higher = less cooling but far less likely to disconnect online games.
        var runFraction: Double? {
            switch self {
            case .throttle: return 0.2    // runs a fifth — big heat cut
            case .freeze:   return nil    // fully paused
            }
        }

        var blurb: String {
            switch self {
            case .throttle:
                return "Throttles the app so it only runs a sliver of the time — cuts CPU and heat a lot but keeps it alive so it stays online. Comes back on its own when you click it. Tested safe for 8+ hours AFK."
            case .freeze:
                return "Fully pauses the app — CPU and GPU go to a true zero and the fan goes quiet. Cools the most, but online games may disconnect. Press Resume to come back."
            }
        }
    }

    // Duty cycle period — short so each pause is brief (network stays alive).
    private let dutyPeriod = 0.5

    /// Rough watts saved per 100% CPU-core we pause. It's deliberately a bit
    /// higher than pure CPU power because freezing also stops the GPU work that
    /// isn't captured by %CPU. This is clearly an ESTIMATE, labelled as such.
    private let wattsPerCPU100 = 8.0

    // ── Emergency Chill thresholds ────────────────────────────────────────
    // True CPU temperature isn't readable on Apple Silicon without sudo, so we
    // use sustained high CPU as a reliable "running hot / fan about to spin up"
    // proxy. When a managed app pins the CPU this hard for this long, we force a
    // short Cool pulse even if you're actively using it. emergencyCPU/Seconds are
    // user-tunable (below); the pulse length is fixed.
    private let emergencyHold = 45          // seconds to hold each cool pulse

    /// Built-in average residential electricity rates ($/kWh) so money works
    /// with no setup. Approximate 2024 figures, ~150 countries (searchable in
    /// the UI). "Other / Custom" keeps whatever rate is set.
    static let regionRates: [(name: String, rate: Double)] = [
        ("Custom…", 0.17),                // type your own rate (kept at the top)
        ("United States", 0.17),          // default
        ("Afghanistan", 0.04),
        ("Albania", 0.11),
        ("Algeria", 0.04),
        ("Angola", 0.03),
        ("Argentina", 0.06),
        ("Armenia", 0.12),
        ("Australia", 0.30),
        ("Austria", 0.28),
        ("Azerbaijan", 0.06),
        ("Bahamas", 0.30),
        ("Bahrain", 0.08),
        ("Bangladesh", 0.07),
        ("Barbados", 0.29),
        ("Belarus", 0.07),
        ("Belgium", 0.37),
        ("Belize", 0.21),
        ("Benin", 0.18),
        ("Bhutan", 0.03),
        ("Bolivia", 0.09),
        ("Bosnia and Herzegovina", 0.10),
        ("Botswana", 0.09),
        ("Brazil", 0.16),
        ("Brunei", 0.06),
        ("Bulgaria", 0.13),
        ("Burkina Faso", 0.20),
        ("Cambodia", 0.19),
        ("Cameroon", 0.13),
        ("Canada", 0.13),
        ("Chad", 0.20),
        ("Chile", 0.18),
        ("China", 0.08),
        ("Colombia", 0.15),
        ("Costa Rica", 0.16),
        ("Croatia", 0.16),
        ("Cuba", 0.05),
        ("Cyprus", 0.28),
        ("Czech Republic", 0.26),
        ("Denmark", 0.38),
        ("Dominican Republic", 0.16),
        ("Ecuador", 0.10),
        ("Egypt", 0.03),
        ("El Salvador", 0.17),
        ("Estonia", 0.20),
        ("Ethiopia", 0.01),
        ("Europe (avg)", 0.29),
        ("Fiji", 0.16),
        ("Finland", 0.24),
        ("France", 0.28),
        ("Gabon", 0.17),
        ("Georgia", 0.07),
        ("Germany", 0.40),
        ("Ghana", 0.06),
        ("Greece", 0.22),
        ("Guatemala", 0.24),
        ("Honduras", 0.15),
        ("Hong Kong", 0.16),
        ("Hungary", 0.11),
        ("Iceland", 0.14),
        ("India", 0.08),
        ("Indonesia", 0.10),
        ("Iran", 0.01),
        ("Iraq", 0.03),
        ("Ireland", 0.40),
        ("Israel", 0.16),
        ("Italy", 0.38),
        ("Ivory Coast", 0.12),
        ("Jamaica", 0.30),
        ("Japan", 0.22),
        ("Jordan", 0.11),
        ("Kazakhstan", 0.05),
        ("Kenya", 0.16),
        ("Kuwait", 0.03),
        ("Kyrgyzstan", 0.02),
        ("Laos", 0.08),
        ("Latvia", 0.19),
        ("Lebanon", 0.10),
        ("Lithuania", 0.20),
        ("Luxembourg", 0.35),
        ("Madagascar", 0.13),
        ("Malawi", 0.08),
        ("Malaysia", 0.10),
        ("Maldives", 0.18),
        ("Mali", 0.20),
        ("Malta", 0.14),
        ("Mauritius", 0.13),
        ("Mexico", 0.10),
        ("Moldova", 0.11),
        ("Mongolia", 0.06),
        ("Montenegro", 0.11),
        ("Morocco", 0.12),
        ("Mozambique", 0.08),
        ("Myanmar", 0.05),
        ("Namibia", 0.13),
        ("Nepal", 0.08),
        ("Netherlands", 0.35),
        ("New Zealand", 0.21),
        ("Nicaragua", 0.24),
        ("Niger", 0.19),
        ("Nigeria", 0.05),
        ("North Macedonia", 0.10),
        ("Norway", 0.14),
        ("Oman", 0.05),
        ("Pakistan", 0.06),
        ("Panama", 0.20),
        ("Papua New Guinea", 0.22),
        ("Paraguay", 0.06),
        ("Peru", 0.16),
        ("Philippines", 0.19),
        ("Poland", 0.20),
        ("Portugal", 0.25),
        ("Qatar", 0.03),
        ("Romania", 0.18),
        ("Russia", 0.06),
        ("Rwanda", 0.20),
        ("Saudi Arabia", 0.05),
        ("Senegal", 0.20),
        ("Serbia", 0.09),
        ("Singapore", 0.23),
        ("Slovakia", 0.20),
        ("Slovenia", 0.18),
        ("South Africa", 0.15),
        ("South Korea", 0.11),
        ("Spain", 0.24),
        ("Sri Lanka", 0.09),
        ("Sudan", 0.01),
        ("Sweden", 0.25),
        ("Switzerland", 0.25),
        ("Syria", 0.02),
        ("Taiwan", 0.09),
        ("Tajikistan", 0.02),
        ("Tanzania", 0.10),
        ("Thailand", 0.13),
        ("Togo", 0.18),
        ("Trinidad and Tobago", 0.05),
        ("Tunisia", 0.08),
        ("Turkey", 0.10),
        ("Turkmenistan", 0.01),
        ("Uganda", 0.19),
        ("Ukraine", 0.04),
        ("United Arab Emirates", 0.08),
        ("United Kingdom", 0.34),
        ("Uruguay", 0.22),
        ("Uzbekistan", 0.03),
        ("Venezuela", 0.01),
        ("Vietnam", 0.08),
        ("Yemen", 0.04),
        ("Zambia", 0.04),
        ("Zimbabwe", 0.10),
    ]

    // ── Settings (persisted) ──────────────────────────────────────────────
    @Published var enabled = true                  { didSet { save() } }
    @Published var mode: Mode = .throttle           { didSet { save(); if !isLoading { reapplyMode() } } }
    @Published var afkSeconds: Int = 30             { didSet { save() } }
    /// A verified paid licence. THIS is the part that persists — `isPro` must
    /// not, or the trial would be written to disk as a permanent unlock.
    @Published private(set) var licensed = false    { didSet { save() } }
    /// True while the free trial is still running (recomputed on each tick).
    @Published private(set) var trialActive = false
    /// Pro is unlocked if you were early, you bought it, or you're on trial.
    /// Deliberately computed, never stored.
    var isPro: Bool { earlyAdopter || licensed || trialActive }
    @Published var licenseKey = ""                  { didSet { save() } }
    /// Live UI state while checking a key online (not persisted).
    @Published var licenseChecking = false
    @Published var licenseError: String? = nil
    /// Emergency Chill: force a short Cool pulse when a managed game runs hot,
    /// even while you're actively playing (opt-in; off by default).
    @Published var emergencyChill = false           { didSet { save() } }
    /// Emergency Chill trigger: cool once a managed app holds ≥ this %CPU for
    /// this many seconds. Both user-tunable.
    @Published var emergencyCPU: Double = 200        { didSet { save() } }
    @Published var emergencySeconds: Int = 120       { didSet { save() } }
    /// bundleID → display name of apps we manage (cool).
    @Published var targets: [String: String] = [:]  { didSet { save() } }
    /// bundleID → display name of apps that should OPEN FrostByte when they start
    /// (and keep it open while any of them run). The external watcher polls these.
    @Published var launchApps: [String: String] = [:] { didSet { if !isLoading { save(); writeLaunchFile() } } }
    /// bundleID → executable/process name, so the shell watcher can pgrep them.
    private var launchExecs: [String: String] = [:]
    /// Roblox FPS cap (nil = unlimited). Mirrors the on-disk setting.
    @Published var fpsCap: Int? = nil
    /// Electricity rate + region for the money estimate.
    @Published var electricityRate = 0.17            { didSet { save() } }
    @Published var region = "United States"          { didSet { save() } }
    /// Phone control (local web server) on/off.
    @Published var webEnabled = false                { didSet { if !isLoading { save(); updateWeb() } } }
    /// Keep the Mac from idle-sleeping (so games stay connected when you step
    /// away / turn the screen off). Display can still turn off; you can still
    /// sleep manually from the Apple menu.
    @Published var keepAwake = true                  { didSet { if !isLoading { save(); updateKeepAwake() } } }

    // ── Live state ────────────────────────────────────────────────────────
    @Published var apps: [AppInfo] = []            // every running app + managed
    @Published var anyAppRunning = false
    @Published var anyTargetRunning = false
    @Published var anyLaunchRunning = false
    @Published var runningLaunchBids: Set<String> = []   // which launch apps are open right now
    @Published var isCoolingAny = false
    @Published var emergencyActive = false         // an Emergency-Chill pulse is running
    @Published var hottestCPU: Double = 0          // hottest single app, % of a core
    @Published var totalCPU: Double = 0            // sum across all apps
    @Published var coolingName: String? = nil
    @Published var statusLine = "Starting up…"
    @Published var cpuHistory: [Double] = []       // recent TOTAL-CPU samples

    // ── Savings tally (estimated) ─────────────────────────────────────────
    @Published var whSavedTotal = 0.0              // watt-hours, all time
    @Published var whSavedWeek = 0.0
    @Published var coolSecondsTotal = 0.0          // seconds spent cooling, all time
    @Published var coolSecondsWeek = 0.0

    private let webServer = WebServer()
    private var sleepAssertionID: IOPMAssertionID = 0
    private var timer: Timer?
    private var coolers: [pid_t: Cooler] = [:]
    private var cpuMap: [pid_t: Double] = [:]
    private var hotCPU: [pid_t: Double] = [:]      // last "hot" CPU before cooling
    private var hotStreak: [pid_t: Int] = [:]      // consecutive hot seconds (Emergency Chill)
    private var emergencyLeft: [pid_t: Int] = [:]  // seconds left in a forced cool pulse
    private var weekAnchor = Date()
    private var tickCount = 0
    private var statTick = 0
    private var idleSeconds = 0
    private var isLoading = false

    private init() {
        load()
        fpsCap = FPSCap.current()
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.2
        writeLaunchFile()   // keep the watcher's list in sync with saved prefs
        updateWeb()
        updateKeepAwake()
        tick()
    }

    // ── Heartbeat ─────────────────────────────────────────────────────────
    private func tick() {
        tickCount += 1
        if tickCount % 2 == 0 { cpuMap = readAllCPU() }   // refresh CPU ~every 2s
        if tickCount % 60 == 0 { updateTrial() }          // lapse the trial live

        let selfBID = Bundle.main.bundleIdentifier ?? ""
        let running = NSWorkspace.shared.runningApplications
        let frontBID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let livePids = Set(running.map(\.processIdentifier))

        var list: [AppInfo] = []
        var seen = Set<String>()
        var total = 0.0, hottest = 0.0
        var coolingAny = false, targetRunning = false, emergencyAny = false, launchRunning = false
        var runningLaunch = Set<String>()
        var coolName: String? = nil

        for app in running {
            guard let bid = app.bundleIdentifier, bid != selfBID, !app.isTerminated else { continue }
            let pid = app.processIdentifier
            let managed = targets[bid] != nil
            if launchApps[bid] != nil { launchRunning = true; runningLaunch.insert(bid) }
            let c = cpuMap[pid] ?? 0

            // Cooling management for apps we're told to manage.
            if managed {
                targetRunning = true
                let cooler = coolers[pid] ?? {
                    let n = Cooler(app: app, dutyPeriod: dutyPeriod)
                    coolers[pid] = n
                    return n
                }()
                let emLeft = emergencyLeft[pid] ?? 0
                if cooler.isCooling {
                    if emLeft > 0 {
                        // Emergency-forced cool pulse: holds even while the app is
                        // frontmost. Hand control back when the pulse ends & you're playing.
                        emergencyLeft[pid] = emLeft - 1
                        emergencyAny = true; coolingAny = true
                        if coolName == nil { coolName = targets[bid] }
                        accumulateSavings(savedCPU: max(0, (hotCPU[pid] ?? 0) - c))
                        if emLeft - 1 <= 0 && bid == frontBID { cooler.resume() }
                    } else if bid == frontBID {
                        cooler.resume(); cooler.awaySeconds = 0
                    } else {
                        coolingAny = true
                        if coolName == nil { coolName = targets[bid] }
                        // Baseline = the app's last hot CPU before it was cooled
                        // (hotCPU isn't updated while cooling, so it stays frozen
                        // at the pre-cool value). Works for manual OR auto cooling.
                        accumulateSavings(savedCPU: max(0, (hotCPU[pid] ?? 0) - c))
                    }
                } else {
                    hotCPU[pid] = c                      // remember its hot draw
                    // Emergency Chill: sustained high CPU → force a Cool pulse even
                    // while you're actively playing (opt-in heat/fan safety net).
                    if emergencyChill && c >= emergencyCPU {
                        hotStreak[pid, default: 0] += 1
                        if hotStreak[pid]! >= emergencySeconds {
                            cooler.cool(mode: .throttle)
                            emergencyLeft[pid] = emergencyHold
                            hotStreak[pid] = 0
                            emergencyAny = true; coolingAny = true
                            if coolName == nil { coolName = targets[bid] }
                        }
                    } else {
                        hotStreak[pid] = 0
                    }
                    if bid == frontBID {
                        cooler.awaySeconds = 0
                    } else if enabled {
                        cooler.awaySeconds += 1
                        if cooler.awaySeconds >= afkSeconds {
                            cooler.cool(mode: mode)
                            coolingAny = true
                            if coolName == nil { coolName = targets[bid] }
                        }
                    }
                }
            }

            // Display list: every regular (windowed) app, plus anything managed.
            if (app.activationPolicy == .regular || managed) && !seen.contains(bid) {
                seen.insert(bid)
                list.append(AppInfo(bid: bid, name: app.localizedName ?? bid,
                                    cpu: c, managed: managed, running: true))
                total += c
                if c > hottest { hottest = c }
            }
        }

        // Managed apps that aren't running (so they can still be un-ticked).
        for (bid, name) in targets where !seen.contains(bid) {
            list.append(AppInfo(bid: bid, name: name, cpu: 0, managed: true, running: false))
        }
        list.sort { a, b in
            a.managed != b.managed ? (a.managed && !b.managed) : a.cpu > b.cpu
        }

        // Drop coolers (and their trackers) whose process is gone.
        for (pid, _) in coolers where !livePids.contains(pid) {
            coolers.removeValue(forKey: pid)
            hotCPU.removeValue(forKey: pid)
            hotStreak.removeValue(forKey: pid)
            emergencyLeft.removeValue(forKey: pid)
        }

        apps = list
        anyAppRunning = list.contains { $0.running }
        anyTargetRunning = targetRunning
        anyLaunchRunning = launchRunning
        runningLaunchBids = runningLaunch
        isCoolingAny = coolingAny
        emergencyActive = emergencyAny
        coolingName = coolName
        hottestCPU = hottest
        totalCPU = total
        pushHistory(total)
        updateStatus()

        statTick += 1
        if statTick % 30 == 0 { saveStats() }   // persist tally every ~30s

        // Stay open while any selected launch app is running (or we're still
        // managing/cooling something); otherwise self-quit after 5 min idle.
        let keepAlive = launchRunning || targetRunning
        idleSeconds = keepAlive ? 0 : idleSeconds + 1
        if idleSeconds >= 300 { saveStats(); NSApp.terminate(nil) }
    }

    // ── Savings math (all estimated) ──────────────────────────────────────
    private func accumulateSavings(savedCPU: Double) {
        rollWeekIfNeeded()
        let wh = (savedCPU / 100.0 * wattsPerCPU100) / 3600.0   // one second's worth
        whSavedTotal += wh; whSavedWeek += wh
        coolSecondsTotal += 1; coolSecondsWeek += 1
    }

    private func rollWeekIfNeeded() {
        if Date().timeIntervalSince(weekAnchor) >= 7 * 24 * 3600 {
            whSavedWeek = 0; coolSecondsWeek = 0; weekAnchor = Date()
        }
    }

    func setEmergencyCPU(_ v: Double) { emergencyCPU = min(600, max(100, (v / 25).rounded() * 25)) }
    func setEmergencySeconds(_ v: Int) { emergencySeconds = min(600, max(30, v)) }

    func setRegion(_ name: String) {
        region = name
        // "Custom…" keeps whatever rate the user typed; any country sets its rate.
        if name != "Custom…",
           let r = Self.regionRates.first(where: { $0.name == name })?.rate {
            electricityRate = r
        }
    }

    /// Set a typed custom rate ($/kWh) and switch region to Custom (phone remote).
    func setCustomRate(_ v: Double) {
        electricityRate = min(5, max(0.01, v))
        region = "Custom…"
    }

    /// Persist stats now (called on quit).
    func flush() { saveStats() }

    private func updateStatus() {
        if emergencyActive {
            let n = coolingName ?? "App"
            statusLine = "🔥→❄️ \(n) ran hot — Emergency Chill cooling it."
        } else if isCoolingAny {
            let n = coolingName ?? "App"
            statusLine = mode == .freeze ? "❄️ \(n) frozen — true 0% CPU."
                                         : "💤 \(n) throttled & cooling."
        } else if !anyAppRunning {
            statusLine = "Nothing running."
        } else {
            statusLine = "\(heatWord.capitalized) — \(Int(totalCPU))% total CPU."
        }
    }

    // ── Manual actions ────────────────────────────────────────────────────
    func coolNow()   { for c in coolers.values { c.cool(mode: mode) }; isCoolingAny = true }
    func resumeAll() { for c in coolers.values { c.resume() }; isCoolingAny = false }
    /// Apply a mode change live to anything currently cooling.
    private func reapplyMode() { for c in coolers.values where c.isCooling { c.cool(mode: mode) } }
    func hardResumeAll() { for c in coolers.values { c.hardResume() } }

    /// Set a managed app on/off by bundle id — used by the phone remote, which
    /// only sends the bid. The display name is resolved from the live app list.
    func setManaged(bid: String, on: Bool) {
        let isManaged = targets[bid] != nil
        guard on != isManaged else { return }
        let name = apps.first(where: { $0.bid == bid })?.name ?? targets[bid] ?? bid
        toggleTarget(bid: bid, name: name)
    }

    func toggleTarget(bid: String, name: String) {
        if targets[bid] != nil {
            for (pid, c) in coolers where c.app.bundleIdentifier == bid {
                c.hardResume(); coolers.removeValue(forKey: pid)
            }
            targets.removeValue(forKey: bid)
        } else {
            guard canManageMore(bid: bid) else { return }   // free tier: 1 app
            targets[bid] = name
        }
    }

    // ── Launch-trigger apps (open FrostByte when they open) ────────────────
    /// Show a Finder picker to choose one or more .app bundles to add as triggers.
    func addLaunchAppFromPanel() {
        guard isPro else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose an app — FrostByte will open whenever it opens."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)   // bring the panel to the front (menu-bar app)
        if panel.runModal() == .OK {
            for url in panel.urls { addLaunchApp(url: url) }
        }
    }

    /// Add a launch trigger from a picked .app bundle (reads its id + process name).
    func addLaunchApp(url: URL) {
        guard isPro else { return }   // custom auto-launch is a Pro feature
        guard let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let exec = bundle.executableURL?.lastPathComponent
            ?? (bundle.infoDictionary?["CFBundleExecutable"] as? String)
        if let exec { launchExecs[bid] = exec }
        launchApps[bid] = name          // didSet writes prefs + the watcher file
    }

    /// Remove a launch trigger (used by the menu × and the phone remote).
    func removeLaunchApp(bid: String) {
        launchExecs.removeValue(forKey: bid)
        launchApps.removeValue(forKey: bid)
    }

    /// Path the shell watcher reads to know which process names launch FrostByte.
    private var launchFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("ComputerCooler/launch-apps.txt")
    }

    /// Write the executable names of the launch apps, one per line, for the watcher.
    private func writeLaunchFile() {
        let names = launchApps.keys.compactMap { launchExecs[$0] }
        let text = names.joined(separator: "\n") + (names.isEmpty ? "" : "\n")
        try? text.write(to: launchFileURL, atomically: true, encoding: .utf8)
    }

    // ── FPS cap ───────────────────────────────────────────────────────────
    func setFPSCap(_ fps: Int?) { if FPSCap.set(fps) { fpsCap = fps } }

    // ── Keep awake / display ──────────────────────────────────────────────
    private func updateKeepAwake() {
        if keepAwake && sleepAssertionID == 0 {
            var id: IOPMAssertionID = 0
            let ok = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "FrostByte keeping you online" as CFString, &id)
            if ok == kIOReturnSuccess { sleepAssertionID = id }
        } else if !keepAwake && sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
    }

    /// Turn the screen off now (Mac stays awake if keepAwake is on).
    func sleepDisplay() {
        let p = Process()
        p.launchPath = "/usr/bin/pmset"
        p.arguments  = ["displaysleepnow"]
        try? p.run()
    }

    // ── Phone control ─────────────────────────────────────────────────────
    private func updateWeb() { webEnabled ? webServer.start() : webServer.stop() }
    var webURL: String? {
        guard webEnabled, let ip = webServer.localIP else { return nil }
        return "http://\(ip):\(webServer.port)/"
    }

    // ── Heat helpers ──────────────────────────────────────────────────────
    var heatWord: String {
        switch hottestCPU {
        case ..<35: return "cool"
        case ..<80: return "warm"
        default:    return "hot"
        }
    }

    /// Menu-bar glyph: ❄️ cooling · 🌙 quiet · 🟢/🟡/🔥 by hottest app.
    var menuBarEmoji: String {
        if isCoolingAny { return "❄️" }
        switch hottestCPU {
        case ..<10: return "🌙"
        case ..<35: return "🟢"
        case ..<80: return "🟡"
        default:    return "🔥"
        }
    }

    private func pushHistory(_ v: Double) {
        cpuHistory.append(v)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
    }

    /// One `ps` call → CPU% for every process, keyed by pid.
    private func readAllCPU() -> [pid_t: Double] {
        let p = Process()
        p.launchPath = "/bin/ps"
        p.arguments  = ["-A", "-o", "pid=,%cpu="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = FileHandle.nullDevice
        do { try p.run() } catch { return cpuMap }
        p.waitUntilExit()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        var map: [pid_t: Double] = [:]
        if let s = String(data: out, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 2, let pid = pid_t(parts[0]), let c = Double(parts[1]) {
                    map[pid] = c
                }
            }
        }
        return map
    }

    // ── Persistence ───────────────────────────────────────────────────────
    private func save() {
        guard !isLoading else { return }
        let d = UserDefaults.standard
        d.set(enabled, forKey: "enabled")
        d.set(mode.rawValue, forKey: "mode")
        d.set(afkSeconds, forKey: "afkSeconds")
        d.set(licensed, forKey: "licensed")
        d.set(earlyAdopter, forKey: "earlyAdopter")
        d.set(licenseKey, forKey: "licenseKey")
        d.set(emergencyChill, forKey: "emergencyChill")
        d.set(emergencyCPU, forKey: "emergencyCPU")
        d.set(emergencySeconds, forKey: "emergencySeconds")
        d.set(targets, forKey: "targets")
        d.set(launchApps, forKey: "launchApps")
        d.set(launchExecs, forKey: "launchExecs")
        d.set(electricityRate, forKey: "electricityRate")
        d.set(region, forKey: "region")
        d.set(webEnabled, forKey: "webEnabled")
        d.set(keepAwake, forKey: "keepAwake")
    }
    private func saveStats() {
        let d = UserDefaults.standard
        d.set(whSavedTotal, forKey: "whSavedTotal")
        d.set(whSavedWeek, forKey: "whSavedWeek")
        d.set(coolSecondsTotal, forKey: "coolSecondsTotal")
        d.set(coolSecondsWeek, forKey: "coolSecondsWeek")
        d.set(weekAnchor.timeIntervalSince1970, forKey: "weekAnchor")
    }
    private func load() {
        isLoading = true
        let d = UserDefaults.standard
        if d.object(forKey: "enabled") != nil { enabled = d.bool(forKey: "enabled") }
        if let m = d.string(forKey: "mode"), let mv = Mode(rawValue: m) { mode = mv }
        let a = d.integer(forKey: "afkSeconds"); if a > 0 { afkSeconds = a }
        // "isPro" is the pre-trial key name — migrate it once.
        licensed = d.bool(forKey: "licensed") || d.bool(forKey: "isPro")
        licenseKey = d.string(forKey: "licenseKey") ?? ""
        // Early access: stamp this Mac once, then honour the stamp forever.
        earlyAdopter = d.bool(forKey: "earlyAdopter")
        if Self.freeLaunch && !earlyAdopter {
            earlyAdopter = true
            d.set(true, forKey: "earlyAdopter")
        }
        resolveTrialStart()   // needs earlyAdopter resolved first
        emergencyChill = d.bool(forKey: "emergencyChill")
        if d.object(forKey: "emergencyCPU") != nil { emergencyCPU = d.double(forKey: "emergencyCPU") }
        let es = d.integer(forKey: "emergencySeconds"); if es > 0 { emergencySeconds = es }
        if let t = d.dictionary(forKey: "targets") as? [String: String], !t.isEmpty {
            targets = t
        } else {
            targets = [Self.robloxBundleID: "Roblox"]   // manage Roblox by default
        }
        if let la = d.dictionary(forKey: "launchApps") as? [String: String] {
            launchApps = la                              // may be empty (user cleared it)
        } else {
            launchApps = [Self.robloxBundleID: "Roblox"] // open FrostByte for Roblox by default
        }
        if let le = d.dictionary(forKey: "launchExecs") as? [String: String] {
            launchExecs = le
        }
        if launchExecs[Self.robloxBundleID] == nil, launchApps[Self.robloxBundleID] != nil {
            launchExecs[Self.robloxBundleID] = "RobloxPlayer"
        }
        if d.object(forKey: "electricityRate") != nil { electricityRate = d.double(forKey: "electricityRate") }
        if let r = d.string(forKey: "region") { region = r }
        webEnabled = d.bool(forKey: "webEnabled")
        keepAwake = d.object(forKey: "keepAwake") != nil ? d.bool(forKey: "keepAwake") : true
        whSavedTotal = d.double(forKey: "whSavedTotal")
        whSavedWeek = d.double(forKey: "whSavedWeek")
        coolSecondsTotal = d.double(forKey: "coolSecondsTotal")
        coolSecondsWeek = d.double(forKey: "coolSecondsWeek")
        let anchor = d.double(forKey: "weekAnchor")
        if anchor > 0 { weekAnchor = Date(timeIntervalSince1970: anchor) }
        // Free tier can't keep Pro-only states enabled.
        if !isPro {
            if mode == .freeze { mode = .throttle }
            emergencyChill = false
        }
        isLoading = false
        save()
    }
}
