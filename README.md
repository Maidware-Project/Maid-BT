# Maid BT - bluetooth earbuds switching

a command-line helper that ships its own gui: a Plasma tray applet and a small helper window. switch between PC, phone, or off with one command - or one click. routes audio automatically (app-agnostic stream moves, so it works across players and browsers) and stops dual-connection earbuds from fighting your phone. native tools only (bluez, PipeWire/PulseAudio via `pactl`/`pw-*`); no accounts, no telemetry.

```
bin/            the switcher scripts (on/off/release, background watcher)
watcher/        Maid Watcher daemon (calls, reconnects, battery)
wireplumber/    optional fix for the 1-second late start (see notes)
systemd/        background services (auto-connect watcher, phone listener)
plasmoid/       the Plasma 6 tray widget with PC / phone / off buttons
desktop/        launcher icons you can pin to your panel
phone/          phone remote setup (MacroDroid/Tasker, optional)
contrib/        compositor keybind/Waybar snippets (Hyprland/Sway/i3)
tests/          suite tests (run with `bash tests/run.sh`)
install.sh      installer - Arch, Debian/Ubuntu (incl. Mint), Fedora, openSUSE
```

## quick start

```sh
# one line, straight from GitHub:
bash <(curl -fsSL https://raw.githubusercontent.com/Maidware-Project/Maid-BT/main/install.sh)

bash install.sh            # installs everything, asks you questions
bash install.sh --tui      # menu: install, config, doctor, uninstall
bluetooth-toggle.sh on     # sound moves to your earbuds
```

prefer a clone? `git clone --depth 1 https://github.com/Maidware-Project/Maid-BT.git` and run `bash install.sh`.

## why not just use blueman / the desktop bluetooth panel?

those manage *devices* (pairing, mice, keyboards). Maid BT manages the
*earbuds workflow*: one click moves you PC → phone → off, sound follows
automatically, dual-connection buds stop fighting the phone, and quality
stays at your buds' stock settings unless you opt into the LDAC lock.
keep your bluetooth manager for pairing; use this for daily switching.

tested daily on openSUSE Tumbleweed (KDE Plasma, PipeWire, LDAC
earbuds). installer covers Arch, Debian/Ubuntu (incl. Mint), Fedora.
suite green in CI (`bash tests/run.sh`).

## what it does

- `on` - turns bluetooth on, connects your earbuds, moves all sound to
  them (works with every app/player). switching takes about a second.
- `release` - hands the buds to your phone without fully disconnecting,
  so switching back is instant. use this every day. dual-connection buds
  (phone+PC at once): set `MULTIPOINT=1` once and release parks the PC
  for the day instead of minutes.
- `off` - full shutdown: disconnects, kills the radio. use `release`
  instead unless you're done for the day.
- `--doctor` / `doctor` - reports session/compositor and stack support
  truthfully (core CLI/TUI works across compositors; the Plasma applet is
  KDE/Plasma-only). see `contrib/compositors/` for Hyprland/Sway/i3
  snippets.
