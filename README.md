# 🧊 FrostByte

**Stop your Mac from overheating while you're AFK — without getting disconnected.**

FrostByte is a tiny macOS menu-bar app. When you leave a game running and step away,
it quietly throttles or pauses it so your Mac stops cooking and the fan goes silent —
but keeps you **online**, so you don't get kicked from the server.

Built for Mac gamers (especially the Roblox AFK-grind crowd) on machines like the
Mac Mini and MacBook Air that get hot and loud fast.

---

## 🎉 Early access — the first 100 downloads keep Pro forever

FrostByte is brand new, so **every Pro feature is free right now**. Download it during early
access and your Mac stays unlocked **permanently** — even after Pro becomes a paid unlock.

No key, no account, no email. The app stamps itself on first run and that's that. If you're
reading this, you're early. 💙

---

## What it does

- **Auto-cool when you're AFK.** Pick a game; when you click away for a bit, FrostByte
  throttles it — big drop in CPU, heat, and fan noise. Comes back the instant you return.
- **Stays connected.** "Cool" mode keeps the game alive so online servers don't drop you.
  Tested for 8+ hours AFK in Roblox with no disconnect.
- **Live heat meter.** A menu-bar emoji that changes with temperature, plus a CPU graph.
- **Roblox FPS cap** (30/60/120) to cool down *active* play, not just idle.
- **Keep-awake + screen-off** so games stay connected when you walk away.
- **Savings estimate** — see the energy, money, and CO₂ you've saved, with fun references
  ("Enough to buy N Robux 🎮"). Works for 150 countries or a custom electricity rate.

### FrostByte Pro unlocks — *all free during early access*

- **Emergency Chill** — cools a game *even while you're playing* if it runs hot for a while.
- **Deep Freeze** — fully pauses a game for a true 0% CPU (great for offline games).
- **Phone remote** — control the whole app from your phone's browser on the same Wi-Fi.
- **Custom auto-launch** — FrostByte opens itself when *any* app you pick (from Finder) opens.
- **Cool unlimited apps** at once (free cools one).

---

## Free vs Pro

| Feature                         | Free | Pro |
|---------------------------------|:----:|:---:|
| Auto-cool when AFK ("Cool")     |  ✅  | ✅  |
| Live heat meter + CPU graph     |  ✅  | ✅  |
| Roblox FPS cap                  |  ✅  | ✅  |
| Keep-awake / turn off display   |  ✅  | ✅  |
| Savings estimate (150 countries)|  ✅  | ✅  |
| Auto-open for Roblox            |  ✅  | ✅  |
| Cool multiple apps at once      |  1   | ∞   |
| **Emergency Chill**             |  —   | ✅  |
| **Deep Freeze**                 |  —   | ✅  |
| **Phone remote**                |  —   | ✅  |
| **Custom auto-launch (any app)**|  —   | ✅  |

**Price:** free while in early access. Later, Pro becomes a **one-time $4.99 unlock** — never
a subscription — and everyone who downloaded early keeps it anyway.

---

## Privacy & trust

FrostByte is a local utility. **Nothing you do leaves your Mac.**

- No accounts, no analytics, no tracking, no internet calls (the only network feature is
  the *optional* phone remote, which is a small web page served **only on your own Wi-Fi**).
- It cools apps by briefly pausing/throttling them (standard macOS signals) and un-pauses
  them the moment you come back — it never modifies or deletes your files.
- The Roblox FPS cap just edits Roblox's own settings file, the same thing the popular
  free "FPS Unlocker" tools do.

---

## Install

1. Download **`FrostByte.zip`** from the [latest release](../../releases/latest) and unzip it.
2. Drag `FrostByte.app` into your **Applications** folder.
3. **Right-click it → Open** → click **Open** in the dialog. *(Right-click matters — see below.)*
4. That's it. It lives in your menu bar (the 🧊 / heat emoji up top). No Dock icon.

### ⚠️ "Apple cannot check it for malicious software"

You'll see that warning on first launch, and it's expected. It doesn't mean anything is wrong
with the app — it means I haven't paid Apple's **$99/year** Developer fee yet, so Apple hasn't
signed off on it. I'm a 13-year-old dev, and I'd rather spend that money once people actually
want the app than before.

**Right-clicking → Open gets past it.** If you double-click instead, macOS gives you no "Open"
button at all — that's why step 3 says right-click.

If macOS still refuses:

> **System Settings → Privacy & Security** → scroll down → click **"Open Anyway"** next to FrostByte.

You shouldn't have to take my word for any of this — **all the source is right here in this
repo.** Read it, or build it yourself:

```sh
git clone https://github.com/douglasruan1216/frostbyte.git
cd frostbyte && ./build_app.sh
```

That builds the exact app in the release, with no Xcode needed.

---

*Made by a 13-year-old dev who was tired of his Mac Mini sounding like a jet engine.*
