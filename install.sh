#!/usr/bin/env bash
# Universal installer: Arch (pacman), Debian/Ubuntu (apt), Fedora (dnf),
# openSUSE (zypper). Copies files (no symlinks — survives folder moves).
# Usage: ./install.sh [--check] [--no-packages] [--uninstall]
set -u
PKGDIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
CHECK=0; NO_PKGS=0; UNINST=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --no-packages) NO_PKGS=1 ;;
    --uninstall) UNINST=1 ;;
    *) echo "unknown option: $a (see: --check --no-packages --uninstall)" >&2; exit 2 ;;
  esac
done

if [ "$UNINST" = "1" ]; then
  systemctl --user disable --now buds-fallback.service bt-intent.service 2>/dev/null || true
  rm -f "$HOME"/.local/bin/bluetooth-toggle.sh "$HOME"/.local/bin/buds-fallback.sh \
    "$HOME"/.local/bin/buds-on.sh "$HOME"/.local/bin/buds-off.sh "$HOME"/.local/bin/buds-release.sh \
    "$HOME"/.local/bin/bt-intent-server.py "$HOME"/.local/bin/bt-notify-menu.sh
  rm -f "$HOME"/.local/bin/maid-watcher
  rm -rf "$HOME"/.local/bin/maid_core
  rm -f "$HOME"/.config/autostart/maid-watcher.desktop
  rm -f "$HOME"/.config/wireplumber/wireplumber.conf.d/51-bt-no-suspend.conf
  rm -f "$HOME"/.config/systemd/user/buds-fallback.service "$HOME"/.config/systemd/user/bt-intent.service \
    "$HOME"/.config/systemd/user/bt-menu.service
  rm -rf "$HOME/.local/share/plasma/plasmoids/com.local.btearbuds"
  rm -f "$HOME"/.local/share/applications/bt-earbuds-pc.desktop \
    "$HOME"/.local/share/applications/bt-earbuds-phone.desktop "$HOME"/.local/share/applications/bt-off.desktop \
    "$HOME"/.local/share/applications/bt-on.desktop
  echo "==> uninstalled (kept: ~/.config/bluetooth-buds.conf ~/.config/bt-intent.token ~/.config/maid-watcher/)"
  exit 0
fi

say()  { echo "==> $*"; }
warn() { echo "!! $*" >&2; }

detect_pm() {
  if command -v pacman >/dev/null 2>&1; then echo pacman
  elif command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v zypper >/dev/null 2>&1; then echo zypper
  else echo none; fi
}

install_pkgs() {
  local pm="$1"; shift
  case "$pm" in
    # NOTE: full -Syu, never -Sy alone — Arch does not support partial
    # upgrades (refreshed db + old packages breaks).
    pacman) sudo pacman -Syu --needed --noconfirm "$@" ;;
    apt) sudo apt-get update && sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
    zypper) sudo zypper --non-interactive install "$@" ;;
  esac
}

PM=$(detect_pm)
if [ "$CHECK" = "1" ]; then
  say "package manager: $PM (check only, nothing installed)"
elif [ "$NO_PKGS" = "0" ]; then
  case "$PM" in
    pacman) REQ=(bluez bluez-utils util-linux libnotify libpulse python) ;;
    apt) REQ=(bluez bluetooth rfkill libnotify-bin pulseaudio-utils python3) ;;
    dnf) REQ=(bluez rfkill libnotify pulseaudio-utils python3) ;;
    zypper) REQ=(bluez rfkill libnotify-tools pulseaudio-utils python3) ;;
    *) warn "no supported package manager — install manually: bluez, bluetoothctl, rfkill, notify-send, pactl, python3 (kdeconnect optional)"; REQ=() ;;
  esac
  if [ "${#REQ[@]}" -gt 0 ]; then
    say "installing: ${REQ[*]}"
    install_pkgs "$PM" "${REQ[@]}" || warn "package install had errors — continuing (see README requirements)"
  fi
  # Maid Watcher (optional component) needs python dbus/gi bindings.
  case "$PM" in
    pacman) WATCHREQ=(python-dbus python-gobject) ;;
    apt) WATCHREQ=(python3-dbus python3-gi) ;;
    dnf) WATCHREQ=(python3-dbus python3-gobject) ;;
    zypper) WATCHREQ=(python3-dbus python3-gobject) ;;
    *) WATCHREQ=() ;;
  esac
  if [ "${#WATCHREQ[@]}" -gt 0 ] && [ "$CHECK" = "0" ] && [ "$NO_PKGS" = "0" ]; then
    say "trying optional (Maid Watcher): ${WATCHREQ[*]}"
    install_pkgs "$PM" "${WATCHREQ[@]}" >/dev/null 2>&1 || say "optional Maid Watcher deps skipped"
  fi
  # kdeconnect is optional (phone pings only): try it, tolerate absence.
  case "$PM" in
    pacman) OPT=(kdeconnect) ;;
    apt) OPT=(kdeconnect) ;;
    dnf) OPT=(kdeconnect) ;;
    zypper) OPT=(kdeconnect-kde) ;;
    *) OPT=() ;;
  esac
  if [ "${#OPT[@]}" -gt 0 ] && [ "$CHECK" = "0" ] && [ "$NO_PKGS" = "0" ]; then
    say "trying optional (phone pings): ${OPT[*]}"
    install_pkgs "$PM" "${OPT[@]}" >/dev/null 2>&1 || say "optional kdeconnect skipped"
  fi
