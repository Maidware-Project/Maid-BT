# Maid BT - a linux only seamless Bluetooth earbuds switcher

one single click switcher  (PC / phone / off) with automatic audio routing
for any earbuds + any wired fallback (speakers, DAC/AMP).
this package — `install.sh` asks for your MAC and fallback sink.

what it does, in plain words:

- `on` — turns bluetooth on, connects your earbuds, moves all sound
  to them. switching takes about a second.
- `release` — hands the buds to your phone without fully
  disconnecting, so switching back is instant. use this every day.
- `off` — full shutdown: disconnects, kills the radio. use `release`
  instead unless you're done for the day.
- background watcher — notices whenever bluetooth changes (even from
  KDE's own toggle), connects your buds when they show up, parks
  sound on your speakers when they vanish. also parks sound when you
  lock the screen and restores it on unlock.
- phone remote (optional, off unless you enable it) — an app on your
  phone (MacroDroid/Tasker) can tell the PC "I'm playing music" or
  "call started" over wifi. see `phone/`.
- battery boost (optional, off unless you enable it) — picks the
  sound quality based on earbud battery to save power. test first: on
  some systems switching quality crashes the desktop.
- any headset — if a *different* bluetooth headset connects, it gets
  sound automatically. yours always win when they appear.
- tray widget + launcher icons — buttons for PC / phone / off.
- **Maid Watcher** (optional) — when a phone call comes in, it pauses
  your music and mutes Discord, then restores everything on hangup.
  also reconnects up to 2 earbuds in priority order and warns you at
  low battery. works on any init system.
- every switch can also ping your phone over KDE Connect (skipped
  quietly if you don't have it paired).

## layout

```
bin/            toggle + watcher + wrappers + intent server + notify menu
watcher/        Maid Watcher daemon (calls, 2-device priority, battery)
systemd/        user units (fallback watcher, intent listener, menu)
plasmoid/       KDE tray widget (PC / Phone / Off buttons + live state)
desktop/        launcher icons (pin to panel/task manager)
phone/          MacroDroid/Tasker recipes + intent endpoint table
bluetooth-buds.conf.example   per-machine MAC + fallback sink template
install.sh      multi-distro installer (Arch/Debian/Fedora/openSUSE)
```

## requirements (important read)

| need | arch | debian/ubuntu | fedora | opensuse |
|---|---|---|---|---|
| bluetooth stack | bluez bluez-utils | bluez bluetooth | bluez | bluez |
| rfkill | util-linux | rfkill | rfkill | (util-linux) |
| notify-send | libnotify | libnotify-bin | libnotify | libnotify-tools |
| pactl | libpulse | pulseaudio-utils | pulseaudio-utils | pulseaudio-utils |
| python3 (intent) | python | python3 | python3 | python3 |
| phone pings (opt) | kdeconnect | kdeconnect | kdeconnect | kdeconnect-kde |

systemd only for now — the watcher/listener run as user services. the
scripts themselves work anywhere, autostart is on you. fork it and wire
your own init if you want.


## installation

```sh
bash install.sh            # deps (sudo) + copy + enable services + prompt for earbuds
bash install.sh --check    # dry run
bash install.sh --no-packages  # skip package install
```

install.sh copies (never symlinks) into `~/.local/bin`, `~/.config/systemd/user`,
`~/.local/share/{plasma/applications}`, enables `buds-fallback.service` and
`bt-intent.service`, generates `~/.config/bt-intent.token` (only used if
you enable phone integration at the prompt), and prompts for
`~/.config/bluetooth-buds.conf` (MAC validated, placeholder rejected).
Existing files are backed up to `*.bak-<timestamp>`. install.sh downloads
nothing — every dependency comes from your distro repos.

ten: pair + trust earbuds (`bluetoothctl pair/trust`), open the intent
TCP port if using phone push (e.g. `sudo firewall-cmd --permanent --add-port=8899/tcp`),
Add Widgets → BT Earbuds (tray), log out/in.

## usage 

```sh
bluetooth-toggle.sh on|off|release|radio|toggle|status|porcelain
buds-on.sh / buds-off.sh / buds-release.sh   # wrappers
```

## NOTES (MUST READ)

kde plasma for some unknown reason could segfault / crash when bluetooth A2DP transport dies ¯\_(ツ)_/¯ (do not blame me honestly)
abruptly (`spa.bluez5: Failure ...` → `QAudioContext` SIGSEGV) — a system bug
not this package. This setup is designed around it: warm-link `release`
instead of disconnects, anti-flap backoff, instant bluez suspend on drop.
Prefer `release` over `off`; if plasmashell crashes, check
`coredumpctl` + journal for the `spa.bluez5: Failure` signature.

electron/chromium apps (spotify, vesktop, discord, browsers) can go
silent after a switch even though the stream moved fine. their web-audio
stack opens the output at fixed params and stalls when the bluetooth
codec/rate renegotiates under it (LDAC 96k ↔ SBC 44.1k/48k) — not our
routing, the app itself. fix is pause → switch → play; if an app stays
dead, restart just that app. the scripts do this automatically now
(pause Playing players across every switch, resume only those after —
opt out with `APP_CYCLE=0` in the conf).

audio delay, the three kinds and what helps:

- late start (~1s cut after silence): PipeWire suspends idle BT nodes.
  fix is `wireplumber/51-bt-no-suspend.conf` (install.sh offers it,
  opt-in, default off — it costs earbud battery). `maid-watcher status`
  shows the live profile.
- lip-sync lag: codec physics (SBC/AAC ~200ms, LDAC 300ms+). no PC
  software removes it — compensate in the player (VLC: J/K keys,
  mpv: `--audio-delay=-0.2`). SBC is usually the lowest-latency choice.
- switch gap: reconnect + A2DP setup + reroute takes seconds by nature.
  the watcher retries the profile a few times so it sticks first try.

## RAM budget (measured live, x86_64)

| piece | idle RSS | notes |
|---|---|---|
| `buds-fallback.sh` watcher | ~4 MB | bash, event-driven |
| `maid-watcher` daemon | ~29 MB | python3 + dbus + GLib loop |
| `bt-intent-server.py` | ~24 MB | only when phone integration enabled |
| plasmoid widget | ~0 MB extra | lives inside plasmashell |
| **full stack** | **~57 MB** | ~1.4% of a 4 GB machine |

4 GB rules: keep phone integration off unless used (saves 24 MB),
leave the idle saver off (default), and let zram/zswap handle the rest
— Fedora/openSUSE enable zram by default; Arch/Debian users on 4 GB
should turn it on. The watcher unit caps itself at 150 MB
(`MemoryMax`) so a leak restarts instead of OOMing you. Kernel
differences don't matter here: everything talks to stable userspace
APIs (BlueZ D-Bus, PipeWire, MPRIS), never to kernel internals.

## uninstalling

```sh
bash install.sh --uninstall   # services off + files out (keeps your config + token)
```

manual version of the same:

```sh
systemctl --user disable --now buds-fallback.service bt-intent.service bt-menu.service
rm ~/.local/bin/{bluetooth-toggle,buds-fallback,buds-on,buds-off,buds-release,bt-intent-server.py,bt-notify-menu.sh}*
rm ~/.config/systemd/user/{buds-fallback,bt-intent,bt-menu}.service
rm -rf ~/.local/share/plasma/plasmoids/com.local.btearbuds
rm ~/.local/share/applications/bt-earbuds-*.desktop ~/.local/share/applications/bt-off.desktop ~/.local/share/applications/bt-on.desktop
```

## License

MIT — see LICENSE.
