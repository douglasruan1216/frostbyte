import Foundation
import Network
import Darwin

/// A tiny HTTP server so you can run the WHOLE app from your phone's browser on
/// the same Wi-Fi — same controls as the menu bar: auto-cool, mode, AFK wait,
/// keep-awake / display off, per-app cooling, FPS cap, region, and the savings
/// readout. Serves one mobile page + a JSON API. A 4-digit PIN gates the API so
/// a random person on the network can't drive your Mac.
@MainActor
final class WebServer {
    let port: UInt16 = 8900
    private var listener: NWListener?

    var isRunning: Bool { listener != nil }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { conn in
                MainActor.assumeIsolated { self.accept(conn) }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            NSLog("FrostByte web server failed: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // ── Connection handling (all on the main queue) ───────────────────────
    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, isComplete, error in
            MainActor.assumeIsolated {
                var buf = buffer
                if let data { buf.append(data) }
                if buf.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.send(conn, self.respond(to: buf))
                } else if isComplete || error != nil {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: buf)
                }
            }
        }
    }

    private func send(_ conn: NWConnection, _ data: Data) {
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    // ── Routing ───────────────────────────────────────────────────────────
    private func respond(to raw: Data) -> Data {
        guard let text = String(data: raw, encoding: .utf8),
              let line = text.split(separator: "\r\n").first else {
            return http("400 Bad Request", "bad", "text/plain")
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return http("400 Bad Request", "bad", "text/plain") }
        let (path, query) = splitTarget(String(parts[1]))
        let cool = CoolController.shared

        switch path {
        case "/":
            return http("200 OK", Self.page, "text/html")
        case "/status", "/coolnow", "/resume", "/setmode", "/enabled", "/emergency",
             "/emergencycpu", "/emergencysecs",
             "/afk", "/keepawake", "/display", "/fps", "/region", "/rate", "/target", "/launch":
            apply(path: path, query: query, cool: cool)
            return json(statusDict(), "200 OK")
        default:
            return http("404 Not Found", "not found", "text/plain")
        }
    }

    /// Perform the action for a control route (mutating the shared controller).
    private func apply(path: String, query: [String: String], cool: CoolController) {
        func flag(_ k: String) -> Bool { query[k] == "1" || query[k] == "true" }
        switch path {
        case "/coolnow":   cool.coolNow()
        case "/resume":    cool.resumeAll()
        case "/setmode":
            if query["m"] == "freeze"    { if cool.isPro { cool.mode = .freeze } }
            else if query["m"] == "cool" { cool.mode = .throttle }
        case "/enabled":   cool.enabled = flag("v")
        case "/emergency": if cool.isPro { cool.emergencyChill = flag("v") }
        case "/emergencycpu":  if let v = Double(query["v"] ?? "") { cool.setEmergencyCPU(v) }
        case "/emergencysecs": if let v = Int(query["v"] ?? "") { cool.setEmergencySeconds(v) }
        case "/afk":
            if let n = Int(query["v"] ?? "") { cool.afkSeconds = min(900, max(15, n)) }
        case "/keepawake": cool.keepAwake = flag("v")
        case "/display":   cool.sleepDisplay()
        case "/fps":
            let v = Int(query["v"] ?? "0") ?? 0
            cool.setFPSCap([30, 60, 120].contains(v) ? v : nil)
        case "/region":
            if let r = query["v"] { cool.setRegion(r) }
        case "/rate":
            if let v = Double(query["v"] ?? "") { cool.setCustomRate(v) }
        case "/target":
            if let bid = query["bid"] { cool.setManaged(bid: bid, on: flag("v")) }
        case "/launch":   // phone can only remove; adding needs the Mac's Finder
            if let bid = query["bid"] { cool.removeLaunchApp(bid: bid) }
        default: break   // "/status" — just report
        }
    }

    /// Everything the menu shows, so the phone can render the whole app.
    private func statusDict() -> [String: Any] {
        let c = CoolController.shared
        func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
        let appsArr: [[String: Any]] = c.apps.map {
            ["bid": $0.bid, "name": $0.name, "cpu": Int($0.cpu.rounded()),
             "managed": $0.managed, "running": $0.running]
        }
        let launchArr: [[String: Any]] = c.launchApps.map {
            ["bid": $0.key, "name": $0.value, "running": c.runningLaunchBids.contains($0.key)]
        }.sorted { ($0["name"] as! String).localizedCaseInsensitiveCompare($1["name"] as! String) == .orderedAscending }
        let regionsArr: [[String: Any]] = CoolController.regionRates.map {
            ["name": $0.name, "rate": $0.rate]
        }
        return [
            "status": c.statusLine,
            "cooling": c.isCoolingAny,
            "running": c.anyTargetRunning,
            "mode": c.mode.rawValue,
            "pro": c.isPro,
            "enabled": c.enabled,
            "emergencyChill": c.emergencyChill,
            "emergency": c.emergencyActive,
            "emergencyCPU": Int(c.emergencyCPU),
            "emergencySeconds": c.emergencySeconds,
            "afkSeconds": c.afkSeconds,
            "keepAwake": c.keepAwake,
            "fps": c.fpsCap ?? 0,
            "region": c.region,
            "rate": r2(c.electricityRate),
            "totalCPU": Int(c.totalCPU.rounded()),
            "hottestCPU": Int(c.hottestCPU.rounded()),
            "whTotal": r2(c.whSavedTotal),
            "whWeek": r2(c.whSavedWeek),
            "coolSecTotal": Int(c.coolSecondsTotal),
            "coolSecWeek": Int(c.coolSecondsWeek),
            "history": c.cpuHistory.map { Int($0.rounded()) },
            "apps": appsArr,
            "launchApps": launchArr,
            "regions": regionsArr,
        ]
    }

    // ── HTTP helpers ──────────────────────────────────────────────────────
    private func http(_ status: String, _ body: String, _ type: String) -> Data {
        let bodyData = Data(body.utf8)
        var out = Data("""
        HTTP/1.1 \(status)\r
        Content-Type: \(type); charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """.utf8)
        out.append(bodyData)
        return out
    }

    private func json(_ dict: [String: Any], _ status: String) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return http(status, body, "application/json")
    }

    private func splitTarget(_ target: String) -> (String, [String: String]) {
        func decode(_ s: Substring) -> String {
            String(s).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(s)
        }
        let comps = target.split(separator: "?", maxSplits: 1)
        let path = String(comps.first ?? "")
        var query: [String: String] = [:]
        if comps.count > 1 {
            for pair in comps[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { query[String(kv[0])] = decode(kv[1]) }
            }
        }
        return (path, query)
    }

    /// The Mac's LAN IP (prefer en0, then en1) so we can show a URL for the phone.
    var localIP: String? {
        var found: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                found[String(cString: ptr.pointee.ifa_name)] = String(cString: host)
            }
        }
        return found["en0"] ?? found["en1"] ?? found.values.first
    }

    // ── The mobile page (fully static; PIN comes from the URL) ────────────
    // Mirrors every section of the menu-bar app. All state comes from /status.
    static let page = """
    <!doctype html><html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <meta name="theme-color" content="#0b1020">
    <title>FrostByte</title>
    <style>
      *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
      body{margin:0;font-family:-apple-system,system-ui,sans-serif;background:#0b1020;color:#eef;
           min-height:100vh;padding:18px;display:flex;flex-direction:column;gap:14px}
      h1{font-size:22px;margin:0}
      .card{background:#182036;border-radius:16px;padding:16px}
      .lbl{font-size:11px;letter-spacing:.5px;font-weight:700;color:#7a86a8;margin:0 0 8px}
      .chd{cursor:pointer;display:flex;justify-content:space-between;align-items:center}
      .chd .chev{color:#7a86a8;font-size:13px}
      .big{font-size:18px;font-weight:600;margin:0 0 8px}
      .row{display:flex;justify-content:space-between;font-size:14px;color:#aab;padding:3px 0}
      .row b{color:#eef;font-variant-numeric:tabular-nums}
      .cmp{font-size:12px;color:#889;text-align:right;margin:2px 0 6px}
      svg{width:100%;height:36px;display:block;background:rgba(255,255,255,.05);border-radius:8px}
      button{border:0;font-family:inherit;font-weight:600;color:#fff}
      .toggle{width:100%;border-radius:14px;padding:15px;font-size:16px;background:#334155;margin-top:2px}
      .toggle.on{background:#16a34a}
      .segs{display:flex;gap:8px}
      .seg{flex:1;border-radius:12px;padding:14px 6px;font-size:15px;background:#26304d;color:#cdd}
      .seg.active{background:#2563eb;color:#fff}
      .blurb{font-size:12px;color:#889;margin:8px 0 0}
      .act{width:100%;border-radius:14px;padding:17px;font-size:18px;margin-top:4px}
      .cool{background:#2563eb}.resume{background:#0891b2}.display{background:#475569}
      .stepper{display:flex;align-items:center;gap:12px;justify-content:space-between}
      .stepper button{width:52px;height:44px;border-radius:12px;font-size:22px;background:#26304d}
      .stepper .v{flex:1;text-align:center;font-size:17px;font-weight:600}
      .approw{display:flex;align-items:center;gap:10px;padding:11px 4px;border-bottom:1px solid #222a44}
      .approw:last-child{border-bottom:0}
      .chk{width:22px;height:22px;border-radius:6px;border:2px solid #445;display:flex;
           align-items:center;justify-content:center;font-size:14px;color:#fff;flex:0 0 auto}
      .chk.on{background:#16a34a;border-color:#16a34a}
      .an{flex:1;font-size:15px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .ac{font-size:13px;color:#9aa;font-variant-numeric:tabular-nums}
      .rm{font-size:16px;color:#e06;padding:2px 6px;margin-left:4px;cursor:pointer}
      .mut{font-size:13px;color:#778;padding:6px 0}
      select,input.search{width:100%;margin-top:8px;padding:12px;border-radius:12px;background:#26304d;color:#eef;
             border:0;font-size:15px;font-family:inherit}
      input.search::placeholder{color:#7a86a8}
      small{color:#889}
      .dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px}
    </style></head><body>
      <h1>🧊 FrostByte</h1>
      <div id="proNote" style="display:none;color:#f59e0b;font-size:13px;margin:-6px 0 0">🔒 Some features are Pro — unlock in the Mac app.</div>

      <div class="card">
        <div class="big" id="st">Connecting…</div>
        <div class="row"><span>All apps CPU</span><b id="cpu">–</b></div>
        <div class="row"><span>Hottest app</span><b id="hot">–</b></div>
        <svg id="spark" viewBox="0 0 100 34" preserveAspectRatio="none"></svg>
      </div>

      <div class="card">
        <button class="toggle" id="tgAuto" onclick="post('/enabled?v='+(S.enabled?0:1))">Auto-cool</button>
        <button class="toggle" id="tgEmg" onclick="post('/emergency?v='+(S.emergencyChill?0:1))" style="margin-top:10px">Emergency Chill</button>
        <div class="blurb">Cools a managed game even while you're playing if it runs hot for a while.</div>
        <div id="emgOpts" style="display:none">
          <div class="lbl" style="margin:14px 0 6px">COOL WHEN ABOVE</div>
          <div class="stepper">
            <button onclick="stepEmgCpu(-25)">−</button>
            <div class="v" id="emgCpuVal">–</div>
            <button onclick="stepEmgCpu(25)">+</button>
          </div>
          <div class="lbl" style="margin:14px 0 6px">HELD FOR</div>
          <div class="stepper">
            <button onclick="stepEmgSecs(-30)">−</button>
            <div class="v" id="emgSecsVal">–</div>
            <button onclick="stepEmgSecs(30)">+</button>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="lbl">COOLING MODE</div>
        <div class="segs">
          <button class="seg" id="mCool"   onclick="post('/setmode?m=cool')">💤 Cool</button>
          <button class="seg" id="mFreeze" onclick="post('/setmode?m=freeze')">❄️ Deep Freeze</button>
        </div>
        <div class="blurb" id="modeBlurb"></div>
      </div>

      <div class="card">
        <div class="lbl">WAIT BEFORE COOLING</div>
        <div class="stepper">
          <button onclick="stepAfk(-15)">−</button>
          <div class="v" id="afkVal">–</div>
          <button onclick="stepAfk(15)">+</button>
        </div>
      </div>

      <div class="card">
        <button class="act cool"   id="coolBtn"   onclick="post('/coolnow')">❄️ Cool down now</button>
        <button class="act resume" id="resumeBtn" onclick="post('/resume')" style="display:none">▶️ Resume</button>
      </div>

      <div class="card">
        <div class="lbl">STEP AWAY</div>
        <button class="toggle" id="tgAwake" onclick="post('/keepawake?v='+(S.keepAwake?0:1))">Keep Mac awake</button>
        <button class="act display" onclick="post('/display')" style="margin-top:10px">🌙 Turn off display</button>
      </div>

      <div class="card">
        <div class="lbl chd" onclick="toggleSec('appsBody','appsChev')">COOL THESE APPS<span class="chev" id="appsChev">▾</span></div>
        <div id="appsBody">
          <div id="apps"></div>
          <div class="mut">Tap any app to cool it while you're away.</div>
        </div>
      </div>

      <div class="card">
        <div class="lbl chd" onclick="toggleSec('launchBody','launchChev')">OPEN FROSTBYTE FOR THESE<span class="chev" id="launchChev">▸</span></div>
        <div id="launchBody" style="display:none">
          <div id="launchApps"></div>
          <div class="mut">FrostByte opens when any of these opens, and stays open until they all close. Add apps from the Mac (Finder); tap ✕ to remove.</div>
        </div>
      </div>

      <div class="card">
        <div class="lbl chd" onclick="toggleSec('savBody','savChev')">AMOUNTS SAVED (ESTIMATED)<span class="chev" id="savChev">▸</span></div>
        <div id="savBody" style="display:none">
          <div class="row"><span>⏱️ Kept cool</span><b id="hrs">–</b></div>
          <div class="row"><span>⚡️ Saved Energy</span><b id="en">–</b></div>
          <div class="cmp" id="enRef"></div>
          <div class="row"><span>💰 Saved Money</span><b id="mon">–</b></div>
          <div class="cmp" id="monRef"></div>
          <div class="row"><span>🌱 Saved CO₂</span><b id="co2">–</b></div>
          <div class="cmp" id="co2Ref"></div>
          <div class="cmp" id="wk"></div>
          <input class="search" id="regionSearch" placeholder="Search region…" oninput="filterRegions()">
          <select id="region" onchange="post('/region?v='+encodeURIComponent(this.value))"></select>
          <input class="search" id="customRate" inputmode="decimal" placeholder="Your rate, $ per kWh"
                 style="display:none" onchange="post('/rate?v='+encodeURIComponent(this.value))">
          <div class="cmp" id="rate"></div>
        </div>
      </div>

      <div class="card">
        <div class="lbl">ROBLOX FPS CAP</div>
        <div class="segs">
          <button class="seg" id="fps0"   onclick="post('/fps?v=0')">Off</button>
          <button class="seg" id="fps30"  onclick="post('/fps?v=30')">30</button>
          <button class="seg" id="fps60"  onclick="post('/fps?v=60')">60</button>
          <button class="seg" id="fps120" onclick="post('/fps?v=120')">120</button>
        </div>
        <div class="blurb">Restart Roblox to apply. Cools active play.</div>
      </div>

      <small id="err"></small>

    <script>
      var S = {}, allRegions = [];
      function el(i){ return document.getElementById(i); }
      function escHtml(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

      function toggleSec(bodyId, chevId){
        var b = el(bodyId), open = b.style.display !== 'none';
        b.style.display = open ? 'none' : 'block';
        el(chevId).textContent = open ? '▸' : '▾';
      }

      function req(p){
        return fetch(p, { method: p === '/status' ? 'GET' : 'POST' })
          .then(function(r){ return r.json(); }).then(render)
          .catch(function(){ el('err').textContent = 'Can’t reach your Mac.'; });
      }
      function post(p){ return req(p); }
      function get(){ return req('/status'); }
      function stepAfk(d){ var n = Math.min(900, Math.max(15, (S.afkSeconds||30) + d)); post('/afk?v=' + n); }
      function stepEmgCpu(d){ var n = Math.min(600, Math.max(100, (S.emergencyCPU||200) + d)); post('/emergencycpu?v=' + n); }
      function stepEmgSecs(d){ var n = Math.min(600, Math.max(30, (S.emergencySeconds||120) + d)); post('/emergencysecs?v=' + n); }
      function toggleApp(bid, v){ post('/target?bid=' + encodeURIComponent(bid) + '&v=' + v); }
      function removeLaunch(bid){ post('/launch?bid=' + encodeURIComponent(bid)); }

      function setToggle(id, on, label){ var e = el(id); e.textContent = label + ': ' + (on?'On':'Off'); e.className = 'toggle' + (on?' on':''); }

      function energyRef(k){
        var c = k / 0.019; if (c >= 1) return 'Enough to charge a phone ' + Math.round(c) + ' times 🔋';
        var b = k * 100;   if (b >= 1) return 'Enough to run an LED bulb for ' + Math.round(b) + ' h 💡';
        return '';
      }
      function moneyRef(k, rate){
        var r = (k * rate) / 0.0125; if (r >= 1) return 'Enough to buy ' + Math.round(r) + ' Robux 🎮';
        return '';
      }
      function co2Ref(k){
        var mi = (k * 0.4) / 0.404; if (mi >= 1) return 'Enough to skip ' + mi.toFixed(1) + ' mi of driving 🚗';
        var m = mi * 1609.34;       if (m >= 1) return 'Enough to skip ' + Math.round(m) + ' m of driving 🚗';
        return '';
      }

      function drawSpark(h){
        if (!h || h.length < 2){ el('spark').innerHTML = ''; return; }
        var maxV = Math.max(100, Math.max.apply(null, h)), W = 100, H = 34, step = W/(h.length-1), pts = '';
        for (var i = 0; i < h.length; i++){
          var x = i*step, y = H - Math.min(h[i], maxV)/maxV*H;
          pts += x.toFixed(1) + ',' + y.toFixed(1) + ' ';
        }
        el('spark').innerHTML = '<polyline points="' + pts + '" fill="none" stroke="#38bdf8" stroke-width="1.6" vector-effect="non-scaling-stroke"/>';
      }

      function renderApps(apps){
        if (!apps || !apps.length){ el('apps').innerHTML = '<div class="mut">No apps found.</div>'; return; }
        var h = '';
        for (var i = 0; i < apps.length; i++){
          var a = apps[i];
          h += '<div class="approw" onclick="toggleApp(\\'' + a.bid + '\\',' + (a.managed?0:1) + ')">'
             + '<span class="chk' + (a.managed?' on':'') + '">' + (a.managed?'✓':'') + '</span>'
             + '<span class="an">' + escHtml(a.name) + '</span>'
             + '<span class="ac">' + (a.running ? (a.cpu + '%') : '—') + '</span></div>';
        }
        el('apps').innerHTML = h;
      }

      function renderLaunchApps(list){
        if (!list || !list.length){ el('launchApps').innerHTML = '<div class="mut">No apps yet — add one from the Mac.</div>'; return; }
        var h = '';
        for (var i = 0; i < list.length; i++){
          var a = list[i];
          h += '<div class="approw">'
             + '<span class="an">' + escHtml(a.name) + '</span>'
             + '<span class="ac">' + (a.running ? 'open' : '—') + '</span>'
             + '<span class="rm" onclick="removeLaunch(\\'' + a.bid + '\\')">✕</span></div>';
        }
        el('launchApps').innerHTML = h;
      }

      function optionsHtml(list, current){
        var h = '';
        for (var i = 0; i < list.length; i++) h += '<option value="' + escHtml(list[i].name) + '">' + escHtml(list[i].name) + '</option>';
        return h;
      }
      function filterRegions(){
        var q = el('regionSearch').value.trim().toLowerCase(), sel = el('region');
        // Keep the current region in the list so the select never goes blank.
        var list = !q ? allRegions : allRegions.filter(function(r){
          return r.name.toLowerCase().indexOf(q) >= 0 || r.name === S.region;
        });
        sel.innerHTML = optionsHtml(list, S.region);
        sel.value = S.region;
      }
      function buildRegions(regions, current){
        var sel = el('region');
        if (!allRegions.length && regions && regions.length){
          allRegions = regions;
          sel.innerHTML = optionsHtml(allRegions, current);
        }
        if (document.activeElement !== sel && el('regionSearch') !== document.activeElement) sel.value = current;
      }

      function render(j){
        if (!j || j.error){ el('err').textContent = j && j.error ? ('Error: ' + j.error) : 'No response'; return; }
        S = j; el('err').textContent = '';

        var color = j.cooling ? '#38bdf8' : (j.running ? '#f59e0b' : '#64748b');
        el('st').innerHTML = '<span class="dot" style="background:' + color + '"></span>' + escHtml(j.status);
        el('cpu').textContent = j.totalCPU + '%';
        el('hot').textContent = j.hottestCPU + '%';
        drawSpark(j.history);

        el('proNote').style.display = j.pro ? 'none' : 'block';
        setToggle('tgAuto', j.enabled, 'Auto-cool when I go AFK');
        setToggle('tgEmg', j.emergencyChill, 'Emergency Chill');
        el('emgOpts').style.display = j.emergencyChill ? 'block' : 'none';
        el('emgCpuVal').textContent = j.emergencyCPU + '% CPU';
        el('emgSecsVal').textContent = j.emergencySeconds < 60 ? (j.emergencySeconds + 's') : (Math.round(j.emergencySeconds/60) + ' min');

        el('mCool').className   = 'seg' + (j.mode === 'Cool' ? ' active' : '');
        el('mFreeze').className = 'seg' + (j.mode === 'Deep Freeze' ? ' active' : '');
        el('modeBlurb').textContent = j.mode === 'Deep Freeze'
          ? 'Fully pauses the app — a true 0% CPU. Best for offline games; online games may disconnect.'
          : 'Throttles the app to a sliver of runtime — big heat cut but stays online. Tested safe 8+ h AFK.';

        el('afkVal').textContent = j.afkSeconds < 60 ? (j.afkSeconds + 's') : (Math.round(j.afkSeconds/60) + ' min');

        el('coolBtn').style.display   = j.cooling ? 'none' : 'block';
        el('resumeBtn').style.display = j.cooling ? 'block' : 'none';

        setToggle('tgAwake', j.keepAwake, 'Keep Mac awake (stay online)');

        renderApps(j.apps);
        renderLaunchApps(j.launchApps);

        var kwh = j.whTotal / 1000;
        el('hrs').textContent = (j.coolSecTotal/3600) < 1 ? (Math.round(j.coolSecTotal/60) + ' min') : ((j.coolSecTotal/3600).toFixed(1) + ' h');
        el('en').textContent  = j.whTotal < 1000 ? (j.whTotal.toFixed(2) + ' Wh') : (kwh.toFixed(3) + ' kWh');
        el('mon').textContent = '$' + (kwh * j.rate).toFixed(4);
        el('co2').textContent = (kwh * 0.4 * 2.20462).toFixed(3) + ' lb';
        el('enRef').textContent  = energyRef(kwh);
        el('monRef').textContent = moneyRef(kwh, j.rate);
        el('co2Ref').textContent = co2Ref(kwh);
        el('wk').textContent  = 'This week: ' + Math.round(j.whWeek) + ' Wh · ' + (j.coolSecWeek/3600).toFixed(1) + ' h';
        buildRegions(j.regions, j.region);
        var custom = j.region === 'Custom…';
        var cr = el('customRate');
        cr.style.display = custom ? 'block' : 'none';
        if (custom && document.activeElement !== cr) cr.value = j.rate;
        el('rate').textContent = '$' + j.rate.toFixed(2) + '/kWh';

        [0,30,60,120].forEach(function(f){ el('fps' + f).className = 'seg' + (j.fps === f ? ' active' : ''); });
      }

      get(); setInterval(get, 2000);
    </script></body></html>
    """
}
