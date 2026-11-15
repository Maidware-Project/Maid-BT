# Maid BT

Maid BT is a Linux Bluetooth audio workflow tool for switching between **PC**, **phone/release**, and **off/radio** states quickly and reliably. It includes CLI tools, optional background services/watchers, and a Plasma tray integration (where applicable).

- **No accounts, no telemetry**
- **Native stack:** BlueZ + PipeWire/PulseAudio tools (`pactl`, `pw-*`)
- **Designed for real-world earbud behavior:** fast switching, safe handoff (`release`), and mitigations for dual-connection/device quirks

## Why Maid BT?
Desktop Bluetooth panels manage pairing/devices. Maid BT focuses on the **daily earbuds workflow**:
- Move audio to/from earbuds with one command/click
- Prefer `release` (warm handoff) over full disconnects to reduce reconnect lag and instability
- Handle common pitfalls (codec/profile issues, silent streams, dual-connection conflicts) with optional configs/helpers
- Provide diagnostics (`--doctor`) and optional phone/watcher integrations

## Features
- **Core commands:** `on`, `off`, `release`, `radio`, `toggle`, `status`, `porcelain`
- **Automatic routing:** moves app streams (app-agnostic) to the selected sink when possible
- **Doctor/reporting:** `bluetooth-toggle.sh --doctor` for session/compositor/stack visibility
- **Optional services:**
  - background watcher (auto-connect/park behavior on BT state changes)
  - Maid Watcher daemon (calls/music behavior, reconnect/battery features)
  - phone remote/listener (opt-in, LAN-based intents)
- **Optional audio/profile helpers:** warm-link, max-quality/LDAC lock, A2DP-only configs (see notes/docs)
- **Plasma integration:** tray widget and Maid BT Helper GUI (KDE Plasma-specific components)

## Quick start

### Install
```sh
# GitHub (primary)
bash <(curl -fsSL https://raw.githubusercontent.com/Maidware-Project/Maid-BT/main/install.sh)

# Codeberg (fallback)
bash <(curl -fsSL https://codeberg.org/Maidware-Project/Maid-BT/raw/branch/main/install.sh)
```

Or clone and run:
```sh
git clone --depth 1 https://github.com/Maidware-Project/Maid-BT.git
cd Maid-BT
bash install.sh
```

### First steps
1. Pair and trust your earbuds (`bluetoothctl pair` / `trust`)
2. Run a switch command:
   ```sh
   bluetooth-toggle.sh on
   bluetooth-toggle.sh release
   bluetooth-toggle.sh status
   ```
3. (Plasma) Add the Maid BT widget to your panel if desired

## Usage

### Common commands
```sh
bluetooth-toggle.sh on|off|release|radio|toggle|status|porcelain
bluetooth-toggle.sh --doctor

# shortcuts
buds-on.sh
buds-off.sh
buds-release.sh

# watcher (if installed/enabled)
maid-watcher status
```

### Recommended daily workflow
- Use **`release`** to hand audio back to phone/park connection for fast return
- Use **`off`** only when you want full shutdown/radio off
- Use **`--doctor`** to inspect session/compositor and audio/Bluetooth stack behavior when troubleshooting

## Supported environments (best effort)
- **Distros/package managers:** Arch (pacman), Debian/Ubuntu/Mint (apt), Fedora (dnf), openSUSE (zypper), Void Linux (xbps)
- **Desktops:** KDE Plasma (including Plasma applet), GNOME, XFCE, MATE, Cinnamon, LXQt
- **WM/compositors:** Hyprland, Sway, i3
- **Shells/environments:** Event Horizon and KineticWE detected/reported where applicable

> Core CLI/TUI tools work broadly on Linux with BlueZ and PipeWire/PulseAudio tooling. Plasma-specific UI components are KDE-only.

## Important notes & troubleshooting
- **Prefer `release` over `off`:** abrupt BT audio teardown can trigger desktop/audio stack instability on some systems.
- **Some apps may stall after audio route/profile changes:** pause/resume or restart the affected app if needed (Maid BT includes mitigation passes; behavior can vary by app/stack).
- **Latency/codec behavior is hardware/stack-dependent:** SBC/AAC/LDAC tradeoffs differ; optional warm-link and quality-lock configs can help specific cases but may increase power use.
- **Fallback sink:** `FALLBACK_SINK` should be a sink **name** (from `pactl list short sinks`), not a transient numeric index.
- **USB reverse tethering:** [gnirehtet](https://github.com/Genymobile/gnirehtet) is a useful ADB companion (separate from Maid BT's Bluetooth workflow).

See in-repo docs for more details:
- [`docs/wiki/`](docs/wiki/Home.md) (quick wiki)
- [`docs/DEVICE-SUPPORT.md`](docs/DEVICE-SUPPORT.md)
- [`docs/REVIEW.md`](docs/REVIEW.md)

## NixOS (flakes & Home Manager)
```nix
inputs.maid-bt.url = "github:Maidware-Project/Maid-BT";
imports = [ inputs.maid-bt.homeManagerModules.default ];
programs.maid-bt.enable = true;
# services.maid-bt.watcher.enable = true;
# services.maid-bt.maidWatcher.enable = true;
# services.maid-bt.intentListener.enable = true;
```

Try without installing:
```sh
nix run github:Maidware-Project/Maid-BT -- status
```

## Uninstall
```sh
bash install.sh --uninstall
# or
bash install.sh --uninstall --purge
```

## Documentation & links
- Website/guides: https://maidware-project.github.io/guides/
- Maid Suite (front end): https://github.com/Maidware-Project/Maid-Suite
- Fallback org mirror: https://codeberg.org/Maidware_Project

## License
GPL-3.0-or-later. See [`LICENSE`](LICENSE) and [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Part of the [Maidware Project](https://maidware-project.github.io/).
