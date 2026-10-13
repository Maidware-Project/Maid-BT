#!/usr/bin/env bash
# buds-release: hand earbuds to the phone. PC parks on fallback sink and stays
# hands-off ~20 min. Link stays warm for instant switch-back.
# Cancel early with: bluetooth-toggle.sh on
set -u
exec "$HOME/.local/bin/bluetooth-toggle.sh" release
