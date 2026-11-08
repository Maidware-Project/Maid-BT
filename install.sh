#!/usr/bin/env bash
# Universal installer: Arch (pacman), Debian/Ubuntu (apt), Fedora (dnf),
# openSUSE (zypper). Copies files (no symlinks - survives folder moves).
# Usage: ./install.sh [--check] [--no-packages] [--uninstall [--purge]]
#          [--prefix=DIR] [--no-config] [--packages] [--verbose]
# --prefix installs program files elsewhere (packaging); user config and
# services still target $HOME unless --no-config skips them entirely.
# --packages: install distro packages without asking. --verbose: restore
# the per-file "installed ..." list; without it the install is quiet
# (one summary line per destination - fits the piped curl install).
set -u
PKGDIR="$(cd "$(dirname "$0")" && pwd)" 2>/dev/null || PKGDIR=""
if [ ! -f "$PKGDIR/install.sh" ]; then
  # piped install (bash <(curl -fsSL ...)): the script is a /dev/fd
  # stream, so there is no package tree next to it. Fetch the repo
  # tarball and continue from there - keeps the one-liner honest,
  # it really installs Maid BT, not a half copy.
  FETCH_TMP="$(mktemp -d /tmp/maidbt-fetch.XXXXXX)"
  trap 'rm -rf "$FETCH_TMP"' INT TERM
  TARBALL_URL="https://github.com/Maidware-Project/Maid-BT/archive/refs/heads/main.tar.gz"
  curl -fsSL "$TARBALL_URL" -o "$FETCH_TMP/maid-bt.tgz" || {
    echo "could not download the Maid BT package tree (curl failed)" >&2
    exit 1
  }
  tar -xzf "$FETCH_TMP/maid-bt.tgz" -C "$FETCH_TMP" || exit 1
  PKGDIR="$(find "$FETCH_TMP" -mindepth 1 -maxdepth 1 -type d -name 'Maid-BT-*' | head -n 1)"
  [ -f "$PKGDIR/install.sh" ] || { echo "downloaded tree looks wrong" >&2; exit 1; }
  # the script stream came through a pipe: stdin is still the user's
  # tty, so never trust [ -t 0 ] alone here - stay silent by default
  PIPED=1
fi
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
_WAS_PIPED="${PIPED:-0}"
CHECK=0; NO_PKGS=0; UNINST=0; PURGE=0; NOCONFIG=0; PREFIX=""; TUI=0; FORCE_PLAIN=0
PKGS=0; VERBOSE=0; PIPED="$_WAS_PIPED"
declare -A STATS=()          # quiet-mode: install counts by destination
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --no-packages) NO_PKGS=1 ;;
    --uninstall) UNINST=1 ;;
    --purge) PURGE=1 ;;
    --no-config) NOCONFIG=1 ;;
    --tui) TUI=1 ;;
    --plain|--no-tui) FORCE_PLAIN=1 ;;
    --packages) PKGS=1 ;;
    --verbose) VERBOSE=1 ;;
    --prefix=*) PREFIX="${a#--prefix=}" ;;
    *) echo "unknown option: $a (see header)" >&2; exit 2 ;;
  esac
done
# TUI is the default for interactive runs: friendlier menu, same engine.
# Scripted/piped/explicit-plain paths keep the engine output.
if [ "$FORCE_PLAIN" != "1" ] && [ "$PIPED" != "1" ] && [ -t 0 ] && [ -t 1 ]; then
  TUI=1
fi
if [ "$TUI" = "1" ]; then
  exec bash "$PKGDIR/bin/tui-install.sh"
fi
if [ -z "$PREFIX" ]; then PREFIX="$HOME/.local"; fi
if [ "$PREFIX" = "$HOME/.local" ]; then
  USERMODE=1
  BINDIR="$HOME/.local/bin"
  SYSDDIR="$HOME/.config/systemd/user"
  SHAREDIR="$HOME/.local/share"
else
  USERMODE=0
  BINDIR="${DESTDIR:-}$PREFIX/bin"
  SYSDDIR="${DESTDIR:-}$PREFIX/lib/systemd/user"
  SHAREDIR="${DESTDIR:-}$PREFIX/share"
