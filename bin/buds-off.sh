#!/usr/bin/env bash
# buds-off: single command to disconnect buds + park audio on fallback sink + BT off.
# Wrapper around bluetooth-toggle.sh so on/off stay in sync.
set -u
_here="$(cd "$(dirname "$0")" && pwd)"
BIN="$_here/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="$HOME/.local/bin/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="/usr/bin/bluetooth-toggle.sh"
exec "$BIN" off
