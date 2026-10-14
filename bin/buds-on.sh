#!/usr/bin/env bash
# buds-on: single command to power BT on + auto-connect earbuds + route audio.
# Wrapper around bluetooth-toggle.sh so there is exactly one implementation.
set -u
_here="$(cd "$(dirname "$0")" && pwd)"
BIN="$_here/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="$HOME/.local/bin/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="/usr/bin/bluetooth-toggle.sh"
exec "$BIN" on