fi
# system installs never touch per-user state, even without --no-config
if [ "$USERMODE" = "0" ]; then NOCONFIG=1; fi

if [ "$UNINST" = "1" ]; then
  systemctl --user disable --now buds-fallback.service bt-intent.service bt-menu.service maid-watcher.service 2>/dev/null || true
  # program files come out of the same dirs the install used, so
  # --prefix/DESTDIR installs uninstall cleanly too.
  rm -f "$BINDIR"/bluetooth-toggle.sh "$BINDIR"/buds-fallback.sh \
    "$BINDIR"/buds-on.sh "$BINDIR"/buds-off.sh "$BINDIR"/buds-release.sh \
    "$BINDIR"/bt-intent-server.py "$BINDIR"/bt-notify-menu.sh
  rm -f "$BINDIR"/maid-watcher "$BINDIR"/maid-bt-config "$BINDIR"/maid-bt-helper
  rm -rf "$BINDIR"/maid_core
  rm -f "$HOME"/.config/autostart/maid-watcher.desktop
  rm -f "$SYSDDIR"/maid-watcher.service
  rm -f "$SHAREDIR"/maid-bt/52-bt-max-quality.conf
  rm -f "$HOME"/.config/wireplumber/wireplumber.conf.d/51-bt-no-suspend.conf
  rm -f "$HOME"/.config/wireplumber/wireplumber.conf.d/52-bt-max-quality.conf
  rm -f "$HOME"/.config/wireplumber/wireplumber.conf.d/53-bt-a2dp-only.conf
  rm -f "$SYSDDIR"/buds-fallback.service "$SYSDDIR"/bt-intent.service \
    "$SYSDDIR"/bt-menu.service
  rm -rf "$SHAREDIR/maid-bt" "$SHAREDIR/plasma/plasmoids/com.local.btearbuds"
  rm -f "$SHAREDIR"/applications/bt-earbuds-pc.desktop \
    "$SHAREDIR"/applications/bt-earbuds-phone.desktop "$SHAREDIR"/applications/bt-off.desktop \
    "$SHAREDIR"/applications/bt-on.desktop "$SHAREDIR"/applications/maid-bt-helper.desktop \
    "$SHAREDIR"/applications/maid-helper.desktop
  if [ "$PURGE" = "1" ]; then
    rm -f "$HOME"/.config/bluetooth-buds.conf "$HOME"/.config/bluetooth-buds.conf.example "$HOME"/.config/bt-intent.token
    rm -rf "$HOME"/.config/maid-watcher
    echo "==> uninstalled, all settings removed (--purge)"
  elif [ "$PIPED" = "0" ] && [ -t 0 ]; then
    printf 'Remove settings too (earbuds conf, phone token, watcher config)? [y/N]: '
    read -r _ans
    case "$_ans" in [Yy]*)
      rm -f "$HOME"/.config/bluetooth-buds.conf "$HOME"/.config/bt-intent.token
      rm -rf "$HOME"/.config/maid-watcher
      echo "==> uninstalled, settings removed" ;;
    *) echo "==> uninstalled (kept: ~/.config/bluetooth-buds.conf ~/.config/bt-intent.token ~/.config/maid-watcher/)" ;;
    esac
  else
    echo "==> uninstalled (kept: ~/.config/bluetooth-buds.conf ~/.config/bt-intent.token ~/.config/maid-watcher/; rerun with --purge to remove)"
  fi
  exit 0
fi

say()  { echo "==> $*"; }
warn() { echo "!! $*" >&2; }

