# Compositor snippets (Hyprland / Sway / i3)

Maid BT’s **core CLI** (`bluetooth-toggle.sh`, `maid-switch`) is compositor-agnostic. The Plasma applet is KDE-only. These snippets are **examples** — adjust paths/keys to taste.

## Keybind examples
- Hyprland (`~/.config/hypr/hyprland.conf`):
  - `bind = SUPER, B, exec, ~/.local/bin/bluetooth-toggle.sh toggle`
  - `bind = SUPER SHIFT, B, exec, ~/.local/bin/bluetooth-toggle.sh release`
- Sway/i3 (`~/.config/sway/config` or `~/.config/i3/config`):
  - `bindsym $mod+b exec ~/.local/bin/bluetooth-toggle.sh toggle`
  - `bindsym $mod+Shift+b exec ~/.local/bin/bluetooth-toggle.sh release`

## Waybar custom module (example)
Use `bluetooth-toggle.sh porcelain` for a stable status token (`on`/`off`/`buds`/etc., best-effort) and toggle on click:

```jsonc
"custom/maidbt": {
  "exec": "~/.local/bin/bluetooth-toggle.sh porcelain",
  "interval": 5,
  "on-click": "~/.local/bin/bluetooth-toggle.sh toggle",
  "on-click-right": "~/.local/bin/bluetooth-toggle.sh release"
}
```

Notes: requires bluez/pactl and your `~/.config/bluetooth-buds.conf` (run `maid-setup.sh` / installer). Test on your compositor; report issues with `bluetooth-toggle.sh --doctor` output.
