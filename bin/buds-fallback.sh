#!/usr/bin/env bash
# buds-fallback v2: seamless plug-and-play. Radio stays on; buds reconnect on
# case-open and audio follows automatically:
#   buds appear -> auto-connect your earbuds, default sink to buds, notify
#   buds gone   -> park default audio on fallback sink within seconds, notify,
#                  keep retrying quietly in the background (backoff to 30s)
#
# Manual single commands (instant, no wait):
#   ~/.local/bin/bluetooth-toggle.sh on   (or buds-on.sh)
#   ~/.local/bin/bluetooth-toggle.sh off  (or buds-off.sh)
# This daemon is the safety net for KDE tray clicks (2s delay max).
set -u

BUDS_MAC="AA:BB:CC:DD:EE:FF"
FALLBACK_SINK=""
# Fill these via ~/.config/bluetooth-buds.conf (install.sh prompts for them):
#   BUDS_MAC="..." and FALLBACK_SINK="..."
[ -f "$HOME/.config/bluetooth-buds.conf" ] && . "$HOME/.config/bluetooth-buds.conf"
# Refuse to run unconfigured (placeholder MAC) instead of retry-spamming.
if [ "${BUDS_MAC:-}" = "AA:BB:CC:DD:EE:FF" ] || [ -z "${BUDS_MAC:-}" ]; then
  echo "[buds-fallback] BUDS_MAC not configured - copy bluetooth-buds.conf.example to" >&2
  echo "[buds-fallback] ~/.config/bluetooth-buds.conf and edit it, then restart me." >&2
  sleep 3600
  exit 2
fi
POLL=1
GRACE=6               # seconds disconnected before audio parks on fallback (radio stays on)
CONNECT_RETRY_EVERY=5 # fast retry interval; backs off to 30s after RETRY_BACKOFF_AFTER
RETRY_BACKOFF_AFTER=120 # seconds of continuous loss before backing off retries
FAIL_BACKOFF=30       # quiet period after a failed connect (anti-flap)
FLAP_WINDOW=15        # a connection dying this fast counts as a flap
FLAP_BACKOFF=120      # quiet period after a flap (anti-flap)
BATTERY_BOOST=0       # opt-in: match A2DP codec to buds battery (saves power).
APP_CYCLE=1
# Opt out of the app pause/resume cycle with APP_CYCLE=0 in the conf.
                      # WARNING: any transport teardown can segfault older
                      # plasmashell (QAudioContext). Leave 0 unless your
                      # desktop survives profile switches (test one first).
BATTERY_POLL=60       # seconds between battery checks
BATT_COOLDOWN=180     # min seconds between codec switches (anti-flap)
POWER_OFF_ON_LOST=0   # 0 = seamless mode: radio stays on, buds reconnect on case-open
BLOCK_ON_EXTERNAL_OFF=0 # 1 = also rfkill block when KDE tray powers off (sticky off)
MARKER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bt-toggle-manual"
HANDS="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bt-hands-off"
HANDS_SECS=1200  # release-to-phone window; explicit `on` clears it early

# release-to-phone active? marker holds "epoch [seconds]" (default HANDS_SECS)
hands_off() {
  [ -f "$HANDS" ] || return 1
  local now_s mtime dur
  now_s=$(date +%s)
  read -r mtime dur < "$HANDS" 2>/dev/null || return 1
  [ -n "${mtime:-}" ] || return 1
  dur=${dur:-$HANDS_SECS}
  [ $((now_s - mtime)) -lt "$dur" ]
}

ping_phone() {
  # best-effort message to the first reachable phone (silent when unpaired)
  command -v kdeconnect-cli >/dev/null 2>&1 || return 0
  local dev
  dev=$(kdeconnect-cli -a --id-only 2>/dev/null | head -n 1)
  [ -n "$dev" ] || return 0
  kdeconnect-cli -d "$dev" --ping-msg "$1" >/dev/null 2>&1 || true
}

lost_for=0
did_fallback=0
last_attempt=0
cooldown_until=0
connected_since=0
last_batt_check=0
last_codec_switch=0
prev_powered=""
prev_connected=""
prev_locked=""

is_locked() { qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive 2>/dev/null | grep -qi true; }

log() { echo "[buds-fallback] $*"; }

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Bluetooth" -u "${3:-normal}" -i "${4:-bluetooth}" "$1" "$2"
  else
    kdialog --passivepopup "$1 $2" 5 2>/dev/null || true
  fi
}