# Report the KDE stack so install logs show what this machine runs.
kde_env() {
  local plasma fw qt kc
  plasma=$(plasmashell --version 2>/dev/null | awk 'NR==1{print $2}')
  [ -n "$plasma" ] || plasma=$(kwin_wayland --version 2>/dev/null | awk 'NR==1{print $2}')
  fw=$(kf6-config --version 2>/dev/null)
  [ -n "$fw" ] || fw=$(pkg-config --modversion KF6CoreAddons 2>/dev/null)
  [ -n "$fw" ] || fw=$(rpm -q --qf '%{VERSION}' kf6-kcoreaddons 2>/dev/null)
  [ -n "$fw" ] || fw=$(dpkg-query -W -f='${Version}' libkf6coreaddons6 2>/dev/null)
  [ -n "$fw" ] || fw=$(pacman -Q kf6-kcoreaddons 2>/dev/null | awk '{print $2}')
  qt=$(qmake6 -query QT_VERSION 2>/dev/null)
  [ -n "$qt" ] || qt=$(qtpaths6 --qt-version 2>/dev/null)
  [ -n "$qt" ] || qt=$(pkg-config --modversion Qt6Core 2>/dev/null)
  kc=$(kdeconnectd --version 2>/dev/null | awk 'NR==1{print $NF}')
  [ -n "$kc" ] || kc=$(kdeconnect-cli --version 2>/dev/null | awk 'NR==1{print $NF}')
  KDE_PLASMA="$plasma"
  KDE_FRAMEWORKS="$fw"
  KDE_QT="$qt"
  KDE_CONNECT="$kc"
}
kde_env_line() {
  if [ -z "${KDE_PLASMA:-}${KDE_FRAMEWORKS:-}${KDE_QT:-}${KDE_CONNECT:-}" ]; then
    echo "KDE: not detected (non-KDE session or tools missing)"
  else
    echo "KDE: Plasma ${KDE_PLASMA:-?} | Frameworks ${KDE_FRAMEWORKS:-?} | Qt ${KDE_QT:-?} | KDE Connect ${KDE_CONNECT:-not installed}"
  fi
}
kde_env
say "$(kde_env_line)"

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
    # NOTE: full -Syu, never -Sy alone - Arch does not support partial
    # upgrades (refreshed db + old packages breaks).
    pacman) sudo pacman -Syu --needed --noconfirm "$@" ;;
    apt) sudo apt-get update && sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
    zypper) sudo zypper --non-interactive install "$@" ;;
  esac
}

PM=$(detect_pm)

do_packages() {
  # one place for every distro package call - callers gate it so sudo
  # is never hit from a piped run without the user asking for it
  local pm="$1"
  case "$pm" in
    pacman) REQ=(bluez bluez-utils util-linux libnotify libpulse python) ;;
    apt) REQ=(bluez bluetooth rfkill libnotify-bin pulseaudio-utils python3) ;;
    dnf) REQ=(bluez rfkill libnotify pulseaudio-utils python3) ;;
    zypper) REQ=(bluez rfkill libnotify-tools pulseaudio-utils python3) ;;
    *) warn "no supported package manager - install manually: bluez, bluetoothctl, rfkill, notify-send, pactl, python3 (kdeconnect optional)"; REQ=() ;;
  esac
  if [ "${#REQ[@]}" -gt 0 ]; then
    say "installing: ${REQ[*]}"
    install_pkgs "$pm" "${REQ[@]}" || warn "package install had errors - continuing (see README requirements)"
  fi
  # Maid Watcher (optional component) needs python dbus/gi bindings.
  case "$pm" in
    pacman) WATCHREQ=(python-dbus python-gobject) ;;
    apt) WATCHREQ=(python3-dbus python3-gi) ;;
    dnf) WATCHREQ=(python3-dbus python3-gobject) ;;
    zypper) WATCHREQ=(python3-dbus python3-gobject) ;;
    *) WATCHREQ=() ;;
  esac
  if [ "${#WATCHREQ[@]}" -gt 0 ]; then
    say "trying optional (Maid Watcher): ${WATCHREQ[*]}"
    install_pkgs "$pm" "${WATCHREQ[@]}" >/dev/null 2>&1 || say "optional Maid Watcher deps skipped"
  fi
  # kdeconnect is optional (phone pings only): try it, tolerate absence.
  case "$pm" in
    pacman|apt|dnf) OPT=(kdeconnect) ;;
    zypper) OPT=(kdeconnect-kde) ;;
    *) OPT=() ;;
  esac
  if [ "${#OPT[@]}" -gt 0 ]; then
    say "trying optional (phone pings): ${OPT[*]}"
    install_pkgs "$pm" "${OPT[@]}" >/dev/null 2>&1 || say "optional kdeconnect skipped"
  fi
}

if [ "$CHECK" = "1" ]; then
  say "package manager: $PM (check only, nothing installed)"
elif [ "$NO_PKGS" = "1" ]; then
  say "skipping packages (--no-packages)"
