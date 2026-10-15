#!/usr/bin/env bash
# Bluetooth on/off switch that actually sticks + auto audio routing.
#
#   on  = rfkill unblock + power on + auto-connect your earbuds
#         + switch default sink to buds
#   off = disconnect buds + park default audio on fallback sink
#         + move streams off bluez + power off + rfkill block
#   release = park on fallback, keep link warm (instant switch-back, anti-crash),
#         PC stays hands-off ~20 min (hand buds to the phone; `on` cancels)
#   radio = power the radio on only: no grab, no audio moves (buds stay
#         put, e.g. controller/mouse use). daemon stays hands-off 8h.
#
# Usage: bluetooth-toggle.sh [on|off|release|radio|toggle|status]   (default: toggle)
# No sudo needed. Wired controllers are unaffected (inputplumber/joycond keep
# running — only the radio follows this switch).

set -o pipefail
# audit trail: journal + ~/MaidLogs (visible folder, see install summary)
_here_bt="${0%/*}"
case "$_here_bt" in "$0") _here_bt="." ;; esac
for _alib in "$_here_bt/audit-lib.sh" "$HOME/.local/bin/audit-lib.sh" \
            "/usr/bin/audit-lib.sh"; do
  if [ -z "${AUDIT_LIB_LOADED:-}" ] && [ -f "$_alib" ]; then
    . "$_alib"
    break
  fi
done
unset _here_bt _alib
# old installs lack audit-lib.sh: degrade to silent no-op, never crash
command -v maid_audit >/dev/null 2>&1 || maid_audit() { :; }
command -v need >/dev/null 2>&1 || need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 2; }; }
need bluetoothctl "bluez package"
need pactl "pulseaudio-utils / libpulse package"
RFKILL="$(command -v rfkill 2>/dev/null || { [ -x /usr/sbin/rfkill ] && echo /usr/sbin/rfkill; } || { [ -x /sbin/rfkill ] && echo /sbin/rfkill; } || echo rfkill)"
ACTION="${1:-toggle}"

BUDS_MAC="AA:BB:CC:DD:EE:FF"
FALLBACK_SINK=""
APP_CYCLE=1
QUALITY_LOCK=0
# Fill these via ~/.config/bluetooth-buds.conf (install.sh prompts for them):
#   BUDS_MAC="..." and FALLBACK_SINK="..."
# Opt out of the app pause/resume cycle with: APP_CYCLE=0
# Pin LDAC after every switch (needs LDAC headset) with: QUALITY_LOCK=1
[ -f "$HOME/.config/bluetooth-buds.conf" ] && . "$HOME/.config/bluetooth-buds.conf"
command -v validate_conf >/dev/null 2>&1 && validate_conf
CONNECT_TIMEOUT=20   # seconds to retry bluetoothctl connect
SINK_WAIT=15         # seconds to wait for bluez sink to appear
MARKER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bt-toggle-manual"
mark_manual() { touch "$MARKER" 2>/dev/null || true; }
HANDS="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bt-hands-off"
HANDS_SECS=1200  # release-to-phone window (20 min); explicit `on` clears it early
clear_hands() { rm -f "$HANDS" 2>/dev/null || true; }
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

notify_phone() {
  # best-effort message to the first reachable phone (silent when unpaired)
  command -v kdeconnect-cli >/dev/null 2>&1 || return 0
  local dev
  dev=$(kdeconnect-cli -a --id-only 2>/dev/null | head -n 1)
  [ -n "$dev" ] || return 0
  kdeconnect-cli -d "$dev" --ping-msg "$1" >/dev/null 2>&1 || true
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Bluetooth" -u "${3:-normal}" -i "${4:-bluetooth}" "$1" "$2"
  else
    kdialog --passivepopup "$1 $2" 5 2>/dev/null || echo "$1 $2"
  fi
}

is_blocked() { $RFKILL list bluetooth 2>/dev/null | grep -qi "soft blocked: yes"; }
is_powered() { bluetoothctl show 2>/dev/null | grep -qi "powered: yes"; }
is_buds_connected() { bluetoothctl info "$BUDS_MAC" 2>/dev/null | grep -q "Connected: yes"; }

