# Usage

## Core commands
```sh
bluetooth-toggle.sh on
bluetooth-toggle.sh release
bluetooth-toggle.sh off
bluetooth-toggle.sh radio
bluetooth-toggle.sh toggle
bluetooth-toggle.sh status
bluetooth-toggle.sh porcelain
bluetooth-toggle.sh --doctor
```

Shortcuts: `buds-on.sh`, `buds-release.sh`, `buds-off.sh`

## Recommended workflow
- **Daily switching:** prefer `release` for quick handoff back to phone
- **Full shutdown:** use `off`/`radio` when needed
- **Diagnostics:** run `--doctor` and `status` when behavior is unexpected

## Optional components
- Background watcher / Maid Watcher daemon for auto-connect, reconnect, battery/call-related behaviors
- Phone remote/listener (opt-in)
- Audio profile/config helpers (warm-link, quality lock, A2DP-only) depending on device/stack behavior and tradeoffs