# skip our own notify if the manual script just notified (<12s ago) to avoid doubles
manual_recent() {
  [ -f "$MARKER" ] || return 1
  local now mtime
  now=$(date +%s)
  mtime=$(stat -c %Y "$MARKER" 2>/dev/null || echo 0)
  [ $((now - mtime)) -lt 12 ]
}

is_connected() { bluetoothctl info "$BUDS_MAC" 2>/dev/null | grep -q "Connected: yes"; }
is_powered() { bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; }
other_device_connected() { bluetoothctl devices Connected 2>/dev/null | grep -vq "$BUDS_MAC" && bluetoothctl devices Connected 2>/dev/null | grep -q "Device"; }

bluez_sink() { pactl list short sinks 2>/dev/null | grep -i "bluez" | awk '{print $2}' | head -n 1; }

bluez_sink_id() {
  # short sink-inputs list sinks by numeric id, not name — resolve it
  pactl list sinks 2>/dev/null | awk '/^Sink #/{gsub(/#/,"",$2); id=$2} /Name: / && /bluez/ {print id; exit}'
}

move_bluez_to_fallback() {
  local bid
  bid=$(bluez_sink_id)
  pactl list short sink-inputs 2>/dev/null | awk -v b="${bid:-}" '$2 == b || $2 ~ /bluez/ {print $1}' | while read -r sid; do
    [ -n "$sid" ] && pactl move-sink-input "$sid" "$FALLBACK_SINK" 2>/dev/null || true
  done
}

suspend_bluez() {
  # idle the bluez node ASAP so a dying link tears down clean instead of
  # erroring (bluez transport errors segfault plasmashell's QAudioContext)
  pactl list short sinks 2>/dev/null | grep -i "bluez" | awk '{print $2}' | while read -r s; do
    pactl suspend-sink "$s" 1 2>/dev/null || true
  done
}

park_on_fallback() {
  pactl set-default-sink "$FALLBACK_SINK" 2>/dev/null || log "set-default-sink failed"
  move_bluez_to_fallback
  suspend_bluez
  sleep 1
  move_bluez_to_fallback
}

ensure_a2dp() {
  # if a previous off-cycle left the card on profile off, re-acquire A2DP;
  # never touches HSP/HFP (call in progress) or already-active A2DP
  local c active
  for c in $(pactl list short cards 2>/dev/null | grep -i "bluez" | awk '{print $2}'); do
    active=$(pactl list cards 2>/dev/null | awk -v card="$c" 'index($0, card) {f=1} f && /Active Profile:/ {print; exit}')
    case "$active" in
      *": off"*) pactl set-card-profile "$c" a2dp-sink 2>/dev/null || true ;;
    esac
  done
}

switch_to_buds_nowait() {
  local waited=0 sink=""
  ensure_a2dp
  while [ "$waited" -lt 8 ]; do
    sink="$(bluez_sink)"
    [ -n "$sink" ] && break
    sleep 1
    waited=$((waited + 1))
  done
  sink="$(bluez_sink)"
  if [ -n "$sink" ]; then
    pactl set-default-sink "$sink" 2>/dev/null || true
    pactl suspend-sink "$sink" 0 2>/dev/null || true
    pactl list short sink-inputs 2>/dev/null | awk '{print $1}' | while read -r sid; do
      pactl move-sink-input "$sid" "$sink" 2>/dev/null || true
    done
    log "default -> $sink"
  else
    log "connected but no bluez sink yet"
  fi
}

CYCLE_RESUME=""

_mpris_players() { qdbus6 2>/dev/null | grep '^org.mpris.MediaPlayer2\.' | sort -u; }
_mpris_status() { timeout 3 qdbus6 "$1" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlaybackStatus 2>/dev/null; }

media_cycle_start() {
  # pause Playing players so Chromium/Electron apps reopen clean audio
  # on the new sink (their web-audio stack stalls across BT renegotiation)
  [ "${APP_CYCLE:-1}" = "1" ] || return 0
  CYCLE_RESUME=""
  local p st
  while read -r p; do
    [ -n "$p" ] || continue
    st=$(_mpris_status "$p")
    if [ "$st" = "Playing" ]; then
      timeout 3 qdbus6 "$p" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Pause >/dev/null 2>&1 || true
      CYCLE_RESUME="$CYCLE_RESUME $p"
    fi
  done <<EOF
$(_mpris_players)
EOF
  [ -n "$CYCLE_RESUME" ] && sleep 1
}