bluez_sink() {
  pactl list short sinks 2>/dev/null | grep -i "bluez" | awk '{print $2}' | head -n 1
}

move_all_to() {
  local target="$1"
  [ -z "$target" ] && return 0
  pactl list short sink-inputs 2>/dev/null | awk '{print $1}' | while read -r sid; do
    pactl move-sink-input "$sid" "$target" 2>/dev/null || true
  done
}

bluez_sink_id() {
  # short sink-inputs list sinks by numeric id, not name — resolve it
  pactl list sinks 2>/dev/null | awk '/^Sink #/{gsub(/#/,"",$2); id=$2} /Name: / && /bluez/ {print id; exit}'
}

move_bluez_to_fallback() {
  # move only streams currently on a bluez sink back to fallback
  local bid
  bid=$(bluez_sink_id)
  pactl list short sink-inputs 2>/dev/null | awk -v b="${bid:-}" '$2 == b || $2 ~ /bluez/ {print $1}' | while read -r sid; do
    [ -n "$sid" ] && pactl move-sink-input "$sid" "$FALLBACK_SINK" 2>/dev/null || true
  done
}

suspend_bluez_sink() {
  pactl list short sinks 2>/dev/null | grep -i "bluez" | awk '{print $2}' | while read -r s; do
    pactl suspend-sink "$s" 1 2>/dev/null || true
  done
}

park_on_fallback() {
  pactl set-default-sink "$FALLBACK_SINK" 2>/dev/null || echo "warn: set-default-sink $FALLBACK_SINK failed"
  move_bluez_to_fallback
  suspend_bluez_sink
  # streams may still be creating; one more pass after a beat
  sleep 1
  move_bluez_to_fallback
}

switch_to_buds() {
  local waited=0 sink=""
  # re-acquire A2DP if a previous off-cycle left the card on profile off
  local c active
  for c in $(pactl list short cards 2>/dev/null | grep -i "bluez" | awk '{print $2}'); do
    active=$(pactl list cards 2>/dev/null | awk -v card="$c" 'index($0, card) {f=1} f && /Active Profile:/ {print; exit}')
    case "$active" in
      *": off"*) pactl set-card-profile "$c" a2dp-sink 2>/dev/null || true ;;
    esac
  done
  while [ "$waited" -lt "$SINK_WAIT" ]; do
    sink="$(bluez_sink)"
    [ -n "$sink" ] && break
    sleep 1
    waited=$((waited + 1))
  done
  sink="$(bluez_sink)"
  if [ -n "$sink" ]; then
    pactl set-default-sink "$sink" 2>/dev/null && \
      echo "Default sink -> $sink" || echo "warn: set-default-sink $sink failed"
    pactl suspend-sink "$sink" 0 2>/dev/null || true
    move_all_to "$sink"
    enforce_quality
    return 0
  else
    echo "warn: connected but no bluez sink appeared within ${SINK_WAIT}s (PipeWire/bluez delay?)"
    return 1
  fi
}

current_profile() {
  local card="bluez_card.${BUDS_MAC//:/_}"
  pactl list cards 2>/dev/null | awk -v c="$card" 'index($0, c) {f=1} f && /Active Profile:/ {sub(/.*Active Profile: /, ""); print; exit}'
}

enforce_quality() {
  # quality lock (opt-in): pin A2DP to LDAC. manual run = explicit
  # intent, so no cooldown. HSP/HFP with a live BT mic means a call:
  # hands off. HSP with a free mic means stuck: rescue to LDAC.
  [ "${QUALITY_LOCK:-0}" = "1" ] || return 0
  local cur card
  cur=$(current_profile)
  case "$cur" in
    "a2dp-sink"|"") return 0 ;;
    headset*|handsfree*)
      bt_mic_in_use && return 0
      card="bluez_card.${BUDS_MAC//:/_}"
      if pactl set-card-profile "$card" a2dp-sink 2>/dev/null; then
        echo "Quality lock rescued HSP -> LDAC (mic free)"
      fi
      return 0 ;;
    a2dp*)
      card="bluez_card.${BUDS_MAC//:/_}"
      if pactl set-card-profile "$card" a2dp-sink 2>/dev/null; then
        echo "Quality lock -> LDAC (was $cur)"
      fi ;;
  esac
}

