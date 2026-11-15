# Troubleshooting

## Earbuds connect but audio does not route correctly
- Run `bluetooth-toggle.sh --doctor` and `status`
- Check sinks/cards with `pactl list short sinks` / `pactl list cards short`
- Ensure `FALLBACK_SINK` (if configured) is a sink **name**, not a numeric index
- Some apps may need pause/resume or restart after route/profile changes

## Unstable switching / desktop audio issues
- Prefer `release` instead of `off` for daily handoff
- Avoid rapid repeated toggles; allow reconnect/routing to settle
- Review optional audio configs (warm-link, quality lock, A2DP-only) for your device/stack

## Dual-connection / multipoint quirks
- Configure multipoint-related options if supported by your earbuds
- Behavior varies by device firmware and Linux audio stack; test changes incrementally

## Plasma widget/UI issues
- Plasma applet is KDE-specific; core CLI remains usable elsewhere
- After install/update, refresh/restart Plasma components if the widget does not appear

## More help
- See [`../DEVICE-SUPPORT.md`](../DEVICE-SUPPORT.md) for model-specific notes
- Website guides: https://maidware-project.github.io/guides/
- Report issues with distro, desktop/session, BlueZ/PipeWire versions, device model, and `--doctor` output where possible