- background watcher - notices whenever bluetooth changes (even from
  KDE's own toggle), connects your buds when they show up, parks sound
  on your speakers when they vanish. also parks sound when you lock the
  screen and restores it on unlock.
- phone remote (optional, off unless you enable it) - an app on your
  phone (MacroDroid/Tasker) can tell the PC "I'm playing music" or "call
  started" over wifi. see `phone/` and the
  [MacroDroid/Tasker source](https://github.com/Maidware-Project/Maid-BT/blob/main/phone/README-macrodroid-tasker.md);
  the phone remote is part of Maid BT (documented in the BT guide).
- battery boost (optional, off unless you enable it) - picks the sound
  quality based on earbud battery to save power. test first: on some
  systems switching quality crashes the desktop.
- any headset - if a *different* bluetooth headset connects, it gets
  sound automatically. yours always win when they appear.
- tray widget + launcher icons - buttons for PC / phone / off. the
  applet's Configure dialog covers the MAC, fallback speakers, retry
  timings, calls, battery warnings, saver, laptop mode, mic routing, and
  the fallback toggles.
- **Maid Watcher** (optional) - when a phone call comes in, it pauses
  your music and mutes Discord, then restores everything on hangup. also
  reconnects up to 2 earbuds in priority order and warns you at low
  battery. works on any init system.
- volume memory - the buds' level is remembered while they play and
  handed back on the next arrival, so a reconnect (or unlock, or reboot)
  never comes back too quiet. a fresh pairing keeps the buds' own default.
- controller respect - a bluetooth gamepad (DualSense and friends) never
  counts as a headset; wired pads (InputPlumber / joycond) are untouched.
- every switch can also ping your phone over KDE Connect (skipped quietly
  if you don't have it paired).

## plasma applet + Maid BT Helper

the installer offers a compact Plasma 6 tray applet: tiles for this PC,
phone, other devices and off, codec + battery on the header, and one
line that says where the sound is right now. add it from the system tray
once installed.

also ships **Maid BT Helper**, a small Maidware GUI: read-only checks,
the safe subset of the shell's fixes, one-click LDAC pin (opt-in,
reversible), and a shareable report with no device names and no MAC
addresses - what you paste when filing a bug.

## what you need

| need | arch | debian/ubuntu | fedora | opensuse |
|---|---|---|---|---|
| bluetooth | bluez bluez-utils | bluez bluetooth | bluez | bluez |
| rfkill | util-linux | rfkill | rfkill | (util-linux) |
| notifications | libnotify | libnotify-bin | libnotify | libnotify-tools |
| audio control | libpulse | pulseaudio-utils | pulseaudio-utils | pulseaudio-utils |
| python3 | python | python3 | python3 | python3 |
| phone pings (optional) | kdeconnect | kdeconnect | kdeconnect | kdeconnect-kde |

the background pieces need systemd. no systemd (OpenRC etc.)? the
switcher scripts and Maid Watcher still work - you just start them
yourself instead of getting auto-start.

## installation

```sh
bash install.sh                # installs everything, asks you questions
bash install.sh --check        # dry run: shows what it would do
bash install.sh --no-packages  # skip installing packages
```

the installer copies files into place (never symlinks), asks for your
earbuds, offers the optional extras (phone remote, Maid Watcher,
warm-link audio), and backs up anything it replaces. it downloads
nothing - everything comes from your distro's own packages.

then: pair + trust your earbuds (`bluetoothctl pair` + `trust`), add the
"Maid BT" widget to your panel. if it does not appear yet, restart
plasmashell; a full logout is not needed. if you use the phone remote,
also open TCP port 8899 in your firewall.

## usage

```sh
bluetooth-toggle.sh on|off|release|radio|toggle|status|porcelain
bluetooth-toggle.sh --doctor   # session/compositor + stack report
buds-on.sh / buds-off.sh / buds-release.sh   # shortcuts
maid-watcher status            # connection, profile, battery
```

## notes (please read)

**KDE can crash when bluetooth audio dies suddenly.** that's a system
bug, not this package (`spa.bluez5: Failure` → desktop crash). the whole
setup is designed around it: `release` keeps the link warm instead of
tearing it down, reconnects back off instead of hammering. prefer
`release` over `off` every day.

**some apps go silent after a switch** (Spotify, Discord, browsers).
their sound engine can stall when bluetooth changes quality underneath
them - not our routing. fix: pause, switch, play. the scripts do that
automatically and make an app-agnostic pass over streams; if one app
stays dead, restart just that app (opt out with `APP_CYCLE=0`).

**sound delays, and what helps:**

- late start (~1 second cut after silence): bluetooth naps when idle.
  fix is the optional warm-link config (installer offers it; costs a
  little earbud battery).
- thin sound after a switch (stuck on SBC): the card can land on a low
  codec and stay there. fix is the optional max-quality config (pins
  LDAC first, unlocks SBC-XQ) plus `QUALITY_LOCK=1` in
  `~/.config/bluetooth-buds.conf` to enforce LDAC after every switch.
  costs earbud battery; needs LDAC buds. the lock also rescues a card
  stuck on HSP/HFP with nobody on the mic (a live call mic is never touched).
- fully silent dual-mode buds: newer stacks may try LE Audio transports
  first; without working ISO sockets they fail while classic A2DP would
  be fine. fix is the optional a2dp-only config, then reconnect once.
- lip-sync lag: bluetooth sound always trails video a bit (SBC/AAC
  ~0.2s, LDAC ~0.3s). nothing on the PC removes it - nudge it in your
  player (VLC: J/K keys, mpv: `--audio-delay=-0.2`).
- switch gap: reconnecting + rerouting takes a few seconds by nature.

**the fallback sink must be a name.** `FALLBACK_SINK` in
`~/.config/bluetooth-buds.conf` wants a NAME from `pactl list short
sinks`, not the number on its left - numbers are per-session and go
stale.

## Linux Mint (incl. older releases)

Mint is Ubuntu underneath, so the `apt` installer path handles it
(Cinnamon, MATE, Xfce). PulseAudio (not PipeWire) on most Mint installs
is handled automatically via `pactl` fallbacks. Older BlueZ (e.g. 5.53 on
Mint 20.x): battery reporting may be absent (shown as unknown), HFP
wideband needs 5.65+ and falls back to CVSD silently, A2DP SBC always
works.

## RAM budget (measured live)

| piece | idle memory | notes |
|---|---|---|
| background watcher | ~4 MB | tiny script, sleeps until needed |
| Maid Watcher daemon | ~29 MB | calls, reconnects, battery |
| phone listener | ~24 MB | only runs if you enable phone remote |
| tray widget | ~0 MB extra | lives inside the desktop itself |
| **everything together** | **~57 MB** | ~1.4% of a 4 GB machine |

on 4 GB machines: leave phone remote off unless you use it, leave the
idle saver off (default). Fedora/openSUSE already compress RAM (zram).

## NixOS (flakes & home-manager)

a `flake.nix` is provided for the cli/tools:

```sh
nix run github:Maidware-Project/Maid-BT -- status
# or install: nix profile install github:Maidware-Project/Maid-BT
```

home-manager: enable `programs.maid-bt.enable = true;` via the flake’s `homeManagerModules.default`. bluez/pipewire (or pulseaudio-compat), rfkill, and notifications come from your NixOS config; user services (watcher/listener) and the Plasma plasmoid are session/system-specific - manage them via home-manager/systemd user units or the tool’s own setup as appropriate.

## uninstall

```sh
bash install.sh --uninstall            # everything out, asks about settings
bash install.sh --uninstall --purge    # everything out including settings, no questions
```

or by hand: stop the background services, delete the installed files
and the widget (see `install.sh --uninstall` for the exact list; it also
removes the Maid Watcher, its autostart entry, and the warm-link audio
config).

## works with the Maid suite

Maid BT stands alone. it works well with [Maid Suite](https://github.com/Maidware-Project/Maid-Suite),
the canonical Maidware front end (TUI/GUI) which embeds the Helper and
AU updater cores and can install/update Maid BT and the rest of the
suite. the standalone Maid Helper and Maid AU repos are archived; their
cores live in Maid Suite. the bundled Maid Watcher shares your KDE
Connect phone pairing with Maidshare.

## License

GPL-3.0-or-later — forkable and open source. See `LICENSE`. Third-party
notices and credits: `THIRD-PARTY-NOTICES.md` (names what Maid BT
references or depends on; third-party components keep their own
licenses). Part of the Maidware Project.