bt_mic_in_use() {
  # true when any recording stream captures from a bluetooth mic.
  # herestring keeps the loop in this shell so return works.
  local idxs sidx sname srcs
  idxs=$(pactl list source-outputs 2>/dev/null | sed -n 's/^\tSource: //p')
  [ -n "$idxs" ] || return 1
  srcs=$(pactl list short sources 2>/dev/null) || return 1
  while read -r sidx; do
    [ -n "$sidx" ] || continue
    sname=$(echo "$srcs" | awk -v i="$sidx" '$1==i {print $2}')
    case "$sname" in *bluez*) return 0 ;; esac
  done <<< "$idxs"
  return 1
}

connect_buds() {
  # make sure future power-ons want this device
  bluetoothctl trust "$BUDS_MAC" >/dev/null 2>&1 || true
  if is_buds_connected; then
    echo "Already connected to $BUDS_MAC."
    return 0
  fi

  echo "Connecting to earbuds ($BUDS_MAC)..."
  local waited=0 ok=0
  while [ "$waited" -lt "$CONNECT_TIMEOUT" ]; do
    if bluetoothctl connect "$BUDS_MAC" 2>&1 | grep -qiE "connection successful|already connected"; then
      ok=1
      break
    fi
    is_buds_connected && { ok=1; break; }
    sleep 2
    waited=$((waited + 2))
    is_buds_connected && { ok=1; break; }
  done

  if [ "$ok" = "1" ] || is_buds_connected; then
    echo "Earbuds connected."
    return 0
  else
    echo "Connect failed/timed out after ${CONNECT_TIMEOUT}s. Is the case open and buds out of case?"
    return 1
  fi
}

do_on() {
  clear_hands  # explicit on cancels any release-to-phone window
  $RFKILL unblock bluetooth 2>&1
  sleep 1
  bluetoothctl power on 2>&1 | tail -n 1
  if ! is_powered; then
    echo "Bluetooth ON requested, but adapter not powered (check dongle/hard block)."
    notify "Bluetooth on?" "Unblocked, but adapter won't power — check hardware switch." critical dialog-error
    return 1
  fi
  echo "Bluetooth ON (unblocked + powered)."
  systemctl --user start buds-fallback.service 2>/dev/null || true

  if connect_buds; then
    media_cycle_start
    switch_to_buds || true
    media_cycle_end
    maid_audit maid-bt "action=on buds connected, audio moved"
    notify "Bluetooth on" "Connected to earbuds." normal bluetooth
    notify_phone "Earbuds switched to PC"
    mark_manual
  else
    maid_audit maid-bt "action=on connect FAILED"
    notify "Bluetooth on" "Powered on, but earbuds didn't connect — open case / wake buds, re-run: bluetooth-toggle.sh on" critical dialog-error
    mark_manual
    return 1
  fi
}

do_release() {
  # release buds to the phone: park PC audio on fallback but KEEP the link up.
  # Warm link = switch-back is an instant PipeWire flip (no BT paging,
  # no profile bring-up) and no transport teardown (anti-crash).
  # Daemon won't re-grab for HANDS_SECS (hands-off).
  echo "Parking audio on fallback sink ($FALLBACK_SINK)..."
  media_cycle_start
  park_on_fallback
  media_cycle_end
  systemctl --user start buds-fallback.service 2>/dev/null || true
  date +%s > "$HANDS" 2>/dev/null || true
  if is_buds_connected; then
    echo "Link stays warm for instant switch-back."
  else
    echo "Buds not on PC right now — PC grabs when free and hands-off lapses."
  fi
  echo "Released (PC stays hands-off $((HANDS_SECS/60)) min; '$0 on' cancels)."
  maid_audit maid-bt "action=release parked on fallback, link warm"
  notify "Earbuds released" "Audio on fallback sink. Use the phone — link stays warm." normal bluetooth-disabled
  notify_phone "Earbuds switched to phone"
  mark_manual
}

