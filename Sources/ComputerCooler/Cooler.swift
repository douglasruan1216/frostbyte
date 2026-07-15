import AppKit

/// Cools one running game process. Owns its own throttle timer + generation
/// guard so a stale pause can never re-freeze the game after we resume it.
@MainActor
final class Cooler {
    let app: NSRunningApplication
    private(set) var isCooling = false
    var awaySeconds = 0

    private var dutyTimer: Timer?
    private var coolGen = 0
    private let dutyPeriod: Double

    var pid: pid_t { app.processIdentifier }

    init(app: NSRunningApplication, dutyPeriod: Double) {
        self.app = app
        self.dutyPeriod = dutyPeriod
    }

    /// Start cooling — or, if already cooling, switch to a different mode live.
    func cool(mode: CoolController.Mode) {
        if !isCooling { awaySeconds = 0; app.hide() }
        isCooling = true
        let pid = self.pid
        kill(pid, SIGCONT)   // ensure it's running before (re)applying a mode
        if let runFraction = mode.runFraction {
            startDutyCycle(pid: pid, runFraction: runFraction)   // throttle modes
        } else {
            // Deep Freeze — fully pause.
            coolGen &+= 1
            dutyTimer?.invalidate(); dutyTimer = nil
            let gen = coolGen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.coolGen == gen, self.isCooling else { return }
                kill(pid, SIGSTOP)
            }
        }
    }

    func resume() {
        stopDutyCycle()          // bumps coolGen → cancels any pending pause
        isCooling = false
        awaySeconds = 0
        let pid = self.pid
        kill(pid, SIGCONT)
        // Backup un-freeze in case a stray SIGSTOP landed first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { kill(pid, SIGCONT) }
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps])
    }

    /// Make absolutely sure the process is left running (used before we quit or
    /// stop managing it) — never leave a game frozen with no one to resume it.
    func hardResume() {
        stopDutyCycle()
        isCooling = false
        kill(pid, SIGCONT)
    }

    private func startDutyCycle(pid: pid_t, runFraction: Double) {
        dutyTimer?.invalidate()
        coolGen &+= 1
        let gen = coolGen
        let runSecs = dutyPeriod * runFraction
        let stopIfCurrent: () -> Void = { [weak self] in
            guard let self, self.coolGen == gen, self.isCooling else { return }
            kill(pid, SIGSTOP)
        }
        let t = Timer(timeInterval: dutyPeriod, repeats: true) { [weak self] _ in
            guard let self, self.coolGen == gen, self.isCooling else { return }
            kill(pid, SIGCONT)   // run briefly…
            DispatchQueue.main.asyncAfter(deadline: .now() + runSecs, execute: stopIfCurrent) // …then pause
        }
        RunLoop.main.add(t, forMode: .common)
        dutyTimer = t
        kill(pid, SIGCONT)
        DispatchQueue.main.asyncAfter(deadline: .now() + runSecs, execute: stopIfCurrent)
    }

    private func stopDutyCycle() {
        coolGen &+= 1
        dutyTimer?.invalidate()
        dutyTimer = nil
    }
}