elif [ "$PKGS" = "1" ]; then
  do_packages "$PM"
elif [ "$PIPED" = "1" ]; then
  say "packages: not touching sudo in a piped run - install them anytime with: bash install.sh --packages"
elif [ -t 0 ]; then
  printf 'install the packages Maid BT needs (discovered via %s)? [y/N]: ' "$PM"
  read -r _ans
  case "${_ans:-n}" in
    [Yy]*) do_packages "$PM" ;;
    *) say "packages skipped now - install later with --packages (pass --no-packages to silence this ask)" ;;
  esac
else
  say "packages skipped (non-interactive; --packages forces them)"
fi

copy_one() {
  local src="$1" dest="$2" rewrite="${3:-0}" tmp=""
  if [ "$CHECK" = "1" ]; then echo "COPY $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  # render first, compare second: $src still holds the Exec-path
  # placeholder, which never equals an installed file - comparing raw
  # would back up on every run. compare what we would write instead.
  tmp="$(mktemp)" || return 1
  if [ "$rewrite" = "1" ]; then
    # user install: fix the Exec placeholder to this $HOME.
    # escape & (sed replacement metachar) in $HOME
    sed -e "s|@HOME@|${HOME//&/\\&}|g" "$src" > "$tmp"
  elif [ "$rewrite" = "2" ]; then
    # system package: bare command names, resolved via PATH.
    sed -e "s|@HOME@/.local/bin/||g" "$src" > "$tmp"
  else
    cp -a "$src" "$tmp"
  fi
  if [ -e "$dest" ] && ! cmp -s "$tmp" "$dest"; then
    if cp -a "$dest" "${dest}.bak-${BACKUP_TS}"; then
      say "backed up $dest"
    else
      warn "backup failed - not replacing $dest"
      rm -f "$tmp"
      return 1
    fi
  fi
  cat "$tmp" > "$dest"
  rm -f "$tmp"
  # quiet mode counts instead of echoing every file; --verbose prints
  if [ "$VERBOSE" = "1" ]; then
    echo "installed $dest"
  else
    local qd; qd="$(dirname "$dest")"
    STATS[$qd]=$(( ${STATS[$qd]:-0} + 1 ))
  fi
}

# rewrite mode: 1 = user home fixup, 2 = system bare names
if [ "$USERMODE" = "1" ]; then REWRITE=1; else REWRITE=2; fi

