# changelog

## installer fixes

- backups only on real change: the compare now runs against the
  rewritten file content, so reinstalls no longer pile up
  `.bak-<timestamp>` copies of every desktop file.
- `--uninstall` honors `--prefix`/`DESTDIR`: program files come out of
  the same `BINDIR`/`SHAREDIR`/`SYSDDIR` the install used.

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
  want — scripts don't care, only autostart does.

## any headset grabs audio

- any newly connected bluetooth headset takes the audio, not just
  yours — no manual switching. yours connect first, other paired
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
  fallback/lock parks — music keeps flowing to speakers.

## intent + installer hardening

- intent server never logs query strings anymore, so a `?token=` can
  never land in the journal. new preferred auth: `X-Token` header
  (query still works for old macros).
- installer no longer enables bt-intent by default — opt-in prompt,
  off for non-interactive runs. core switching never touches network.
- token file created with umask 077 (never 644, even briefly); warns
  instead of silently failing without python3.
- kdeconnect moved to optional (best-effort, tolerated if missing).
- `install.sh --uninstall` actually exists now (was header-only).
- sink values validated before writing the conf (no code injection
  through a crafted FALLBACK_SINK).
- `sed` home rewrite survives `&` in $HOME.
- systemd units hardened (NoNewPrivileges, ProtectSystem=strict,
  ProtectHome read-only, PrivateTmp, address families) — verified live,
  watcher + intent server both healthy after.

## phone integration hardening

- intent server no longer logs query strings, so a legacy `?token=`
  can never land in the journal. new preferred auth: `X-Token` header
  (never logged); query auth still accepted for old macros.
- installer no longer enables `bt-intent.service` by default — opt-in
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
  `QAudioContext` SIGSEGV — seen live here). flip it to 1 only if your
  desktop survives a manual profile switch:
  `pactl set-card-profile bluez_card.<AA_BB_CC_DD_EE_FF> a2dp-sink-aac`
  then back, with no crash. if it crashes, leave it 0 — warm link +
  no teardowns is the whole crash strategy of this package.
