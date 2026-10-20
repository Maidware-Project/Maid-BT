# Maid BT v1.0 - bluetooth earbuds switching

command-line helper. switching between pc, phone, or off with one command. routes audio automatically and stops dual-connection earbuds from fighting your phone. install asks for your mac and fallback sink.

## quick start

```sh
bash install.sh                # asks for your earbuds MAC + fallback sink
bluetoothctl pair <MAC>        # then: trust <MAC>
bluetooth-toggle.sh on         # sound moves to your earbuds
```

## why not just use blueman / the desktop bluetooth panel?

those manage *devices* (pairing, mice, keyboards). Maid BT manages the
*earbuds workflow*: one click moves you PC → phone → off, sound follows
automatically, dual-connection buds stop fighting the phone, and LDAC
stays enforced instead of silently decaying to SBC. keep your bluetooth
manager for pairing; use this for daily switching.

tested daily on openSUSE Tumbleweed (KDE Plasma, PipeWire, LDAC
earbuds). installer covers Arch, Debian/Ubuntu (incl. Mint), Fedora.
suite green in CI (`bash tests/run.sh`, 20+ checks).

what it does, in plain words:

- `on` - turns bluetooth on, connects your earbuds, moves all sound
  to them. switching takes about a second.
- `release` - hands the buds to your phone without fully
  disconnecting, so switching back is instant. use this every day.
  dual-connection buds (phone+PC at once): set `MULTIPOINT=1` once
  and release parks the PC for the day instead of minutes.
- `off` - full shutdown: disconnects, kills the radio. use `release`
  instead unless you're done for the day.