media_cycle_end() {
  # resume only what we paused (never start paused music)
  [ "${APP_CYCLE:-1}" = "1" ] || return 0
  [ -z "${CYCLE_RESUME:-}" ] && return 0
  sleep 1
  local p
  for p in $CYCLE_RESUME; do
    timeout 3 qdbus6 "$p" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Play >/dev/null 2>&1 || true
  done
  CYCLE_RESUME=""
}

buds_battery() {
  # earbuds battery percent via BlueZ (empty when unknown)
  local hex
  hex=$(bluetoothctl info "$BUDS_MAC" 2>/dev/null | sed -n 's/.*Battery Percentage: 0x\([0-9a-fA-F]*\).*/\1/p' | head -n 1)
  [ -n "$hex" ] && printf '%d' "0x$hex" 2>/dev/null || true
}

codec_for() {
  # bands by drain (heaviest first): LDAC 75+, AAC 45+, SBC-XQ 15+, SBC below
  local b=$1
  if [ "$b" -ge 75 ]; then echo "a2dp-sink"
  elif [ "$b" -ge 45 ]; then echo "a2dp-sink-aac"
  elif [ "$b" -ge 15 ]; then echo "a2dp-sink-sbc_xq"
  else echo "a2dp-sink-sbc"; fi
}

current_profile() {
  local card="bluez_card.${BUDS_MAC//:/_}"
  pactl list cards 2>/dev/null | awk -v c="$card" 'index($0, c) {f=1} f && /Active Profile:/ {sub(/.*Active Profile: /, ""); print; exit}'
}

try_connect_once() {
  log "auto-connect attempt to $BUDS_MAC"
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 bluetoothctl connect "$BUDS_MAC" 2>&1 | tail -n 2 || true
  else
    bluetoothctl connect "$BUDS_MAC" 2>&1 | tail -n 2 || true
  fi
}

log "start (buds=$BUDS_MAC fallback=$FALLBACK_SINK grace=$GRACE power_off=$POWER_OFF_ON_LOST)"

