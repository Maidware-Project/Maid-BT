# Installation

## Quick install
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/Maidware-Project/Maid-BT/main/install.sh)
# fallback: bash <(curl -fsSL https://codeberg.org/Maidware_Project/Maid-BT/raw/branch/main/install.sh)
```

## Installer modes
```sh
bash install.sh
bash install.sh --check
bash install.sh --no-packages
bash install.sh --tui
```

## Post-install
- Pair/trust earbuds with BlueZ (`bluetoothctl`)
- Test `bluetooth-toggle.sh on|status|release`
- Enable optional watchers/services only if needed
- For phone remote features, configure the phone side and firewall/port as documented

## NixOS
Use the flake + Home Manager module (`programs.maid-bt.enable = true`) and enable optional services as needed. Rebuild with refresh to track latest updates.
