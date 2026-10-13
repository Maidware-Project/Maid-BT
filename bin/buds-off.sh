#!/usr/bin/env bash
# buds-off: single command to disconnect buds + park audio on fallback sink + BT off.
# Wrapper around bluetooth-toggle.sh so on/off stay in sync.
set -u
exec "$HOME/.local/bin/bluetooth-toggle.sh" off