- background watcher - notices whenever bluetooth changes (even from
  KDE's own toggle), connects your buds when they show up, parks
  sound on your speakers when they vanish. also parks sound when you
  lock the screen and restores it on unlock.
- phone remote (optional, off unless you enable it) - an app on your
  phone (MacroDroid/Tasker) can tell the PC "I'm playing music" or
  "call started" over wifi. see `phone/`.
- battery boost (optional, off unless you enable it) - picks the
  sound quality based on earbud battery to save power. test first: on
  some systems switching quality crashes the desktop.
- any headset - if a *different* bluetooth headset connects, it gets
  sound automatically. yours always win when they appear.
- tray widget + launcher icons - buttons for PC / phone / off. open
  the applet's Configure dialog for Earbuds and Behavior pages covering
  the MAC, fallback speakers, retry timings, calls, battery warnings,
  saver, laptop mode, mic routing, and the fallback toggles.
- **Maid Watcher** (optional) - when a phone call comes in, it pauses
  your music and mutes Discord, then restores everything on hangup.
  also reconnects up to 2 earbuds in priority order and warns you at
  low battery. works on any init system.
- every switch can also ping your phone over KDE Connect (skipped
  quietly if you don't have it paired).

## layout

```
bin/            the switcher scripts (on/off/release, background watcher)
watcher/        Maid Watcher daemon (calls, reconnects, battery)
wireplumber/    optional fix for the 1-second late start (see below)
systemd/        background services (auto-connect watcher, phone listener)
plasmoid/       the tray widget with PC / phone / off buttons
desktop/        launcher icons you can pin to your panel
phone/          phone setup guide (MacroDroid/Tasker)
install.sh      installer - works on Arch, Debian/Ubuntu, Fedora, openSUSE
```

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

what the installer does: copies files into place (never symlinks, so
moving the folder can't break anything), asks for your earbuds, offers
the optional extras (phone remote, Maid Watcher, warm-link audio),
backs up anything it replaces. it downloads nothing - everything comes
from your distro's own packages.

then: pair + trust your earbuds (`bluetoothctl pair` + `trust`), add
the "Maid BT" widget to your panel. if it does not appear yet, restart
plasmashell; a full logout is not needed. if you use
the phone remote, also open TCP port 8899 in your firewall.

## usage

```sh
bluetooth-toggle.sh on|off|release|radio|toggle|status|porcelain
buds-on.sh / buds-off.sh / buds-release.sh   # shortcuts for the above
maid-watcher status                          # connection, profile, battery
```

## notes (please read)

**KDE can crash when bluetooth audio dies suddenly.** that's a system
bug, not this package (`spa.bluez5: Failure` → desktop crash). the
whole setup is designed around it: `release` keeps the link warm
instead of tearing it down, reconnects back off instead of hammering.
prefer `release` over `off` every day.

**some apps go silent after a switch** (Spotify, Discord, browsers).
their sound engine stalls when bluetooth changes quality underneath
them - again not our routing. fix: pause, switch, play. the scripts do
that automatically; if one app stays dead, restart just that app
(opt out with `APP_CYCLE=0`).

**sound delays, and what helps:**

- late start (~1 second cut after silence): bluetooth naps when idle.
  fix is the optional warm-link config (installer offers it; costs a
  little earbud battery).
- thin sound after a switch (stuck on SBC): the card can land on a
  low codec and stay there. fix is the optional max-quality config
  (installer offers it; pins LDAC first, unlocks SBC-XQ) plus
  `QUALITY_LOCK=1` in `~/.config/bluetooth-buds.conf` to enforce
  LDAC after every switch. costs earbud battery; needs LDAC buds.
  the lock also rescues a card stuck on HSP/HFP with nobody on the
  mic (e.g. after a restart) - a live call mic is never touched.
- fully silent dual-mode buds: newer stacks try LE Audio transports
  first on buds that offer it, and without working ISO sockets those
  transports fail over and over while classic A2DP would be fine.
  fix is the optional a2dp-only config (installer offers it; locks
  the buds to classic A2DP), then reconnect once.
- lip-sync lag: bluetooth sound always trails video a bit (SBC/AAC
  ~0.2s, LDAC ~0.3s). nothing on the PC removes it - nudge it right
  in your player (VLC: J/K keys, mpv: `--audio-delay=-0.2`).
- switch gap: reconnecting + rerouting takes a few seconds by nature.
  that's physics, not a bug.

**the fallback sink must be a name.** `FALLBACK_SINK` in
`~/.config/bluetooth-buds.conf` wants a NAME from `pactl list short
sinks`, not the number on its left - numbers are per-session and go
stale. the daemon warns about a numeric one at start and skips the
park instead of failing silently.

## Linux Mint (incl. older releases)

Mint is Ubuntu underneath, so the `apt` installer path handles it
(Cinnamon, MATE, Xfce). What differs from the reference setup:

- **PulseAudio, not PipeWire** on most Mint installs: every audio
  helper tries PipeWire first, then the same operation over `pactl`
  (profiles with underscore names, stream moves, mute). Nothing to
  configure - it degrades automatically.
- **Older BlueZ** (5.53 on Mint 20.x): battery reporting may be absent
  (shown as unknown, never crashes), HFP wideband needs 5.65+ and
  falls back to CVSD silently, A2DP SBC always works (mandatory
  codec). LDAC/aptX need their codec libs installed or you get SBC.

## RAM budget (measured live)

| piece | idle memory | notes |
|---|---|---|
| background watcher | ~4 MB | tiny script, sleeps until needed |
| Maid Watcher daemon | ~29 MB | does calls, reconnects, battery |
| phone listener | ~24 MB | only runs if you enable phone remote |
| tray widget | ~0 MB extra | lives inside the desktop itself |
| **everything together** | **~57 MB** | ~1.4% of a 4 GB machine |

on 4 GB machines: leave phone remote off unless you use it, leave the
idle saver off (it is by default). Fedora/openSUSE already compress RAM
for you (zram); Arch/Debian users should turn it on.

## uninstalling

```sh
bash install.sh --uninstall            # everything out, asks about settings
bash install.sh --uninstall --purge    # everything out including settings, no questions
```

or by hand: stop the background services, delete the installed files
and the widget (see `install.sh --uninstall` for the exact list, it
also removes the Maid Watcher, its autostart entry, and the
warm-link audio config).

## works with the Maid suite

Maid BT stands alone, but plays nice: [Maid AU](https://github.com/Maidware-Project/Maid-AU) tracks
this repo and pulls its updates (`MAID_SUITE`, deploy with `UPDATE_MAID_DEPLOY=1`),
and the bundled Maid Watcher shares your KDE Connect phone pairing with Maidshare.

## License

MIT - see LICENSE. a Maidware Project, Forkable open source tools served to help