while true; do
  powered=0; connected=0
  now=$(date +%s)
  is_powered && powered=1
  is_connected && connected=1

  # init prev on first loop (no notify for steady state)
  if [ -z "$prev_powered" ]; then
    prev_powered=$powered
    prev_connected=$connected
    [ "$connected" = "1" ] && did_fallback=0 || { [ "$powered" = "0" ] && did_fallback=1; }
  fi

  # --- power transitions (catches KDE tray clicks) ---
  if [ "$powered" = "1" ] && [ "$prev_powered" = "0" ]; then
    log "adapter powered ON (external or script)"
    lost_for=0
    did_fallback=0
    last_attempt=0
    if hands_off; then
      log "hands-off active, skipping auto-connect"
    elif ! manual_recent; then
      notify "Bluetooth on" "Adapter powered on — connecting to earbuds…" normal bluetooth
    fi
  fi

  if [ "$powered" = "0" ] && [ "$prev_powered" = "1" ]; then
    log "adapter powered OFF"
    park_on_fallback
    if [ "$BLOCK_ON_EXTERNAL_OFF" = "1" ]; then
      RFKILL_BIN="$(command -v rfkill 2>/dev/null || { [ -x /usr/sbin/rfkill ] && echo /usr/sbin/rfkill; } || { [ -x /sbin/rfkill ] && echo /sbin/rfkill; } || echo rfkill)"
      "$RFKILL_BIN" block bluetooth 2>/dev/null || true
    fi
    if ! manual_recent; then
      notify "Bluetooth off" "Bluetooth is off — audio back on fallback sink." normal bluetooth-disabled
      ping_phone "PC Bluetooth off"
    fi
    did_fallback=1
    lost_for=0
  fi

  # screen lock: park PC audio on fallback silently (warm link, no teardown).
  # unlock: route back to buds ONLY if they are actively connected.
  locked=0
  is_locked && locked=1
  if [ -z "$prev_locked" ]; then
    prev_locked=$locked
  elif [ "$locked" = "1" ] && [ "$prev_locked" = "0" ]; then
    log "screen locked -> parking audio on fallback (link stays warm)"
    park_on_fallback
  elif [ "$locked" = "0" ] && [ "$prev_locked" = "1" ]; then
    if [ "$connected" = "1" ]; then
      log "screen unlocked, buds connected -> routing back to buds"
      switch_to_buds_nowait
      notify "Welcome back" "Audio back on earbuds." normal bluetooth
    else
      log "screen unlocked, buds away -> staying on fallback"
    fi
  fi
  prev_locked=$locked

  if [ "$connected" = "1" ]; then
    lost_for=0
    if [ "$prev_connected" = "0" ]; then
      log "buds connected"
      connected_since=$now
      media_cycle_start
      switch_to_buds_nowait
      media_cycle_end
      if ! manual_recent; then
        notify "Bluetooth on" "Connected to earbuds." normal bluetooth
        ping_phone "Earbuds switched to PC"
      fi
    fi
    if [ "$did_fallback" = "1" ]; then
      log "buds back, re-armed"
      did_fallback=0
    fi
    # battery boost (opt-in): match codec to buds battery, never during calls
    if [ "$BATTERY_BOOST" = "1" ] && [ $((now - last_batt_check)) -ge "$BATTERY_POLL" ]; then
      last_batt_check=$now
      batt=$(buds_battery)
      if [ -n "$batt" ]; then
        want=$(codec_for "$batt")
        cur=$(current_profile)
        case "$cur" in
          headset*|handsfree*) : ;;  # call in progress: hands off
          "$want") : ;;
          *)
            if [ $((now - last_codec_switch)) -ge "$BATT_COOLDOWN" ]; then
              card="bluez_card.${BUDS_MAC//:/_}"
              if pactl set-card-profile "$card" "$want" 2>/dev/null; then
                last_codec_switch=$now
                log "battery ${batt}% -> codec $want"
                notify "Battery saver" "Earbuds at ${batt}% — codec $want." normal bluetooth
              else
                log "codec switch to $want failed"
              fi
            fi
            ;;
        esac
      fi
    fi
  else
    # disconnected
    if [ "$powered" = "1" ]; then
      lost_for=$((lost_for + POLL))
      # fresh drop: idle the bluez node instantly (clean teardown, anti-crash)
      # and arm a long cooldown if the connection died almost immediately (flap)
      if [ "$prev_connected" = "1" ]; then
        suspend_bluez
        if [ "$connected_since" -ne 0 ] && [ $((now - connected_since)) -lt "$FLAP_WINDOW" ]; then
          log "flap: link lived $((now - connected_since))s, cooling down ${FLAP_BACKOFF}s"
          cooldown_until=$((now + FLAP_BACKOFF))
        fi
        connected_since=0
      fi
      # seamless auto-connect with circuit breaker (anti-flap)
      interval=$CONNECT_RETRY_EVERY
      [ "$lost_for" -ge "$RETRY_BACKOFF_AFTER" ] && interval=30
      next_allowed=$((last_attempt + interval))
      [ "$cooldown_until" -gt "$next_allowed" ] && next_allowed=$cooldown_until
      if ! hands_off && [ "$now" -ge "$next_allowed" ]; then
        last_attempt=$now
        try_connect_once
        is_connected && connected=1
        if [ "$connected" = "1" ]; then
          lost_for=0
          cooldown_until=0
          log "buds connected (via retry)"
          media_cycle_start
          switch_to_buds_nowait
          media_cycle_end
          if ! manual_recent; then
            notify "Bluetooth on" "Connected to earbuds." normal bluetooth
            ping_phone "Earbuds switched to PC"
          fi
          did_fallback=0
        else
          cooldown_until=$((now + FAIL_BACKOFF))
        fi
      fi
      if [ "$connected" = "0" ] && [ "$lost_for" -ge "$GRACE" ] && [ "$did_fallback" = "0" ]; then
        log "buds lost (${lost_for}s) -> default to $FALLBACK_SINK"
        park_on_fallback
        if [ "$POWER_OFF_ON_LOST" = "1" ]; then
          if other_device_connected; then
            log "other BT device connected, leaving radio on"
          else
            log "powering bluetooth off"
            bluetoothctl power off >/dev/null 2>&1 || true
            # power-off transition notify happens next loop; send combined one now
            # if manual didn't just handle it (avoids double when manual off ran)
            if ! manual_recent; then
              notify "Bluetooth off" "Earbuds gone — audio back on fallback sink." normal bluetooth-disabled
              ping_phone "Earbuds disconnected from PC"
            fi
          fi
        else
          if ! manual_recent; then
            notify "Earbuds disconnected" "Audio back on fallback sink." normal bluetooth-disabled
            ping_phone "Earbuds disconnected from PC"
          fi
        fi
        did_fallback=1
      elif [ "$did_fallback" = "1" ]; then
        move_bluez_to_fallback
      fi
    else
      # powered off and disconnected: make sure audio parked (once)
      if [ "$did_fallback" = "0" ]; then
        park_on_fallback
        did_fallback=1
      fi
    fi
  fi

  prev_powered=$powered
  # re-read connected in case retry just connected late
  is_connected && prev_connected=1 || prev_connected=0
  sleep "$POLL"
done
