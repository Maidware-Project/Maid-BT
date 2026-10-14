# Maid BT - a linux only seamless Bluetooth earbuds switcher

one single click switcher  (PC / phone / off) with automatic audio routing
for any earbuds + any wired fallback (speakers, DAC/AMP).
this package — `install.sh` asks for your MAC and fallback sink.

what it does and how does it work?

- `bluetooth-toggle.sh on` — unblock + power on, auto-connect earbuds,
  move all audio to them. warm link = ~1s switch.
  
- `bluetooth-toggle.sh release` — park PC audio on the fallback sink, hand
  buds to the phone. Link stays warm: instant switch-back, no link teardown.
  
- `bluetooth-toggle.sh off` — full off: disconnect, park audio, radio
  power off + rfkill block. (Prefer `release` daily — see crash note.)
  
- `buds-fallback.service` (watcher) — catches any power change (even KDE's
  tray toggle): auto-connects when buds appear, parks audio on the fallback
  sink when they vanish, with anti-flap circuit breaker. Watches screen
  lock: parks on lock, restores on unlock only if buds are connected.
  
- `bt-intent.service` — tiny LAN HTTP listener so the phone can push
  playback/call intent (MacroDroid/Tasker). See `phone/`. **Off by
  default at install** (opt-in prompt); core switching is fully local.
- battery boost (opt-in, off by default) — watcher matches A2DP codec
  to earbuds battery (LDAC/AAC/SBC-XQ/SBC bands). see CHANGELOG, it
  can crash plasmashell on some systems so test first.
- any-headset mode: a newly connected bluetooth headset (not yours)
  grabs audio automatically, no manual switch. yours connect first and
  always win on appearance; other paired headsets get priority connects
  when yours are down. hands-off silences all of it; a vanished default
  gets parked on fallback.
- Tray widget (`plasmoid/`) + three launcher icons (`desktop/`) +
  optional notification menu (`bt-notify-menu.sh`, superseded by widget).
  
- KDE Connect pings to the phone on every switch (needs `kdeconnect-cli`
  + paired phone; silently skipped otherwise).

## layout

```
bin/            toggle + watcher + wrappers + intent server + notify menu
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
