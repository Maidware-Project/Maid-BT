# changelog

## unreleased

- **silent install**: a piped run (`bash <(curl ...)`) never touches sudo and
  never asks: packages are opt-in (`--packages` forces, tty runs ask once,
  piped runs skip with a pointer), and every optional question (phone
  integration, watcher autostart, warm-link, max-quality, a2dp-only) only
  fires in a real interactive run - piped runs print their one "off (+ how
  to enable)" line instead. output is quiet by default: one `installed N
  files -> dir` line per destination instead of a per-file dump; `--verbose`
  brings the old full list back.
- `tests/demo.sh`: preview the installer the way a fresh user sees it, in a
  throw-away home with shims for sudo, package managers, systemctl, bluez
  and pulse. `bash tests/demo.sh` prints the piped experience;
  `bash tests/demo.sh --window` opens the interactive TUI in your default
  terminal (ghostty/konsole/kitty/... auto-detected).
- fixed: the menu crashed the shell on first draw (`$1: unbound
  variable` under `set -u` in rule()/head(), and again in the
  keep-existing-MAC path). suite now pty-runs the TUI so this class of
  bug can't ship again (33 checks).
- you can type `cancel` (or `q`) everywhere: main menu, earbud and
  sink picks, and the uninstall prompt.
- `bash <(curl -fsSL ...raw.../install.sh)` works: install.sh falls back to
  downloading the repo tarball when it is piped through curl, instead of
  failing on a /dev/fd path.
- new text-UI installer (`install.sh --tui` or `bin/tui-install.sh`): screens
  with numbered picks, full install / config-only / doctor / **uninstall**
  (engine `--uninstall [--purge]`), version facts, and an N64-style
  MAIDWARE boot animation that auto-skips (no tty, `TERM=dumb`, `NO_COLOR`,
  narrow, `MAID_FAST=1`) or on any key. detects the default terminal
  ($TERMINAL/$TERM_PROGRAM → session markers → Plasma kdeglobals → common
  binaries) and records it as `TERMINAL_CMD=` in bluetooth-buds.conf for
  log-tail/helper windows.
- config-only menu choice no longer reruns the engine: it re-picks earbuds
  + fallback sink, rewrites the conf, and restarts buds-fallback only.
- suite extended to 33 checks (TUI parse, no-tty refusal, uninstall wiring,
  boot intro, `--tui` passthrough).

## Maid BT v1.2.2 (this release)

- the watcher used to wake every single second all day: bluetoothctl
  twice, pactl two to three times, qdbus6 for the lockscreen - a dozen
  spawns per second, close to a million a day. steady stretches now run
  on a slower cadence (heavy sweep every 3rd tick, half speed while the
  buds are quietly playing), the lockscreen probe and pactl sweeps ride
  the same gates, and duplicate re-probes inside one tick are gone.
  same reactions, a fraction of the process churn.
- the tray applet used to ask the whole bluetooth stack every 2 seconds
  on top of that (rfkill + bluetoothctl twice). the watcher now
  publishes its readout to a runtime state file every tick, and the
  tray reads that instead when it is fresh - a state question costs a
  file read, not a stack poke. if the watcher is down the tray answers
  itself again, no lying: a stale file is ignored.
- applet busy state fixed: a background state poll finishing mid-switch
  used to unlock all four tiles too early (looked unresponsive, allowed
  double taps), and the stand-down timer fired only once, so a slow
  connect could leave the tiles stuck on one highlight. the poll can no
  longer clear the busy flag, the watch now re-arms until the switch
  really reports back (20s cap), and tile icon/label colors now
  animate to the new tint instead of snapping late.
- switching to the phone: release used to keep the PC-buds link warm
  "for instant switch-back", but the buds then often refused to hand
  audio to the PC's phone connection. release now parks the PC audio,
  gives it a few seconds, and lets go of the link - the buds' Bluetooth
  then walks over to the phone on its own. `on` (or the This PC tile)
  still brings them back in a couple of seconds. the tray reads
  "phone" for the whole hand-off window, the watcher stays hands-off
  (and never powers the radio down mid-hand-off), and the duplicate
  "earbuds disconnected" notices during a release are gone.
- the settings window and its pages follow your system theme now
  (plasma widgets instead of generic ones), open centered on the
  screen, and the Off tile/power icons use names that exist in every
  theme chain (papirus-dark inherits breeze, which has no
  bluetooth-disabled icon - it used to draw a broken fallback).

## Maid BT v1.2.1

- the earbuds state page used to sit for the whole 8s window and come
  back with bluetooth talk (br-connection-refused) when the buds were
  busy. refused control connections now answer in about a second, in
  plain words: buds usually docked, asleep, or on the phone. press
  refresh to go again once the buds are out.
- the applet's four tiles (this pc / phone / radio / off) share one
  tile shape: same rounding, hover and highlight painted on the tile,
  long names cut off instead of stretching the row.

## Maid BT v1.2

fixed:
- sudden audio switch on charging / phone wake: the a2dp switch and
  chat stream routing now happen only while something is playing -
  silent connects change nothing, sound moves the audio when it comes.
- reconnect storm: 3 connect/drop hops in 2 minutes stand the watcher
  down for 10 minutes (one quiet notice, no reconnect races, no
  profile changes, no popup spam), then it picks itself back up.
- reconnect backoff: a connect that drops again no longer resets the
  attempt counter - only a link that held clears it.

added:
- nothing else. third-party pairing docs removed by request; the
  on/off/release contract test stays.

## Maid BT v1.1

added:
- dock-aware: buds sitting in the charging case stand down (no retry
  storms); opening the lid reconnects.
- smart fallback: on dock, audio hands back to the previous output.
  music keeps playing through the move.
- Soundcore device control: battery, ANC and 10-band EQ written on the
  buds - clean-room Python port of the OpenSCQ30 protocol (MIT).
- our own settings window (Earbuds / Behavior / Equalizer / About) and
  phone-side switching commands over KDE Connect (maid-switch).
- model database: ~40 brands with codes and quirks; `maid-watcher
  model` CLI, auto-recognize via the live bluez alias.
- "Maid BT Helper" GUI: checks, safe fixes, reversible LDAC pin,
  shareable report.
- live config: the watcher re-reads config.json on change;
  `maid-bt-config apply` flips saver / laptop mode without a restart.
- applet shows which side has the audio, wider popup, symbolic icons.

fixed:
- applet flicker on chatty adapters; tooltip clipping.
- a2dp watchdog re-asserts a dead transport instead of leaving the
  card silent until a manual profile flip.
- rfkill: pkexec fallback rescues a soft-blocked radio; missing rfkill
  in the service PATH handled honestly.
- codec ladder: LDAC dropped by default (Realtek LDAC adapters stall)
  - AAC / SBC-XQ offered; the max-quality pin stays opt-in.
- volume resume returns the buds to their last level; controllers
  (DualSense on bluetooth and friends) are never grabbed as headsets.

## gui wording

- the applet describes itself with its gui parts now: "A Linux-only
  Bluetooth earbuds switcher - tray applet + helper window".
  same wording on the repo description. nothing in behavior changed.

## Maid BT v1.0

- first stable release. the applet is a compact Plasma 6 tray menu for
  moving earbuds between this PC, the phone, other devices, and off.
- the Configure dialog now has Earbuds and Behavior pages instead of
  only Keyboard Shortcuts and About. Earbuds covers paired-device
  selection, MAC, name, fallback speakers picked from the running audio
  server (PipeWire or PulseAudio), auto-reconnect, preferred profile,
  app pause/resume, LDAC lock, and multipoint. Behavior covers retry
  timings, adapter recovery, calls, battery warnings, idle saver,
  laptop mode, mic routing, fallback grab, and BT fallback.
- `maid-bt-config` writes settings directly and atomically, with MAC,
  sink and range validation, so users never edit
  `bluetooth-buds.conf` or `config.json` by hand.
- panels no longer clip the action tooltips; the strings are shorter.
- metadata is 1.0 (first stable release).

## development notes

### settings pages

- the applet's Configure dialog now has real Earbuds and Behavior pages
  instead of only Keyboard Shortcuts and About. Earbuds covers MAC,
  display name, fallback speakers, auto-reconnect, preferred profile,
  app pause/resume, LDAC lock, and multipoint. Behavior covers retry
  timings, adapter recovery, calls, battery warnings, idle saver,
  laptop mode, mic routing, fallback grab, and BT fallback.
- changes are written by `maid-bt-config` to
  `~/.config/bluetooth-buds.conf` and
  `~/.config/maid-watcher/config.json` atomically, with validation
  (MAC, sink name, ranges) so the dialog cannot leave a broken config.
- the config pages save as you change a value; the dialog's Apply/OK
  also flushes the current values. Reload re-reads the files.
- settings pages are part of the v1.0 release.

### redesign update

- the panel popup is now a compact, native Plasma menu: a live status
  header, native hover/selection backgrounds, and four clear choices:
  This PC, Phone, Other devices, and Off. it sizes to its content and
  leaves the popup's own translucent theme background alone, so light,
  dark, and translucent themes all work.
- "Other devices" replaces the old "Radio only" label: it powers the
  Bluetooth radio on without grabbing the earbuds or moving audio, so a
  controller, mouse, or keyboard can connect while the buds stay put.
- hover explanations and a settings button to the existing configuration
  dialog make the deeper options reachable from the menu.
- the applet is now named Maid BT and describes itself in About as
  "A Linux-only Bluetooth earbuds switcher"; metadata was 1.1
  during the redesign and is 1.0 for the first stable release. the
  license is MIT.

## kdeconnectd early-login fix moved to Maid Helper

- the version-specific patch no longer travels in this repo. Maid
  Helper's `kdeconnect` doctor installs a user-level platform-fallback
  wrapper that works across KDE Connect versions and survives package
  updates: `maid-helper --only kdeconnect --fix`.
- no KDE Connect source patch is shipped anywhere now; Maid Helper's
  wrapper is the only fix, so a future KDE Connect update cannot
  collide with a stale patch.
- the installer now reports the detected Plasma, Frameworks, Qt and
  KDE Connect versions, and skips the plasmoid on Plasma older than 6.

## fallback sink honesty

- the fallback sink is stored as a name, never a pulse index: indexes
  are assigned per session and go stale, which used to make the park
  fail silently (audio just stopped). the daemon now warns at start
  when the config holds a bare number, checks the sink is really there
  before parking, and logs it when it can't. the installer resolves a
  typed index to the current name instead of writing it down.
- the systemd units carve out `~/MaidLogs` for the audit trail: it was
  silently dead inside their read-only sandbox (daemon and notification
  menu both).

## intent listener audit

- full auth review of the port 8899 listener: token required on every
  endpoint (header preferred, query legacy), constant-time compare,
  fail-closed with no token file, fixed action allowlist, no shell,
  no query in logs, sandboxed unit. added a 60 s per-connection
  socket cap and a `MAID_INTENT_PORT` override so the suite tests
  auth live (bad token 403, both token paths, unknown 404, no leaks).
- installer only mints the token when missing, so a running daemon
  never goes stale.

## dual-connection buds

- opt-in `MULTIPOINT=1` in `bluetooth-buds.conf`: `release` (and the
  phone intents behind it) parks the PC for 8h instead of 20 min, so
  dual-link buds share phone+PC all day without the daemon fighting
  the phone. explicit `on` cancels anytime. single-link behavior
  unchanged. (Bluetooth can't see the phone-side link, so this is a
  tell-it-once flag, not auto-detection.)

## max-quality audio

- opt-in `52-bt-max-quality.conf` (installer offers it): pins the A2DP
  codec ladder LDAC > AAC > SBC-XQ > SBC and unlocks high-bitpool
  SBC-XQ, so fallbacks land closer to LDAC than stock SBC.
- opt-in `QUALITY_LOCK=1` in `bluetooth-buds.conf`: the switcher and
  the fallback daemon pin LDAC (`a2dp-sink`) after every switch and
  restore it on mid-session downgrades. never touches HSP/HFP calls.
- the lock also rescues HSP stuck states with a free mic (post-restart
  silence): switches to LDAC only when no app captures the BT mic.
- fixed: `BATTERY_BOOST=1` from the conf is honored again (the default
  assignment used to clobber it, so the opt-in never took effect).

## installer fixes

- backups only on real change: the compare now runs against the
  rewritten file content, so reinstalls no longer pile up
  `.bak-<timestamp>` copies of every desktop file.
- `--uninstall` honors `--prefix`/`DESTDIR`: program files come out of
  the same `BINDIR`/`SHAREDIR`/`SYSDDIR` the install used.
- shipped example config is placeholder-only again (`Buds 1`, no real
  product names); the personal-data test is now case-insensitive so
  variants can't slip through.

## Linux Mint support

- PulseAudio fallbacks across the audio layer (card lookup, profiles,
  streams, mute, activity detect) for Mint / older stacks without
  PipeWire tools.
- older BlueZ tolerated: missing battery/HFP-wideband degrades
  silently, SBC always available as the mandatory codec.

## wifi-to-bluetooth phone fallback

- opt-in `bt_fallback`: when no paired phone is reachable over wifi,
  the watcher offers the Bluetooth-tethering path (Retry /
  Bluetooth-instead actions) and, once a bnep link appears, refreshes
  KDE Connect so calls, intents and sharing resume over Bluetooth.
  needs KDE Connect to know the phone is gone; never grabs blindly.

## chat routing fix

- Discord/Vesktop playback stranded off the default sink gets moved
  back automatically (on connect + every cycle). microphone routing is
  never touched. `route_comms.enabled` (default on) opts out.

## phone-down fallback

- opt-in `fallback_grab`: when no paired phone is reachable and a
  managed device sits disconnected, the watcher grabs it back instead
  of waiting for a manual switch. off by default; needs KDE Connect
  to know the phone is actually gone (no kdeconnect = never grabs
  blindly).

## systemd-native watcher + actionable notifications

- Maid Watcher installs as a supervised systemd user unit
  (`maid-watcher.service`: Restart=on-failure, journal logging,
  hardened like the other units) when systemd is present; XDG
  autostart remains the fallback on OpenRC/runit.
- the "giving up reconnect" notification now has a Reconnect-now
  action button instead of being a dead end.

## laptop mode + reconnect safety

- Maid Watcher detects laptop chassis over DMI and uses gentler radio
  timing there (longer backoff, fewer attempts); `laptop.mode` forces
  `auto`/`on`/`off`. `maid-watcher status` shows chassis + mode.
- documented: reconnect "give up" is a safety valve (stops hammering
  BlueZ/the phone, notifies, restarts on the next disconnect event).

## audio delay tuning

- new opt-in `wireplumber/51-bt-no-suspend.conf`: kills the ~1s
  late-start after silence by never suspending BT nodes (costs earbud
  battery, hence opt-in). installer offers it, removes it on uninstall.
- `maid-watcher status` now shows the live A2DP profile (codec) so
  lip-sync lag can be matched to a player-side A/V offset.
- profile enforcement retries twice on slow card appearance, shrinking
  the switch gap.

## Maid Watcher update

- new optional `watcher/` daemon (`maid-watcher`, XDG-autostarted,
  init-independent): KDE Connect call handling (pause media, mute
  Discord/Vesktop, restore on hangup + safety timeout), up to 2
  prioritized devices with backoff reconnect, BlueZ battery
  low/critical notifications, opt-in idle saver.
- installer offers Maid Watcher autostart (default off), installs its
  python dbus/gi deps, writes `~/.config/maid-watcher/config.json`
  once, and removes all of it on `--uninstall`.
- plays nice with warm-link: acts only on real disconnects, A2DP
  enforcement is a no-op when the profile already matches.

## systemd only for now

- installer skips service setup on non-systemd init with a warning
  instead of failing weirdly. fork it and wire your own init if you
  want - scripts don't care, only autostart does.

## any headset grabs audio

- any newly connected bluetooth headset takes the audio, not just
  yours - no manual switching. yours connect first, other paired
  headsets get priority connects when yours are down (radio on,
  hands-off off). yours still win when they show up, hands-off silences
  all of it, yanked devices park on fallback, and the buds timer pauses
  while a foreign headset owns it so fallback never steals mid-listen.

## radio mode + app pause/resume cycle

- new `radio` action: powers the radio for other devices, grabs nothing,
  moves no audio, daemon stays hands-off 8h. `on` cancels. widget button
  + phone-button row included.
- switches now pause Playing chromium/electron apps over MPRIS and
  resume only those after the move (their web-audio stalls across BT
  renegotiation otherwise). opt out with `APP_CYCLE=0`. never pauses on
  fallback/lock parks - music keeps flowing to speakers.

## intent + installer hardening

- intent server never logs query strings anymore, so a `?token=` can
  never land in the journal. new preferred auth: `X-Token` header
  (query still works for old macros).
- installer no longer enables bt-intent by default - opt-in prompt,
  off for non-interactive runs. core switching never touches network.
- token file created with umask 077 (never 644, even briefly); warns
  instead of silently failing without python3.
- kdeconnect moved to optional (best-effort, tolerated if missing).
- `install.sh --uninstall` actually exists now (was header-only).
- sink values validated before writing the conf (no code injection
  through a crafted FALLBACK_SINK).
- `sed` home rewrite survives `&` in $HOME.
- systemd units hardened (NoNewPrivileges, ProtectSystem=strict,
  ProtectHome read-only, PrivateTmp, address families) - verified live,
  watcher + intent server both healthy after.

## phone integration hardening

- intent server no longer logs query strings, so a legacy `?token=`
  can never land in the journal. new preferred auth: `X-Token` header
  (never logged); query auth still accepted for old macros.
- installer no longer enables `bt-intent.service` by default - opt-in
  prompt at install, off for non-interactive runs. core switching is
  fully local and unaffected.

## battery boost (buds-fallback.sh)

- watcher reads earbuds battery over BlueZ (`Battery Percentage`) and
  matches the A2DP codec to it: 75%+ LDAC, 45%+ AAC, 15%+ SBC-XQ,
  below that SBC. check every 60s, at most one switch per 3 min,
  never touches the profile mid-call (HSP/HFP left alone).
- **off by default** (`BATTERY_BOOST=0`). turning it on means transport
  teardowns on purpose, and on some plasmashell builds any A2DP
  teardown segfaults the audio thread (`spa.bluez5: Failure ...` →
  `QAudioContext` SIGSEGV - seen live here). flip it to 1 only if your
  desktop survives a manual profile switch:
  `pactl set-card-profile bluez_card.<AA_BB_CC_DD_EE_FF> a2dp-sink-aac`
  then back, with no crash. if it crashes, leave it 0 - warm link +
  no teardowns is the whole crash strategy of this package.
