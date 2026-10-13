#!/usr/bin/env bash
# buds-on: single command to power BT on + auto-connect earbuds + route audio.
# Wrapper around bluetooth-toggle.sh so there is exactly one implementation.
set -u
exec "$HOME/.local/bin/bluetooth-toggle.sh" on
