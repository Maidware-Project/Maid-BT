#!/usr/bin/env bash
# buds-release: hand earbuds to the phone. PC parks on fallback sink and stays
# hands-off ~20 min. Link stays warm for instant switch-back.
# Cancel early with: bluetooth-toggle.sh on
set -u
_here="$(cd "$(dirname "$0")" && pwd)"
BIN="$_here/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="$HOME/.local/bin/bluetooth-toggle.sh"
[ -x "$BIN" ] || BIN="/usr/bin/bluetooth-toggle.sh"
exec "$BIN" release
