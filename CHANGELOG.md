# changelog

## Maid BT v1.1 (this release)

- dock-aware goes: earbuds inside their charging case go silent (closed
  case powers them off). maid-watcher probes instead of retrying blindly,
  buds-fallback stands down after repeated silent connects, and any
  reconnect re-arms. no more retry storms while the buds are parked.
- smart fallback: "when the buds dock, hand audio to the output used
  before them" (GUI checkbox; falls back to the configured fallback
  speakers when that output is gone). music keeps playing through the
  move now - the pause/resume cycle covers the dock transition, so
  Chromium/Electron apps no longer stall.
- soundcore device control (Liberty 5 family): battery + ANC mode +
  10-band EQ written into the buds' own memory from Maid BT. The wire
  protocol facts come from the GPL OpenSCQ30 project; Maid BT speaks it
  through our own clean-room Python implementation (MIT) - credit and
  details in the About page and README.
- new settings window: gear opens "Maid BT Settings" with exactly the
  Maidware pages (Earbuds / Behavior / Equalizer / About) - no Plasma
  stock "Keyboard Shortcuts" page. Plasma's own dialog still exists in
  the right-click menu and now includes the Equalizer page too.
- model database: full Soundcore family (Q/Life/Space/headphone series
  with device codes), multipoint/codec/case/home-ecosystem quirks for
  ~40 brands; `maid-watcher model "NAME"` CLI; docs/DEVICE-SUPPORT.md
  (generated) lists what is natively supported on Linux.
- phone switching from KDE Connect: the paired device's "run command"
  list gets three bluetooth commands ("Earbuds: audio on PC", "Earbuds:
  audio on phone", "Earbuds: who has audio") backed by bin/maid-switch
  (pc|phone|status), calling the same release/on machinery as the
  applet. existing personal commands in that list are preserved and
  Maid BT config snapshots live in ~/.config/kdeconnect-cmd-backup-*.
- soundcore device control is live end-to-end: real reads (battery/
  firmware/dual connection) and writes (ANC modes, NC strength, preset
  and custom EQ curves) verified against a Liberty 5 on the wire; the
  settings window shows the curve that is actually on the buds and a
  failed read says so honestly instead of showing stale zeros.
- model database lookup understands short aliases ("Liberty 5"
  resolves to "soundcore Liberty 5") - the EQ page no longer shows
  "not supported" for buds whose configured name is the short form.
- bluetooth stability: WirePlumber quality/A2DP-only guards deployed
  with the service, reconnect back-off refinements, battery monitor
  and call watcher cleanups. Toggle actions now survive missing rfkill
  in the systemd user PATH.
- applet state no longer flickers: the porcelain readout collects
  bluetoothctl's output before matching instead of piping into
  `grep -q`. grep exited on the first match, bluetoothctl took
  SIGPIPE, and pipefail turned a good read into "off"/"on" while the
  earbuds were connected. the same race could make a real fallback
  sink look missing during a park. regression test uses a chatty fake
  adapter.
- default codec ladder drops LDAC (wireplumber/52-bt-max-quality.conf
  = [aac sbc_xq sbc]): adapters with the Realtek LDAC stall lose
  packets until quality collapses, so AAC and SBC-XQ are offered
  instead. the max-quality pin stays an explicit opt-in (helper GUI).
- a2dp watchdog in buds-fallback: while buds are connected, a dead
  transport is re-asserted every ~12 ticks instead of leaving the card
  stuck at profile "off" with silence until a manual profile flip.
- settings window fixes: pages hosted in Maid BT's own window render
  correctly again (the switch handler destroyed each freshly-loaded
  page via sourceComponent's last-set-wins rule), page roots use
  host-agnostic ScrollablePage, the EQ strength slider applies on
  release, and the About pane no longer logs undefined-assignment
  errors.
- maid-setup notes the model database quirks (multipoint/LDAC hints)
  into the generated config.

## gui wording

- the applet describes itself with its gui parts now: "A Linux-only
  Bluetooth earbuds switcher - tray applet + helper window".
  same wording on the repo description. nothing in behavior changed.

## Maid BT v1.1

- applet: shows which side owns the audio ("Earbuds: PC · audio here" /
  "Earbuds: phone"), a wider popup so nothing clips, and symbolic Breeze
  icons on the header and tiles.
- Maid BT Helper GUI: checks, safe fixes, one-click LDAC pin
  (reversible), shareable report. installed as the "Maid BT Helper"
  launcher next to the shell.
- live settings: `maid-bt-config apply` takes battery saver and laptop
  mode on the spot (saver = idle park timer, laptop mode = reconnect
  aggressiveness) - no re-run of the watcher needed.
- watcher: re-reads its config on change and applies it live without a
  restart; switch-triggered unwatch/refresh drops stale reconnection
  attempts after phone-side moves.
- sound quality stays stock by default: the max-quality pin is an
  explicit opt-in (installer or helper GUI), and the shell ships with
  no codec forced.

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
