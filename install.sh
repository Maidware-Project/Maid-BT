#!/usr/bin/env bash
# this is truly my power
# Universal installer: Arch (pacman), Debian/Ubuntu (apt), Fedora (dnf),
# openSUSE (zypper), Gentoo (emerge). Copies files (no symlinks - survives folder moves).
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
  REPO="Maidware-Project/Maid-BT"
  LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  _fetched=0
  _urls=()
  if [ -n "$LATEST_TAG" ]; then
    _urls+=("https://github.com/$REPO/archive/refs/tags/$LATEST_TAG.tar.gz")
    _urls+=("https://codeberg.org/Maidware_Project/Maid-BT/archive/${LATEST_TAG}.tar.gz")
  fi
  _urls+=("https://github.com/$REPO/archive/refs/heads/main.tar.gz")
  _urls+=("https://codeberg.org/Maidware_Project/Maid-BT/archive/main.tar.gz")
  for TARBALL_URL in "${_urls[@]}"; do
    if curl -fsSL "$TARBALL_URL" -o "$FETCH_TMP/maid-bt.tgz" 2>/dev/null && tar -xzf "$FETCH_TMP/maid-bt.tgz" -C "$FETCH_TMP" 2>/dev/null; then
      PKGDIR="$(find "$FETCH_TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
      [ -f "$PKGDIR/install.sh" ] && { _fetched=1; break; }
    fi
    rm -rf "$FETCH_TMP"/* 2>/dev/null || true
  done
  [ "$_fetched" = "1" ] || { echo "could not download the Maid BT package tree (tried GitHub and Codeberg)" >&2; exit 1; }
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
session_env_line() {
  local de="${XDG_CURRENT_DESKTOP:-}" sess="${XDG_SESSION_DESKTOP:-}" dses="${DESKTOP_SESSION:-}"
  local label="unknown"
  case "$de $sess $dses" in
    *[Pp]lasma*|*[Kk][Dd][Ee]*) label="KDE Plasma" ;;
    *[Gg][Nn][Oo][Mm][Ee]*) label="GNOME" ;;
    *[Xx][Ff][Cc][Ee]*) label="XFCE" ;;
    *[Mm][Aa][Tt][Ee]*) label="MATE" ;;
    *[Cc]innamon*) label="Cinnamon" ;;
    *[Ll][Xx][Qq]t*) label="LXQt" ;;
    *[Hh]yprland*) label="Hyprland" ;;
    *[Ss]way*) label="Sway" ;;
    *[Ii]3*) label="i3" ;;
    *) [ -n "${de:-}${sess:-}${dses:-}" ] && label="$de" || label="unknown" ;;
  esac
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x gpuishell >/dev/null 2>&1 && label="$label (+ GPUIShell/gpuishell)"
    pgrep -x horizon >/dev/null 2>&1 && label="$label (+ Event Horizon)"
    pgrep -x kineticwe >/dev/null 2>&1 && label="$label (+ KineticWE)"
  fi
  echo "Session: $label | XDG_CURRENT_DESKTOP=${de:-n/a} | DESKTOP_SESSION=${dses:-n/a} | WAYLAND=${WAYLAND_DISPLAY:+yes}${WAYLAND_DISPLAY:-no} | X11=${DISPLAY:+yes}${DISPLAY:-no}"
}
distro_env_line() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "Distro: ${PRETTY_NAME:-${NAME:-unknown}} (id=${ID:-?}${ID_LIKE:+ like=${ID_LIKE}})"
  elif [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
    echo "Distro: Linux (unidentified)"
  else
    echo "Distro: $(uname -s 2>/dev/null || echo unknown)"
  fi
}
kde_env
say "$(kde_env_line)"
say "$(session_env_line)"
say "$(distro_env_line)"

detect_pm() {
  if command -v pacman >/dev/null 2>&1; then echo pacman
  elif command -v xbps-install >/dev/null 2>&1; then echo xbps
  elif command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v zypper >/dev/null 2>&1; then echo zypper
  elif command -v emerge >/dev/null 2>&1; then echo emerge
  else echo none; fi
}

install_pkgs() {
  local pm="$1"; shift
  case "$pm" in
    # NOTE: full -Syu, never -Sy alone - Arch does not support partial
    # upgrades (refreshed db + old packages breaks).
    pacman) sudo pacman -Syu --needed --noconfirm "$@" ;;
    xbps) sudo xbps-install -Sy "$@" ;;
    apt) sudo apt-get update && sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
    zypper) sudo zypper --non-interactive install "$@" ;;
    emerge) sudo emerge -avuDN --noreplace "$@" ;;
  esac
}

PM=$(detect_pm)

do_packages() {
  # one place for every distro package call - callers gate it so sudo
  # is never hit from a piped run without the user asking for it
  local pm="$1"
  case "$pm" in
    pacman) REQ=(bluez bluez-utils util-linux libnotify libpulse python) ;;
    xbps) REQ=(bluez bluez-alsa util-linux libnotify pulseaudio-utils python3) ;;
    apt) REQ=(bluez bluetooth rfkill libnotify-bin pulseaudio-utils python3) ;;
    dnf) REQ=(bluez rfkill libnotify pulseaudio-utils python3) ;;
    zypper) REQ=(bluez rfkill libnotify-tools pulseaudio-utils python3) ;;
    emerge) REQ=(net-wireless/bluez sys-apps/util-linux x11-libs/libnotify media-sound/pulseaudio-utils dev-lang/python) ;;
    *) warn "no supported package manager - install manually: bluez, bluetoothctl, rfkill, notify-send, pactl, python3 (kdeconnect optional)"; REQ=() ;;
  esac
  if [ "${#REQ[@]}" -gt 0 ]; then
    say "installing: ${REQ[*]}"
    install_pkgs "$pm" "${REQ[@]}" || warn "package install had errors - continuing (see README requirements)"
  fi
  # Maid Watcher (optional component) needs python dbus/gi bindings.
  case "$pm" in
    pacman) WATCHREQ=(python-dbus python-gobject) ;;
    xbps) WATCHREQ=(python3-dbus python3-gobject) ;;
    apt) WATCHREQ=(python3-dbus python3-gi) ;;
    dnf) WATCHREQ=(python3-dbus python3-gobject) ;;
    zypper) WATCHREQ=(python3-dbus python3-gobject) ;;
    emerge) WATCHREQ=(dev-python/dbus-python dev-python/pygobject) ;;
    *) WATCHREQ=() ;;
  esac
  if [ "${#WATCHREQ[@]}" -gt 0 ]; then
    say "trying optional (Maid Watcher): ${WATCHREQ[*]}"
    install_pkgs "$pm" "${WATCHREQ[@]}" >/dev/null 2>&1 || say "optional Maid Watcher deps skipped"
  fi
  # kdeconnect is optional (phone pings only): try it, tolerate absence.
  case "$pm" in
    pacman|apt|dnf|xbps) OPT=(kdeconnect) ;;
    zypper) OPT=(kdeconnect-kde) ;;
    emerge) OPT=(kde-misc/kdeconnect) ;;
    *) OPT=() ;;
  esac
  if [ "${#OPT[@]}" -gt 0 ]; then
    say "trying optional (phone pings): ${OPT[*]}"
    install_pkgs "$pm" "${OPT[@]}" >/dev/null 2>&1 || say "optional kdeconnect skipped"
  fi
  if [ "$pm" = "xbps" ]; then
    say "Void Linux: oco (Void Community Repository) - https://codeberg.org/oSoWoSo/oco (binary repo: https://repo.osowoso.org)"
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
# init/autostart templates for non-systemd setups
if [ -d "$PKGDIR/autostart" ]; then
  mkdir -p "$SHAREDIR/maid-bt/autostart"
  for f in "$PKGDIR"/autostart/*.desktop; do
    [ -f "$f" ] || continue
    copy_one "$f" "$SHAREDIR/maid-bt/autostart/$(basename "$f")"
  done
fi
if [ -d "$PKGDIR/init" ]; then
  mkdir -p "$SHAREDIR/maid-bt/init"
  cp -a "$PKGDIR/init/." "$SHAREDIR/maid-bt/init/" 2>/dev/null || true
fi
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

init_name() {
  local c
  c="$(ps -p 1 -o comm= 2>/dev/null || echo unknown)"
  case "$c" in
    systemd) echo systemd ;;
    openrc-init|openrc) echo openrc ;;
    runit) echo runit ;;
    dinit) echo dinit ;;
    s6-svscan|s6) echo s6 ;;
    init)
      if command -v rc-update >/dev/null 2>&1; then echo openrc
      elif command -v sv >/dev/null 2>&1; then echo runit
      elif command -v dinitctl >/dev/null 2>&1; then echo dinit
      else echo sysvinit
      fi ;;
    *) echo "$c" ;;
  esac
}

install_autostart() { # src dstname
  [ -f "$1" ] || return 1
  mkdir -p "$HOME/.config/autostart"
  copy_one "$1" "$HOME/.config/autostart/$2" 1
}

enable_user_service() { # name
  local svc="$1" init
  init="$(init_name)"
  case "$init" in
    systemd)
      systemctl --user daemon-reload 2>/dev/null || true
      systemctl --user enable --now "$svc.service" 2>/dev/null ;;
    openrc)
      if command -v rc-update >/dev/null 2>&1 && rc-update --user show >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/rc/init.d"
        copy_one "$PKGDIR/init/openrc-user/$svc" "$HOME/.config/rc/init.d/$svc"
        chmod +x "$HOME/.config/rc/init.d/$svc" 2>/dev/null || true
        rc-update --user add "$svc" default >/dev/null 2>&1 || true
        rc-service --user "$svc" start >/dev/null 2>&1 || true
      else
        install_autostart "$PKGDIR/autostart/$svc.desktop" "$svc.desktop" || \
        install_autostart "$PKGDIR/watcher/$svc.desktop" "$svc.desktop" || true
      fi ;;
    dinit)
      if command -v dinitctl >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/dinit.d"
        copy_one "$PKGDIR/init/dinit/$svc" "$HOME/.config/dinit.d/$svc"
        dinitctl --user enable "$svc" >/dev/null 2>&1 || true
        dinitctl --user start "$svc" >/dev/null 2>&1 || true
      else
        install_autostart "$PKGDIR/autostart/$svc.desktop" "$svc.desktop" || \
        install_autostart "$PKGDIR/watcher/$svc.desktop" "$svc.desktop" || true
      fi ;;
    *)
      install_autostart "$PKGDIR/autostart/$svc.desktop" "$svc.desktop" || \
      install_autostart "$PKGDIR/watcher/$svc.desktop" "$svc.desktop" || true ;;
  esac
}

disable_user_service() { # name
  local svc="$1" init
  init="$(init_name)"
  case "$init" in
    systemd) systemctl --user disable --now "$svc.service" 2>/dev/null || true ;;
    openrc)
      rc-service --user "$svc" stop >/dev/null 2>&1 || true
      rc-update --user del "$svc" default >/dev/null 2>&1 || true ;;
    dinit)
      dinitctl --user stop "$svc" >/dev/null 2>&1 || true
      dinitctl --user disable "$svc" >/dev/null 2>&1 || true ;;
  esac
  rm -f "$HOME/.config/autostart/$svc.desktop"
}

INIT_SYS="$(init_name)"
say "init system: $INIT_SYS"
if [ "$INIT_SYS" = "systemd" ]; then
  systemctl --user daemon-reload 2>/dev/null || true
else
  say "non-systemd init detected ($INIT_SYS): using user init/autostart integration"
fi

# buds-fallback is the core daemon; enable by default.
if enable_user_service buds-fallback; then
  say "buds-fallback enabled ($INIT_SYS)"
else
  warn "could not enable buds-fallback ($INIT_SYS)"
fi

# phone integration stays OFF unless asked: it opens a LAN port, so it is
# opt-in, never default.
PHONE_ON=0
if [ "$PIPED" = "0" ] && [ -t 0 ]; then
  printf 'Enable phone integration (bt-intent, LAN port 8899)? [y/N]: '
  read -r _ans
  case "$_ans" in [Yy]*) PHONE_ON=1 ;; esac
fi
if [ "$PHONE_ON" = "1" ]; then
  enable_user_service bt-intent || warn "could not enable bt-intent ($INIT_SYS)"
else
  disable_user_service bt-intent
  say "phone integration off (enable anytime by re-running installer or enabling bt-intent service)"
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
  # The watcher unit/autostart owns the daemon: avoid two daemons.
  rm -f "$HOME/.config/autostart/maid-watcher.desktop"
  enable_user_service maid-watcher || warn "could not enable maid-watcher ($INIT_SYS)"
else
  disable_user_service maid-watcher
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
# LE Audio vs A2DP-only guard:
# - 53-bt-a2dp-only.conf disables LE Audio to avoid silent dual-mode buds on
#   adapters/stacks with broken ISO/LE Audio transports (safe default off).
# - 54-bt-le-audio.conf enables LE Audio (BAP/LC3 roles/codecs) for capable
#   stacks/devices. Do not enable both at once.
A2DP_ON=0
LEAUDIO_ON=0
if [ "$PIPED" = "0" ] && [ -t 0 ]; then
  printf 'Enable LE Audio (BAP/LC3) support instead of A2DP-only guard? [y/N]: '
  read -r _wans4
  case "$_wans4" in
    [Yy]*)
      LEAUDIO_ON=1
      ;;
    *)
      printf 'Lock buds to classic A2DP (fixes silent LE Audio buds)? [y/N]: '
      read -r _wans4b
      case "$_wans4b" in [Yy]*) A2DP_ON=1 ;; esac
      ;;
  esac
fi
if [ "$LEAUDIO_ON" = "1" ]; then
  mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
  copy_one "$PKGDIR/wireplumber/54-bt-le-audio.conf" \
    "$HOME/.config/wireplumber/wireplumber.conf.d/54-bt-le-audio.conf"
  # avoid conflicting guard
  rm -f "$HOME/.config/wireplumber/wireplumber.conf.d/53-bt-a2dp-only.conf" 2>/dev/null || true
  if [ -f "$CONF" ]; then
    if grep -q '^LE_AUDIO=' "$CONF" 2>/dev/null; then
      sed -i 's/^LE_AUDIO=.*/LE_AUDIO=1/' "$CONF" 2>/dev/null || true
    else
      printf '\nLE_AUDIO=1\n' >> "$CONF" 2>/dev/null || true
    fi
  fi
  say "LE Audio enabled (54-bt-le-audio.conf, LE_AUDIO=1). Restart wireplumber to apply: systemctl --user restart wireplumber"
