# Mochi for Mac 🍵

> A desktop companion that keeps you company while you code. You never code alone again.

Mochi is a lightweight desktop companion for macOS. A small green character that idles, looks around, dozes off, and hangs out on your screen while you work.

This is an unofficial native macOS port of [miflow13/mochi-desktop](https://github.com/miflow13/mochi-desktop) (the original Linux/GNOME companion), built from scratch in Swift and AppKit with zero external dependencies.

---

## Features

- **Presence:** Mochi sits on your desktop, idles, blinks, looks around, sleeps, and wakes up.
- **Interactivity:** Click for bounce or squish reactions, double-click for a heart emote, feed him snacks, or drag him anywhere.
- **Awareness:** Mochi notices when you switch between code editors, terminals, and browsers. After 5 minutes without keyboard, mouse, or scroll input, he dozes off and wakes when you return.
- **Focus Sessions:** Start a 25-minute focus session from the menu. Mochi stays calm and quiet beside you, with a heart reward when your session finishes.
- **Roaming:** Mochi occasionally takes a short walk along the bottom of your screen, pausing immediately if you type, click, drag, or start a focus session.
- **Menu Bar Companion:** A 🌱 menu-bar icon lets you bring Mochi to your active screen or quit anytime.

---

## Controls

| Interaction | Action |
| :--- | :--- |
| **Left-click** | Bounce or squish reaction |
| **Double-click** | Heart emote ❤️ |
| **Drag & Drop** | Pick up and reposition Mochi anywhere |
| **Right-click / Control-click** | Feed, heart, sleep/wake, change size (small / medium / large), toggle Awareness & Roaming |
| **Click sleeping Mochi** | Wake him up |
| **🌱 Menu bar icon** | Bring Mochi to current display, quit |

---

## Installation

### Download pre-built release (Apple Silicon)

1. Download `Mochi-0.1.0-macos-arm64.zip` from [Releases](https://github.com/kwakuoseikwakye/mochi-desktop-mac/releases).
2. Unzip and drag `Mochi.app` into `/Applications`.
3. Because release builds are self-signed and not notarized, macOS sets a quarantine flag on downloaded binaries. Run this once in Terminal to allow it:

```sh
xattr -dr com.apple.quarantine /Applications/Mochi.app
```

4. Open Mochi from Applications or Spotlight.

*Requires Apple Silicon (M1/M2/M3/M4) running macOS 13 (Ventura) or newer.*

---

### Build from source (Apple Silicon & Intel)

Building from source requires macOS 13+ and Xcode command line tools (`xcode-select --install`):

```sh
git clone https://github.com/kwakuoseikwakye/mochi-desktop-mac.git
cd mochi-desktop-mac

# Build release bundle
bash scripts/build.sh

# Run
open dist/Mochi.app
```

---

## Privacy & Permissions

Mochi is designed to be completely unobtrusive and private:

- **Zero permissions required:** Mochi does not ask for Accessibility, Screen Recording, or Input Monitoring permissions.
- **No keylogging:** Mochi only checks the time elapsed since your last input (`CGEventSource.secondsSinceLastEventType`) to know when you are actively typing or idle. It never reads or records your keystrokes.
- **No window snooping:** Mochi only inspects the active application's bundle identifier (to distinguish code editors and terminals from web browsers). It cannot see window contents or titles.
- **Zero network activity:** Mochi makes no network requests and has no analytics or telemetry.

---

## Testing & Verification

Run the automated test suite and sprite smoke test:

```sh
# Run 46 unit tests
swift test

# Run sprite smoke test (verifies all 119 bundled animation frames in an offscreen panel)
dist/Mochi.app/Contents/MacOS/MochiMac --smoke-test
```

---

## Credit & Attribution

Mochi for Mac is an unofficial Mac port of [Mochi](https://github.com/miflow13/mochi-desktop) created by **miflow13** and the Mochi contributors.

- The character design, sprites, and animations are from upstream commit `9cdd100`, used under the MIT License.
- The macOS implementation is a new native Swift/AppKit codebase.
- Upstream license and credits are preserved in [UPSTREAM.md](UPSTREAM.md) and bundled inside the app (`MOCHI-LICENSE.txt`).
- This project is an independent community port and is not affiliated with or endorsed by the original Mochi project.

---

## License

Mochi for Mac is released under the [MIT License](LICENSE).
