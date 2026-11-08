#!/usr/bin/env bash
# demo.sh - preview the Maid BT installer exactly the way a fresh user
# experiences it, inside a throw-away home. the real world is shimmed
# out so a demo can never touch anything that matters:
#   sudo / package managers / systemctl / pkexec  -> answer 0, do nothing
#   bluetoothctl / rfkill                         2026252 fake paired buds
#   pactl                                         2026252 fake speakers+dac
# two views:
#   bash tests/demo.sh            piped one-liner experience, printed here
#   bash tests/demo.sh --window   interactive TUI in a terminal window
#                                 (ghostty/konsole/kitty/... auto-detected)
# the sandbox home is deleted when the demo exits (Ctrl-C is safe too).
set -u

DEMO_ROOT="$(mktemp -d /tmp/maidbt-demo-home.XXXXXX)"
trap 'rm -rf "$DEMO_ROOT"' EXIT
PKGDIR="$(cd "$(dirname "$0")/.." && pwd)"

export HOME="$DEMO_ROOT/home"
mkdir -p "$HOME/.config" "$HOME/.local/share" "$HOME/.cache" "$HOME/.local/state"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# ------------------------------------------------------------- shims
SHIM="$DEMO_ROOT/shims"
mkdir -p "$SHIM"
noop() { printf '#!/bin/sh\nexit 0\n' > "$SHIM/$1"; chmod +x "$SHIM/$1"; }

for c in systemctl sudo pkexec rfkill notify-send gamemoded kreadconfig6; do
  noop "$c"
done
for c in pacman apt-get dnf zypper; do
  printf '#!/bin/sh\necho "(demo) %s would run here; sandbox says ok"\nexit 0\n' "$c" > "$SHIM/$c"
  chmod +x "$SHIM/$c"
done
printf '#!/bin/sh\ncase "${1:-}" in\n  devices) echo "Device 04:0C:29:DE:AD:17 Maid Buds Pro" ;;\n  info) echo "\tPaired: yes" ;;\nesac\nexit 0\n' > "$SHIM/bluetoothctl"
chmod +x "$SHIM/bluetoothctl"
printf '#!/bin/sh\ncase "$1 $2" in\n  "info  ") echo "Default Sink: demo-motherboard-dac" ;;\n  "list short sinks") printf "42\\tdemo-motherboard-dac\\tdaudio\\trunning\\n63\\tbluez_sink.04_0C_29_DE_AD_17\\ta2dp_sink\\tsuspended\\n" ;;\nesac\nexit 0\n' > "$SHIM/pactl"
chmod +x "$SHIM/pactl"
export PATH="$SHIM:$PATH"

# ------------------------------------------------------------- views
window() {
  # spawn "$@" inside the default terminal, best effort
  local self; self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  local tl=""
  for c in "${MAID_DEMO_TERMINAL:-}" "${TERMINAL:-}" "${TERM_PROGRAM:-}" \
           ghostty konsole kitty alacritty wezterm gnome-terminal xterm; do
    [ -n "$c" ] && command -v "$c" >/dev/null 2>&1 && { tl="$c"; break; }
  done
  [ -n "$tl" ] || { echo "no terminal found - set MAID_DEMO_TERMINAL=konsole (etc)"; return 1; }
  echo "· demo TUI opening in $tl (sandbox: $DEMO_ROOT/home)"
  case "$tl" in
    konsole)        nohup konsole -e "$self" --tui-child >/dev/null 2>&1 & ;;
    kitty)          nohup kitty "$self" --tui-child >/dev/null 2>&1 & ;;
    alacritty)      nohup alacritty -e "$self" --tui-child >/dev/null 2>&1 & ;;
    wezterm)        nohup wezterm start -- "$self" --tui-child >/dev/null 2>&1 & ;;
    ghostty)        nohup ghostty -e "$self" --tui-child >/dev/null 2>&1 & ;;
    gnome-terminal) nohup gnome-terminal -- "$self" --tui-child >/dev/null 2>&1 & ;;
    xterm)          nohup xterm -e "$self" --tui-child >/dev/null 2>&1 & ;;
    *) echo "no exec recipe for $tl"; return 1 ;;
  esac
}

if [ "${1:-}" = "--window" ]; then window; exit 0; fi

if [ "${1:-}" = "--tui-child" ]; then
  # child end of --window: banner, then the real TUI, then a friendly hold
  printf '\n  %sMAID BT demo%s - sandbox home: %s\n' "\e[1m" "\e[0m" "$HOME" >&2
  printf '  sudo, packages, systemctl, bluez and pactl are demo shims.\n' >&2
  printf '  poke the menu, try 3 (doctor), then q.\n\n' >&2
  bash "$PKGDIR/bin/tui-install.sh"
  printf '\n[demo done - this window is throw-away]\n'
  exit 0
fi

# ---------------------------------------------------- piped experience
# the exact one-liner output a new user sees (packages skipped here so
# the demo never needs sudo for real)
printf '· a fresh user runs: bash <(curl -fsSL .../Maid-BT/main/install.sh)\n'
printf '· demo home: %s\n\n' "$HOME"
bash "$PKGDIR/install.sh" --no-packages </dev/null
printf '\n· nothing above touched your real home; sandbox: %s\n' "$HOME"
printf '· want --verbose (full per-file list), --packages flow, or the TUI? bash tests/demo.sh --window\n'