do_radio() {
  # radio only: power on for other devices, touch nothing else.
  # daemon stays hands-off 8h so it won't grab the buds.
  $RFKILL unblock bluetooth 2>&1
  sleep 1
  bluetoothctl power on 2>&1 | tail -n 1
  if ! is_powered; then
    echo "Radio ON requested, but adapter not powered."
    notify "Bluetooth on?" "Unblocked, but adapter won't power." critical dialog-error
    mark_manual
    return 1
  fi
  # long hands-off window so the daemon won't grab the buds
  printf '%s %s\n' "$(date +%s)" "28800" > "$HANDS" 2>/dev/null || true
  systemctl --user start buds-fallback.service 2>/dev/null || true
  echo "Radio ON (buds untouched, daemon hands-off 8h; '$0 on' cancels)."
  notify "Bluetooth on" "Radio on for other devices — buds stay put." normal bluetooth
  notify_phone "PC Bluetooth on (radio only)"
  mark_manual
}

do_off() {
  # 1. park audio on fallback sink FIRST (moves + suspends bluez) so no stream
  #    is live when the link drops (bluez errors crash plasmashell audio)
  echo "Parking audio on fallback sink ($FALLBACK_SINK)..."
  media_cycle_start
  park_on_fallback
  media_cycle_end
  echo "Settling PipeWire..."
  sleep 2
  # 2. now drop the buds link (note: any link teardown can crash plasmashell
  #    audio — system bug; prefer `release` for daily use)
  if is_buds_connected; then
    echo "Disconnecting $BUDS_MAC..."
    bluetoothctl disconnect "$BUDS_MAC" 2>&1 | tail -n 1 || true
    sleep 1
  fi

  # 3. power down + block (persists via systemd-rfkill)
  bluetoothctl power off 2>&1 | tail -n 1
  $RFKILL block bluetooth 2>&1
  sleep 1
  if is_blocked; then
    echo "Bluetooth OFF (buds disconnected, audio on fallback, radio blocked)."
    maid_audit maid-bt "action=off parked, radio blocked"
    notify "Bluetooth off" "Earbuds disconnected, audio back on fallback sink." normal bluetooth-disabled
    notify_phone "PC Bluetooth off"
    systemctl --user stop buds-fallback.service 2>/dev/null || true
    mark_manual
  else
    echo "Bluetooth OFF requested, but rfkill block failed."
    maid_audit maid-bt "action=off block FAILED"
    notify "Bluetooth off?" "Audio parked on fallback, but block failed." critical dialog-error
    mark_manual
    return 1
  fi
}

case "$ACTION" in
  on) do_on ;;
  off) do_off ;;
  radio) do_radio ;;
  release) do_release ;;
  status)
    if is_blocked; then echo "Bluetooth: OFF (rfkill blocked)";
    elif is_powered; then echo "Bluetooth: ON (powered)";
    else echo "Bluetooth: OFF (not powered, not blocked)"; fi
    $RFKILL list bluetooth 2>/dev/null
    if is_buds_connected; then echo "Earbuds ($BUDS_MAC): CONNECTED";
    else echo "Earbuds ($BUDS_MAC): disconnected"; fi
    echo "Default sink: $(pactl info 2>/dev/null | grep 'Default Sink')"
    echo "Watcher: $(systemctl --user is-active buds-fallback.service 2>/dev/null)"
    ;;
  toggle)
    if is_blocked || ! is_powered; then do_on; else do_off; fi
    ;;
  porcelain)
    # machine-readable state for the tray widget: off|on|buds
    if is_blocked || ! is_powered; then echo "off";
    elif is_buds_connected; then echo "buds";
    else echo "on"; fi
    ;;
  *) echo "usage: $0 [on|off|release|toggle|status|porcelain]"; exit 2 ;;
esac