for f in "$PKGDIR"/bin/*; do
  [ -f "$f" ] || continue
  copy_one "$f" "$BINDIR/$(basename "$f")"
done
[ "$CHECK" = "0" ] && chmod +x "$BINDIR"/bluetooth-toggle.sh "$BINDIR"/maid-setup.sh "$BINDIR"/maid-bt-config "$BINDIR"/maid-bt-helper "$BINDIR"/buds-*.sh "$BINDIR"/bt-*.sh "$BINDIR"/bt-*.py 2>/dev/null || true

# ---- Maid Watcher (optional daemon: calls, 2-device priority, battery) ----
copy_one "$PKGDIR/watcher/maid-watcher" "$BINDIR/maid-watcher"
for f in "$PKGDIR"/watcher/maid_core/*.py; do
  [ -f "$f" ] || continue
  copy_one "$f" "$BINDIR/maid_core/$(basename "$f")"
done
[ "$CHECK" = "0" ] && chmod +x "$BINDIR/maid-watcher" 2>/dev/null || true
if [ "$CHECK" = "1" ]; then
  echo "CONFIG $HOME/.config/maid-watcher/config.json (example copy on real run)"
elif [ "$NOCONFIG" = "1" ]; then
  say "skipped watcher config (--no-config)"
elif [ ! -f "$HOME/.config/maid-watcher/config.json" ]; then
  mkdir -p "$HOME/.config/maid-watcher"
  cp -a "$PKGDIR/watcher/config.example.json" "$HOME/.config/maid-watcher/config.json"
  say "wrote $HOME/.config/maid-watcher/config.json (edit your MACs)"
else
  say "$HOME/.config/maid-watcher/config.json exists - kept"
fi

for f in "$PKGDIR"/systemd/*.service; do
  [ -f "$f" ] || continue
  copy_one "$f" "$SYSDDIR/$(basename "$f")"
done
# sources maid-setup.sh needs later (repo layout absent once installed)
copy_one "$PKGDIR/watcher/maid-watcher.desktop" "$SHAREDIR/maid-bt/maid-watcher.desktop" $REWRITE
copy_one "$PKGDIR/wireplumber/51-bt-no-suspend.conf" "$SHAREDIR/maid-bt/51-bt-no-suspend.conf"
copy_one "$PKGDIR/wireplumber/52-bt-max-quality.conf" "$SHAREDIR/maid-bt/52-bt-max-quality.conf"
copy_one "$PKGDIR/wireplumber/53-bt-a2dp-only.conf" "$SHAREDIR/maid-bt/53-bt-a2dp-only.conf"
copy_one "$PKGDIR/watcher/config.example.json" "$SHAREDIR/maid-bt/config.example.json"

# the kdeconnect early-login fix lives in Maid Helper's `kdeconnect`
# doctor (maid-helper --only kdeconnect --fix); it is not shipped here.
# clean a stale patch copy left by older installs
if [ "$CHECK" = "0" ]; then rm -rf "$SHAREDIR/maid-bt/patches"; fi

if [ -n "${KDE_PLASMA:-}" ] && [ "${KDE_PLASMA%%.*}" -lt 6 ] 2>/dev/null; then
  warn "Plasma $KDE_PLASMA detected; the Maid BT plasmoid needs Plasma 6 - skipping it"
else
  copy_one "$PKGDIR/plasmoid/com.local.btearbuds/metadata.json" \
    "$SHAREDIR/plasma/plasmoids/com.local.btearbuds/metadata.json"
  copy_one "$PKGDIR/plasmoid/com.local.btearbuds/contents/ui/main.qml" \
    "$SHAREDIR/plasma/plasmoids/com.local.btearbuds/contents/ui/main.qml" $REWRITE
  # config pages are discovered at contents/config/config.qml
  for f in "$PKGDIR"/plasmoid/com.local.btearbuds/contents/config/*.qml \
           "$PKGDIR"/plasmoid/com.local.btearbuds/contents/ui/config/*.qml; do
    [ -f "$f" ] || continue
    rel="${f#"$PKGDIR/plasmoid/com.local.btearbuds/"}"
    copy_one "$f" "$SHAREDIR/plasma/plasmoids/com.local.btearbuds/$rel" $REWRITE
  done
fi

for f in "$PKGDIR"/desktop/*.desktop; do
  [ -f "$f" ] || continue
  copy_one "$f" "$SHAREDIR/applications/$(basename "$f")" $REWRITE
done
if [ "$NOCONFIG" = "0" ]; then
  copy_one "$PKGDIR/bluetooth-buds.conf.example" "$HOME/.config/bluetooth-buds.conf.example"
fi

# ---- quiet-mode summary: one line per destination -------------------
if [ "$CHECK" = "0" ] && [ "$VERBOSE" = "0" ]; then
  for qd in $(printf '%s\n' "${!STATS[@]}" | sort); do
    say "installed ${STATS[$qd]} files -> ${qd/#$HOME/~}"
  done
fi

# ---- per-machine earbuds config (interactive, skippable) ----
CONF="$HOME/.config/bluetooth-buds.conf"
if [ "$CHECK" = "1" ]; then
  echo "CONFIG $CONF (interactive prompt on real run)"
elif [ -f "$CONF" ]; then
  say "$CONF exists - kept"
elif [ "$NOCONFIG" = "1" ] || [ "$PIPED" = "1" ] || [ ! -t 0 ]; then
  say "non-interactive - skipped $CONF (copy the .example later)"
else
  say "paired devices:"; bluetoothctl devices 2>/dev/null || true
  printf 'Earbuds MAC (AA:BB:CC:DD:EE:FF, Enter to skip): '; read -r MAC
  if [[ "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [ "$MAC" != "AA:BB:CC:DD:EE:FF" ]; then
    say "audio sinks:"; pactl list short sinks 2>/dev/null || true
    DEF=$(pactl info 2>/dev/null | sed -n 's/^Default Sink: //p')
    printf "Fallback speakers/DAC (name, not index) [Enter = %s]: " "$DEF"; read -r SINK
    SINK=${SINK:-$DEF}
    BAD_INDEX=0
    if [[ "$SINK" =~ ^[0-9]+$ ]]; then
      # a pulse index is per-session and goes stale: store the name
      RESOLVED=$(pactl list short sinks 2>/dev/null | awk -v i="$SINK" '$1==i{print $2; exit}')
      if [ -n "$RESOLVED" ]; then
        say "sink #$SINK is $RESOLVED - storing the name"
        SINK="$RESOLVED"
      else
        BAD_INDEX=1
      fi
    fi
    if [ "$BAD_INDEX" = "1" ]; then
      warn "no sink #$SINK right now - not writing $CONF (rerun install.sh with a name)"
    elif [[ "$SINK" =~ ^[A-Za-z0-9_.,:/+=@-]+$ ]]; then
      { echo "# generated by install.sh on $(date +%F)"; echo "BUDS_MAC=\"$MAC\""; echo "FALLBACK_SINK=\"$SINK\""; } > "$CONF"
      say "wrote $CONF"
    else
      warn "odd characters in sink name - not writing $CONF (copy the .example and edit manually)"
    fi
  else
    say "skipped - edit $CONF later (see bluetooth-buds.conf.example)"
  fi
fi

# ---- intent token ----
if [ "$CHECK" = "1" ]; then
  echo "TOKEN ~/.config/bt-intent.token"
elif [ "$NOCONFIG" = "1" ]; then
  say "skipped token (--no-config)"
elif [ ! -f "$HOME/.config/bt-intent.token" ]; then
  if command -v python3 >/dev/null 2>&1; then
    # umask first: token must never exist world-readable, even briefly
    ( umask 077; python3 -c "import secrets; print(secrets.token_urlsafe(24))" > "$HOME/.config/bt-intent.token" ) \
      && say "generated ~/.config/bt-intent.token (0600)"
  else
    warn "python3 missing - no token generated (phone integration needs it)"
  fi
fi

if [ "$CHECK" = "1" ]; then say "(check only, nothing changed)"; exit 0; fi

if [ "$NOCONFIG" = "1" ] || [ "$USERMODE" = "0" ]; then
  say "program files installed; user setup skipped (pass no --no-config with default prefix for the interactive setup)"
  exit 0
fi

systemctl --user daemon-reload 2>/dev/null || true
# OpenRC/runit/etc are not supported: services need systemd user units.
# Scripts still work if started manually, but nothing is auto-enabled.
SKIP_SERVICES=0
if [ "$(ps -p 1 -o comm= 2>/dev/null || echo unknown)" != "systemd" ]; then
  warn "no systemd here - skipping services (fork it for your init if you want)"
  SKIP_SERVICES=1
fi
[ "$SKIP_SERVICES" = "1" ] || systemctl --user enable --now buds-fallback.service 2>/dev/null \
  || warn "could not enable buds-fallback.service"
# phone integration stays OFF unless asked: it opens a LAN port, so it is
# opt-in, never default.
PHONE_ON=0
if [ "$SKIP_SERVICES" != "1" ] && [ "$PIPED" = "0" ] && [ -t 0 ]; then
  printf 'Enable phone integration (bt-intent.service, LAN port 8899)? [y/N]: '
  read -r _ans
  case "$_ans" in [Yy]*) PHONE_ON=1 ;; esac
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
if [ "$PIPED" = "0" ] && [ -t 0 ]; then
  printf 'Enable Maid Watcher autostart (calls, battery, 3-device priority)? [y/N]: '
  read -r _wans
  case "$_wans" in [Yy]*) WATCH_ON=1 ;; esac
fi
if [ "$WATCH_ON" = "1" ]; then
  if [ "$SKIP_SERVICES" != "1" ]; then
    # systemd-native: supervised unit, journal logging, restart on failure.
    # The unit owns autostart: remove the desktop file so two daemons
    # can never run (double RAM, duplicate reconnects/mutes).
    rm -f "$HOME/.config/autostart/maid-watcher.desktop"
    copy_one "$PKGDIR/watcher/maid-watcher.service" "$HOME/.config/systemd/user/maid-watcher.service"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now maid-watcher.service 2>/dev/null \
      || warn "could not enable maid-watcher.service"
  else
    # any other init: XDG autostart desktop instead.
    copy_one "$PKGDIR/watcher/maid-watcher.desktop" "$HOME/.config/autostart/maid-watcher.desktop" 1
  fi
else
  say "Maid Watcher autostart off (daemon still installed as maid-watcher; run it manually or enable later)"
fi
# Warm-link audio: disable PipeWire auto-suspend on BT nodes so playback
# starts instantly instead of losing ~1s after silence. Costs some earbud
# battery. Opt-in, off by default.
WARM_ON=0
if [ "$PIPED" = "0" ] && [ -t 0 ]; then
  printf 'Keep BT audio warm (no suspend delay, more earbud drain)? [y/N]: '
  read -r _wans2
  case "$_wans2" in [Yy]*) WARM_ON=1 ;; esac
fi
if [ "$WARM_ON" = "1" ]; then
  mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
  copy_one "$PKGDIR/wireplumber/51-bt-no-suspend.conf" \
    "$HOME/.config/wireplumber/wireplumber.conf.d/51-bt-no-suspend.conf"
  say "warm-link on - restart wireplumber to apply: systemctl --user restart wireplumber"
else
  say "warm-link audio off (enable: copy wireplumber/51-bt-no-suspend.conf to ~/.config/wireplumber/wireplumber.conf.d/, restart wireplumber)"
fi
# Max-quality audio: pin codec ladder LDAC > AAC > SBC-XQ > SBC and
# unlock high-bitpool SBC-XQ. Needs LDAC/AAC headset; harmless
# otherwise. Pair with QUALITY_LOCK=1 in ~/.config/bluetooth-buds.conf
# to enforce LDAC after every switch. Opt-in, off by default.
QLOCK_ON=0
if [ "$PIPED" = "0" ] && [ -t 0 ]; then
  printf 'Prefer best codec (LDAC first, SBC-XQ unlocked, more earbud drain)? [y/N]: '
  read -r _wans3
  case "$_wans3" in [Yy]*) QLOCK_ON=1 ;; esac
fi
if [ "$QLOCK_ON" = "1" ]; then
  mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
  copy_one "$PKGDIR/wireplumber/52-bt-max-quality.conf" \
    "$HOME/.config/wireplumber/wireplumber.conf.d/52-bt-max-quality.conf"
  say "max-quality on - restart wireplumber to apply: systemctl --user restart wireplumber"
else
  say "max-quality audio off (enable: copy wireplumber/52-bt-max-quality.conf to ~/.config/wireplumber/wireplumber.conf.d/, restart wireplumber)"
fi
# A2DP-only: newer stacks try LE Audio transports first on dual-mode
# buds when the adapter's ISO sockets are weak - those transports keep
# failing and the buds go silent while classic A2DP works. Opt-in,
# off by default.
A2DP_ON=0
if [ "$PIPED" = "0" ] && [ -t 0 ]; then
  printf 'Lock buds to classic A2DP (fixes silent LE Audio buds)? [y/N]: '
  read -r _wans4
  case "$_wans4" in [Yy]*) A2DP_ON=1 ;; esac
fi
if [ "$A2DP_ON" = "1" ]; then
  mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
  copy_one "$PKGDIR/wireplumber/53-bt-a2dp-only.conf" \
    "$HOME/.config/wireplumber/wireplumber.conf.d/53-bt-a2dp-only.conf"
  say "a2dp-only on - restart wireplumber to apply: systemctl --user restart wireplumber"
else
  say "a2dp-only off (enable: copy wireplumber/53-bt-a2dp-only.conf to ~/.config/wireplumber/wireplumber.conf.d/, restart wireplumber)"
fi
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

say "done. Backups (if any): *.bak-${BACKUP_TS}"
mkdir -p "$HOME/MaidLogs" 2>/dev/null || true
say "logs live in ~/MaidLogs/ (visible folder) + journalctl --user -t maid-bt -t maid-watcher"
say "Next: pair+trust earbuds, add the 'Maid BT' widget (Add Widgets). restart plasmashell only if it is not listed; no logout needed."
say "Phone remote: see phone/README-macrodroid-tasker.md (needs ~/.config/bt-intent.token + open TCP 8899)."