elif [ "$A2DP_ON" = "1" ]; then
  mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
  copy_one "$PKGDIR/wireplumber/53-bt-a2dp-only.conf" \
    "$HOME/.config/wireplumber/wireplumber.conf.d/53-bt-a2dp-only.conf"
  rm -f "$HOME/.config/wireplumber/wireplumber.conf.d/54-bt-le-audio.conf" 2>/dev/null || true
  say "a2dp-only on - restart wireplumber to apply: systemctl --user restart wireplumber"
else
  say "LE Audio/A2DP guard unchanged (enable LE Audio with 54-bt-le-audio.conf + LE_AUDIO=1, or A2DP-only with 53-bt-a2dp-only.conf)"
fi
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

say "done. Backups (if any): *.bak-${BACKUP_TS}"
mkdir -p "$HOME/MaidLogs" 2>/dev/null || true
say "logs live in ~/MaidLogs/ (visible folder) + journalctl --user -t maid-bt -t maid-watcher"
say "Next: pair+trust earbuds, add the 'Maid BT' widget (Add Widgets). restart plasmashell only if it is not listed; no logout needed."
say "Phone remote: see phone/README-macrodroid-tasker.md (MacroDroid/Tasker/OpenTasker; needs ~/.config/bt-intent.token + open TCP 8899)."
