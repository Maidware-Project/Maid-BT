#!/usr/bin/env bash
# bt-notify-menu: persistent Plasma notification card with action buttons.
# The card always reflects live state; clicking a button runs the matching
# bluetooth-toggle.sh action and the card refreshes:
#   radio off          -> [Turn Bluetooth on]
#   buds on PC         -> [Release to phone] [Bluetooth off]
#   radio on, buds away-> [Switch to PC] [Bluetooth off]
# Phone side: KDE Connect run commands (PC only / Phone only / BT Off).
set -u

_here="$(cd "$(dirname "$0")" && pwd)"
BIN="$_here/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="$HOME/.local/bin/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="/usr/bin/bluetooth-toggle.sh"
RFKILL_BIN="$(command -v rfkill 2>/dev/null || { [ -x /usr/sbin/rfkill ] && echo /usr/sbin/rfkill; } || { [ -x /sbin/rfkill ] && echo /sbin/rfkill; } || echo rfkill)"
POLL=2
IDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bt-menu-id"
BUDS_MAC="AA:BB:CC:DD:EE:FF"
# Fill via ~/.config/bluetooth-buds.conf (install.sh prompts for it)
[ -f "$HOME/.config/bluetooth-buds.conf" ] && . "$HOME/.config/bluetooth-buds.conf"
NOTIF_ID=0
[ -f "$IDFILE" ] && NOTIF_ID="$(cat "$IDFILE" 2>/dev/null || echo 0)"

for _alib in "$_here/audit-lib.sh" "$HOME/.local/bin/audit-lib.sh" \
            "/usr/bin/audit-lib.sh"; do
  if [ -z "${AUDIT_LIB_LOADED:-}" ] && [ -f "$_alib" ]; then
    . "$_alib"
    break
  fi
done
unset _alib
command -v maid_audit >/dev/null 2>&1 || maid_audit() { :; }

is_blocked() { "$RFKILL_BIN" list bluetooth 2>/dev/null | grep -qi "soft blocked: yes"; }
is_powered() { bluetoothctl show 2>/dev/null | grep -qi "powered: yes"; }
is_buds_connected() { bluetoothctl info "$BUDS_MAC" 2>/dev/null | grep -q "Connected: yes"; }
default_sink() { pactl info 2>/dev/null | sed -n 's/^Default Sink: //p'; }

short_sink() {
  case "$1" in
    *bluez*) echo "Bluetooth earbuds" ;;
    "") echo "unknown" ;;
    *) desc=$(pactl list sinks 2>/dev/null | awk -v n="$1" 'index($0, n) {f=1} f && /Description: / {sub(/.*Description: /, ""); print; exit}'); [ -n "$desc" ] && echo "$desc" || echo "$1" ;;
  esac
}

post_menu() {
  # $1 summary, $2 body, $3 actions gvariant list
  local out id
  out=$(gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    "Bluetooth" "$NOTIF_ID" "bluetooth" "$1" "$2" "$3" \
    "{'resident': <true>}" 15000 2>/dev/null) || return 1
  id=$(echo "$out" | grep -oE '[0-9]+' | head -n 1)
  [ -n "$id" ] && { NOTIF_ID=$id; echo "$id" > "$IDFILE" 2>/dev/null || true; }
}

dispatch() {
  case "$1" in
    on) "$BIN" on >/dev/null 2>&1 ;;
    release) "$BIN" release >/dev/null 2>&1 ;;
    off) "$BIN" off >/dev/null 2>&1 ;;
  esac
}

# --- action listener (reads live id from file, no stale subshell copy) ---
dbus-monitor --session \
  "type='signal',sender='org.freedesktop.Notifications',interface='org.freedesktop.Notifications',member='ActionInvoked'" \
  2>/dev/null | while read -r line; do
  case "$line" in
    *member=ActionInvoked*) _stage=1 ;;
    *)
      if [ "${_stage:-0}" = "1" ]; then
        case "$line" in
          *uint32*) _gotid=$(echo "$line" | grep -oE '[0-9]+' | head -n 1); _stage=2 ;;
        esac
      elif [ "${_stage:-0}" = "2" ]; then
        case "$line" in
          *string*)
            _key=$(echo "$line" | sed -n 's/.*string "\(.*\)".*/\1/p')
            _stage=0
            _cur=$(cat "$IDFILE" 2>/dev/null || echo -1)
            if [ "$_gotid" = "$_cur" ]; then
              case "$_key" in on|release|off) dispatch "$_key" ;; esac
            fi
            ;;
        esac
      fi
      ;;
  esac
done &
trap 'kill %1 2>/dev/null; exit 0' EXIT INT TERM

# --- state loop: repost card only when something changed ---
last_sig=""
while true; do
  p=0; b=0; c=0
  is_powered && p=1
  is_blocked && b=1
  is_buds_connected && c=1
  sink=$(default_sink)
  sig="$p|$b|$c|$sink"
  if [ "$sig" != "$last_sig" ]; then
    last_sig="$sig"
    if [ "$b" = "1" ] || [ "$p" = "0" ]; then
      post_menu "Bluetooth off" "Radio is off. Output: $(short_sink "$sink")." "['on', 'Turn Bluetooth on']" || true
    elif [ "$c" = "1" ]; then
      post_menu "Earbuds on PC" "Output: $(short_sink "$sink")." "['release', 'Release to phone', 'off', 'Bluetooth off']" || true
    else
      post_menu "Audio on $(short_sink "$sink")" "Bluetooth on, buds away." "['on', 'Switch to PC', 'off', 'Bluetooth off']" || true
    fi
  fi
  sleep "$POLL"
done