else
  say "skipping packages (--no-packages)"
fi

copy_one() {
  local src="$1" dest="$2" rewrite="${3:-0}"
  if [ "$CHECK" = "1" ]; then echo "COPY $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp -a "$dest" "${dest}.bak-${BACKUP_TS}"
    say "backed up $dest"
  fi
  if [ "$rewrite" = "1" ]; then
    # escape & (sed replacement metachar) in $HOME
    sed -e "s|/home/visa|${HOME//&/\\&}|g" "$src" > "$dest"
  else
    cp -a "$src" "$dest"
  fi
  echo "installed $dest"
}

for f in "$PKGDIR"/bin/*; do
  [ -f "$f" ] || continue
  copy_one "$f" "$HOME/.local/bin/$(basename "$f")"
done
[ "$CHECK" = "0" ] && chmod +x "$HOME"/.local/bin/bluetooth-toggle.sh "$HOME"/.local/bin/buds-*.sh "$HOME"/.local/bin/bt-*.sh "$HOME"/.local/bin/bt-*.py 2>/dev/null || true

# ---- Maid Watcher (optional daemon: calls, 3-device priority, battery) ----
copy_one "$PKGDIR/watcher/maid-watcher" "$HOME/.local/bin/maid-watcher"
for f in "$PKGDIR"/watcher/maid_core/*.py; do
  [ -f "$f" ] || continue
  copy_one "$f" "$HOME/.local/bin/maid_core/$(basename "$f")"
done
[ "$CHECK" = "0" ] && chmod +x "$HOME/.local/bin/maid-watcher" 2>/dev/null || true
if [ "$CHECK" = "1" ]; then
  echo "CONFIG $HOME/.config/maid-watcher/config.json (example copy on real run)"
elif [ ! -f "$HOME/.config/maid-watcher/config.json" ]; then
  mkdir -p "$HOME/.config/maid-watcher"
  cp -a "$PKGDIR/watcher/config.example.json" "$HOME/.config/maid-watcher/config.json"
  say "wrote $HOME/.config/maid-watcher/config.json (edit your MACs)"
else
  say "$HOME/.config/maid-watcher/config.json exists — kept"
fi

for f in "$PKGDIR"/systemd/*.service; do
  [ -f "$f" ] || continue
  copy_one "$f" "$HOME/.config/systemd/user/$(basename "$f")"
done

copy_one "$PKGDIR/plasmoid/com.local.btearbuds/metadata.json" \
  "$HOME/.local/share/plasma/plasmoids/com.local.btearbuds/metadata.json"
copy_one "$PKGDIR/plasmoid/com.local.btearbuds/contents/ui/main.qml" \
  "$HOME/.local/share/plasma/plasmoids/com.local.btearbuds/contents/ui/main.qml" 1

for f in "$PKGDIR"/desktop/*.desktop; do
  [ -f "$f" ] || continue
  copy_one "$f" "$HOME/.local/share/applications/$(basename "$f")" 1
done
copy_one "$PKGDIR/bluetooth-buds.conf.example" "$HOME/.config/bluetooth-buds.conf.example"

# ---- per-machine earbuds config (interactive, skippable) ----
CONF="$HOME/.config/bluetooth-buds.conf"
if [ "$CHECK" = "1" ]; then
  echo "CONFIG $CONF (interactive prompt on real run)"
elif [ -f "$CONF" ]; then
  say "$CONF exists — kept"
elif [ ! -t 0 ]; then
  say "non-interactive — skipped $CONF (copy the .example later)"
else
  say "paired devices:"; bluetoothctl devices 2>/dev/null || true
  printf 'Earbuds MAC (AA:BB:CC:DD:EE:FF, Enter to skip): '; read -r MAC
  if [[ "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [ "$MAC" != "AA:BB:CC:DD:EE:FF" ]; then
    say "audio sinks:"; pactl list short sinks 2>/dev/null || true
    DEF=$(pactl info 2>/dev/null | sed -n 's/^Default Sink: //p')
    printf "Fallback sink [Enter = %s]: " "$DEF"; read -r SINK
    SINK=${SINK:-$DEF}
    if [[ "$SINK" =~ ^[A-Za-z0-9_.,:/+=@-]+$ ]]; then
      { echo "# generated by install.sh on $(date +%F)"; echo "BUDS_MAC=\"$MAC\""; echo "FALLBACK_SINK=\"$SINK\""; } > "$CONF"
      say "wrote $CONF"
    else
      warn "odd characters in sink name — not writing $CONF (copy the .example and edit manually)"
    fi
  else
    say "skipped — edit $CONF later (see bluetooth-buds.conf.example)"
  fi
fi

# ---- intent token ----
if [ "$CHECK" = "1" ]; then
  echo "TOKEN ~/.config/bt-intent.token"
elif [ ! -f "$HOME/.config/bt-intent.token" ]; then
  if command -v python3 >/dev/null 2>&1; then
    # umask first: token must never exist world-readable, even briefly
    ( umask 077; python3 -c "import secrets; print(secrets.token_urlsafe(24))" > "$HOME/.config/bt-intent.token" ) \
      && say "generated ~/.config/bt-intent.token (0600)"
  else
    warn "python3 missing — no token generated (phone integration needs it)"
  fi
fi

if [ "$CHECK" = "1" ]; then say "(check only, nothing changed)"; exit 0; fi

systemctl --user daemon-reload 2>/dev/null || true
# OpenRC/runit/etc are not supported: services need systemd user units.
# Scripts still work if started manually, but nothing is auto-enabled.
SKIP_SERVICES=0
if [ "$(ps -p 1 -o comm= 2>/dev/null || echo unknown)" != "systemd" ]; then
  warn "no systemd here — skipping services (fork it for your init if you want)"
  SKIP_SERVICES=1
fi
[ "$SKIP_SERVICES" = "1" ] || systemctl --user enable --now buds-fallback.service 2>/dev/null \
  || warn "could not enable buds-fallback.service"
# phone integration stays OFF unless asked: it opens a LAN port, so it is
# opt-in, never default.
PHONE_ON=0
if [ "$SKIP_SERVICES" != "1" ] && [ -t 0 ]; then
  printf 'Enable phone integration (bt-intent.service, LAN port 8899)? [y/N]: '
  read -r _ans
  case "$_ans" in [Yy]*) PHONE_ON=1 ;; esac
else
  say "phone integration skipped (non-interactive; enable later, see phone/)"
fi
if [ "$PHONE_ON" = "1" ]; then
  systemctl --user enable --now bt-intent.service 2>/dev/null \
    || warn "could not enable bt-intent.service"
else
  say "phone integration off (enable anytime: systemctl --user enable --now bt-intent.service)"
fi
# Maid Watcher autostart is opt-in: it overlaps buds-fallback (reconnects +
# A2DP enforcement). Safe to combine, but ask first.
WATCH_ON=0
if [ -t 0 ]; then
  printf 'Enable Maid Watcher autostart (calls, battery, 3-device priority)? [y/N]: '
  read -r _wans
  case "$_wans" in [Yy]*) WATCH_ON=1 ;; esac
else
  say "Maid Watcher autostart skipped (non-interactive; copy watcher/maid-watcher.desktop to ~/.config/autostart/ to enable)"
fi
if [ "$WATCH_ON" = "1" ]; then
  copy_one "$PKGDIR/watcher/maid-watcher.desktop" "$HOME/.config/autostart/maid-watcher.desktop" 1
else
  say "Maid Watcher autostart off (daemon still installed as maid-watcher; run it manually or copy the desktop file to autostart)"
fi
# Warm-link audio: disable PipeWire auto-suspend on BT nodes so playback
# starts instantly instead of losing ~1s after silence. Costs some earbud
# battery. Opt-in, off by default.
WARM_ON=0
if [ -t 0 ]; then
  printf 'Keep BT audio warm (no suspend delay, more earbud drain)? [y/N]: '
  read -r _wans2
  case "$_wans2" in [Yy]*) WARM_ON=1 ;; esac
else
  say "warm-link audio skipped (non-interactive; copy wireplumber/51-bt-no-suspend.conf to ~/.config/wireplumber/wireplumber.conf.d/ to enable, then restart wireplumber)"
fi
if [ "$WARM_ON" = "1" ]; then
  mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
  copy_one "$PKGDIR/wireplumber/51-bt-no-suspend.conf" \
    "$HOME/.config/wireplumber/wireplumber.conf.d/51-bt-no-suspend.conf"
  say "warm-link on — restart wireplumber to apply: systemctl --user restart wireplumber"
else
  say "warm-link audio off"
fi
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

say "done. Backups (if any): *.bak-${BACKUP_TS}"
say "Next: pair+trust earbuds, add the 'BT Earbuds' widget (Add Widgets), log out/in."
say "Phone remote: see phone/README-macrodroid-tasker.md (needs ~/.config/bt-intent.token + open TCP 8899)."
