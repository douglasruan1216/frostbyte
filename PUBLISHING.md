# Publishing FrostByte (for Douglas + a parent/guardian)

This is the checklist to turn FrostByte from "works on my Mac" into "anyone can download,
trust, and buy it." A few steps **legally require an adult** (18+) — those are marked 👤.
Douglas does all the building; a parent owns the accounts and the money.

---

## Why it can't go on the Mac App Store

FrostByte pauses other apps, edits Roblox's settings file, and runs a small local web
server. The App Store sandbox forbids all three, so FrostByte must be distributed
**directly** (a download link), which means it has to be *notarized* by Apple so it
installs without scary warnings.

---

## Step 1 — 👤 Apple Developer Program ($99/year)

Needed to get a "Developer ID" certificate so macOS trusts the app.

1. A parent signs up at <https://developer.apple.com/programs/> ($99/yr).
2. In Xcode (or the developer portal), create a **Developer ID Application** certificate.
3. Note your **Team ID** (a 10-character code, e.g. `AB12CD34EF`).

## Step 2 — Sign with the real certificate (not ad-hoc)

Right now `build_app.sh` signs "ad-hoc" (`codesign --sign -`), which is fine for your own
machine but not for sharing. For release, change the sign line to your Developer ID and
turn on the hardened runtime (required for notarization):

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  "$APP"
```

## Step 3 — Notarize (Apple scans it for malware, ~2–5 min)

1. Create an **app-specific password** at <https://account.apple.com> (Sign-In & Security →
   App-Specific Passwords). This is safer than using the main Apple ID password.
2. Zip and submit:

```bash
cd ~/ComputerCooler
ditto -c -k --keepParent FrostByte.app FrostByte.zip
xcrun notarytool submit FrostByte.zip \
  --apple-id "PARENT_APPLE_ID_EMAIL" \
  --team-id "TEAMID" \
  --password "APP_SPECIFIC_PASSWORD" \
  --wait
```

3. When it says **Accepted**, "staple" the ticket so it works offline:

```bash
xcrun stapler staple FrostByte.app
```

Now zip it again for distribution — that zip is what people download. It opens with a
normal one-click confirmation instead of a scary "unidentified developer" block.

---

## Step 4 — 👤 Sell the Pro unlock (Gumroad)

Gumroad is the easiest for a first paid app: it handles credit cards **and taxes**, and it
can auto-generate license keys. The account must be owned by an adult (18+).

1. A parent creates a **Gumroad** account and adds a product "FrostByte Pro" (~$4.99).
2. Turn ON **"Generate a unique license key per sale."**
3. Note the product's **permalink / product ID**.

### Then wire the keys into the app (ask Claude to do this part)

There's a placeholder already in the code (`CoolController.storeProductID`). Once you have
the Gumroad product ID, the license box in the app can verify keys online via Gumroad's API
(`POST https://api.gumroad.com/v2/licenses/verify`) and unlock Pro on success. Just say the
word and I'll write that function.

### Friend codes (giving friends Pro for free)

You do **not** need to build a custom coupon system — Gumroad already does one-time codes,
and they use the exact same license box as paying customers. To comp a friend:

1. In the Gumroad dashboard: **Create a discount code** → set it to **100% off** →
   set **max uses = 1** (that makes it one-time).
2. That's your "generate" step — Gumroad gives you the code. Send it to your friend.
3. Your friend opens the FrostByte page, enters the code, checks out for **$0**, and
   Gumroad emails them a real **license key**.
4. They paste that key into **FrostByte Pro → License key → Unlock**. Done.

**Why not a code generator inside the app?** Making a code truly *one-time* needs a central
server to remember which codes were used — an offline code could just be re-pasted or shared
in a group chat and used many times. Gumroad is that server, for free. (Optional later: an
owner-only "Generate friend code" button in the app that calls the Gumroad API for you —
needs your Gumroad API key, so it's a post-launch add-on.)

---

## ⚠️ Step 5 — Ending early access (the honest way)

FrostByte currently ships in **early access**: `CoolController.freeLaunch = true` makes every
Pro feature free, and stamps each Mac that runs it as an `earlyAdopter` (saved permanently
in that Mac's settings).

When the GitHub download counter passes **100**:

1. Set `static let freeLaunch = false` in `CoolController.swift`.
2. Do Step 4 (Gumroad) and paste the product ID into `storeProductID`. Search for `LAUNCH TODO`.
3. Rebuild, notarize, cut a new release.

Everyone who already installed **keeps Pro forever** — their `earlyAdopter` stamp is already
on disk, and `isPro` is `earlyAdopter || licensed`. Only new installs see the lock. That's a
promise made on the landing page, so **never clear the stamp**.

There is deliberately **no owner/master key** in the code. An earlier build had one, but this
repo is public — any hardcoded key would be readable by anyone, and git history would keep it
forever even after deleting it. Douglas's own Mac is unlocked by the `earlyAdopter` stamp
instead, which needs no secret.

---

## Suggested launch order

1. ✅ Ship the app **free** first, notarized (Steps 1–3). Build a small audience.
   - Post a short video (fan noise dropping when you step away) on **r/macgaming** and
     Roblox communities. Free + open about how it works = trust.
2. Add the **Pro unlock** (Steps 4–5) once people are using it and asking for more.
3. Optional later: a permanent "works anywhere" phone link via **Tailscale**.
