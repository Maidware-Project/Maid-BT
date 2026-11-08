#!/usr/bin/env bash
# tui-install.sh - Maid BT's installer with an actual text UI.
#
# Same work as install.sh (which stays the engine: file copies, units,
# checks, token), but with screens, numbered picks, a doctor and an
# uninstall. It also learns which terminal is "the default" on this
# system and uses that for the follow-up windows (log tail, helper):
#   1. $TERMINAL or $TERM_PROGRAM if set explicitly
#   2. markers of the session running us (konsole/kitty/wezterm/...)
#   3. Plasma's own preference: kdeglobals TerminalService/Application
#   4. first installed among the usual suspects
# The answer is stored as TERMINAL_CMD= in bluetooth-buds.conf so
# reruns (and the other tools that read the file) agree on it.
# No dependencies beyond what Maid BT itself needs. Refuses to draw
# without a tty - install.sh plain mode covers that path.
# Usage: bash tui-install.sh
set -u

if [ ! -t 0 ]; then
  echo "tui needs a terminal - run: bash install.sh (plain mode)"
  exit 2
fi

_here_ti="${0%/*}"
case "$_here_ti" in "$0") _here_ti="." ;; esac
PKGDIR="$(cd "$_here_ti/.." 2>/dev/null && pwd || echo "$_here_ti")"
[ -f "$PKGDIR/install.sh" ] || PKGDIR="$_here_ti"
CONF="$HOME/.config/bluetooth-buds.conf"
LOGDIR="$HOME/MaidLogs"

# ------------------------------------------------------------------ ui
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  B=$'\e[1m' DIM=$'\e[2m' R=$'\e[0m'
  BL=$'\e[94m' CY=$'\e[96m' YL=$'\e[93m' GR=$'\e[92m' RD=$'\e[91m' INV=$'\e[7m'
else
  B="" DIM="" R="" BL="" CY="" YL="" GR="" RD="" INV=""
fi

ROWS=$(stty size 2>/dev/null | cut -d' ' -f1); ROWS=${ROWS:-24}
COLS=$(stty size 2>/dev/null | cut -d' ' -f2); COLS=${COLS:-80}
[ "$ROWS" -ge 1 ] 2>/dev/null || ROWS=24
[ "$COLS" -ge 1 ] 2>/dev/null || COLS=80

say()    { printf ' %s==>%s %s\n' "$BL" "$R" "$*"; }
ok()     { printf ' %s[ok]%s %s\n' "$GR" "$R" "$*"; }
warn()   { printf ' %s[!!] %s%s\n' "$YL" "$R" "$*"; }
bad()    { printf ' %s[bad] %s%s\n' "$RD" "$R" "$*"; }

rule() { printf '%*s\n' "${1:-$((COLS - 2))}" '' | tr ' ' '-'; }
head() {
  printf '\n%s MAID BT %s%s %s%s\n' "$INV" "$R" "$B" "$*" "$R"
  rule
}
hr()  { printf '%s%s%s\n' "$DIM" "$(printf '%*s' $((COLS - 2)) '' | tr ' ' '─')" "$R"; }
rel() { printf '%s' "$R"; }

ask_line() { # ask_line "prompt" -> $REPLY, input on the same line
  printf ' %s %s ' "$BL" "$*"; read -r REPLY
}

numbered_pick() {
  # numbered_pick "title" item1 item2... -> $PICK (1-based index) or empty
  [ $# -ge 1 ] || return 1
  local title="$1"; shift
  local -a items=("$@")
  [ "${#items[@]}" -ge 1 ] || return 1
  printf '\n'
  local i=1
  for it in "${items[@]}"; do
    printf '  %s%2d)%s %s\n' "$B" "$i" "$R" "$it"
    i=$((i + 1))
  done
  while :; do
    printf '  %s pick 1-%d, Enter for 1, or cancel: %s' "$B" "${#items[@]}" "$R"
    read -r REPLY
    case "${REPLY:-1}" in
      q|Q|cancel|Cancel) return 1 ;;
      *[!0-9]*|"") continue ;;
    esac
    [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "${#items[@]}" ] && { PICK="$REPLY"; return 0; }
  done
}

# ------------------------------------------------- default terminal
# every candidate checked that it actually exists before trusting it
detect_terminal() {
  TERMINAL_CMD=""
  local v
  for v in TERMINAL TERM_PROGRAM; do
    if [ -n "${!v:-}" ] && command -v "${!v}" >/dev/null 2>&1; then
      TERMINAL_CMD="${!v}"; return
    fi
  done
  if [ -n "${KONSOLE_VERSION:-}" ]; then TERMINAL_CMD="konsole"
  elif [ -n "${KITTY_WINDOW_ID:-}" ]; then TERMINAL_CMD="kitty"
  elif [ -n "${WEZTERM_EXECUTABLE:-}" ]; then TERMINAL_CMD="wezterm"
  elif [ -n "${GHOSTTY_RESOURCES_DIR:-}" ]; then TERMINAL_CMD="ghostty"
  elif [ -n "${GNOME_TERMINAL_SCREEN:-}" ]; then TERMINAL_CMD="gnome-terminal"
  elif [ "${TERM:-}" = "xterm-kitty" ]; then TERMINAL_CMD="kitty"
  fi
  [ -z "$TERMINAL_CMD" ] || command -v "$TERMINAL_CMD" >/dev/null 2>&1 || TERMINAL_CMD=""
  if [ -z "$TERMINAL_CMD" ] && command -v kreadconfig6 >/dev/null 2>&1; then
    local g
    for g in TerminalService TerminalApplication; do
      if guess="$(kreadconfig6 --file kdeglobals --group General --key "$g" 2>/dev/null)"; then
        case "$guess" in *.desktop) guess="${guess%.desktop}"; guess="${guess#org.kde.}" ;; esac
        if [ -n "$guess" ] && command -v "$guess" >/dev/null 2>&1; then
          TERMINAL_CMD="$guess"; return
        fi
      fi
    done
  fi
  if [ -z "$TERMINAL_CMD" ]; then
    local t
    for t in konsole alacritty kitty wezterm ghostty gnome-terminal lxterminal xterm; do
      command -v "$t" >/dev/null 2>&1 && { TERMINAL_CMD="$t"; return; }
    done
  fi
}

launch_in_terminal() {
  # spawn "$@" inside the detected default terminal, best effort
  detect_terminal
  if [ -z "$TERMINAL_CMD" ]; then
    warn "could not find a default terminal - run manually: $*"
    return 1
  fi
  say "opening $TERMINAL_CMD: $*"
  case "$TERMINAL_CMD" in
    konsole)        konsole -e "$@" >/dev/null 2>&1 & ;;
    kitty)          kitty "$@" >/dev/null 2>&1 & ;;
    alacritty)      alacritty -e "$@" >/dev/null 2>&1 & ;;
    wezterm)        wezterm start -- "$@" >/dev/null 2>&1 & ;;
    ghostty)        ghostty -e "$@" >/dev/null 2>&1 & ;;
    gnome-terminal) gnome-terminal -- "$@" >/dev/null 2>&1 & ;;
    lxterminal)     lxterminal -e "$@" >/dev/null 2>&1 & ;;
    xterm)          xterm -e "$@" >/dev/null 2>&1 & ;;
    *)              warn "no exec recipe for $TERMINAL_CMD - run manually: $*"; return 1 ;;
  esac
}

# ----------------------------------------------------- system facts
host_facts() {
  DISTRO="$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")" 2>/dev/null || DISTRO="unknown"
  PLASMA="$(plasmashell --version 2>/dev/null | head -n 1)"
  SESS="wayland"
  [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ] || SESS="headless?"
  [ -n "${WAYLAND_DISPLAY:-}" ] || SESS="x11 or unset"
  command -v bluetoothctl >/dev/null 2>&1 || bad "bluetooth missing: bluez package"
  command -v pactl       >/dev/null 2>&1 || bad "pactl missing: pulseaudio-utils/libpulse"
}

# ----------------------------------------------------- config write
write_config() {
  # $1 = BUDS_MAC, $2 = FALLBACK_SINK; keeps TERMINAL_CMD when known
  local mac="${1:-}" sink="${2:-}" t=""
  [ -f "$CONF" ] && t="$(sed -n 's/^TERMINAL_CMD="\(.*\)"/\1/p' "$CONF" 2>/dev/null | head -n 1)"
  detect_terminal; [ -n "$TERMINAL_CMD" ] || t=""
  {
    echo "# generated by tui-install.sh on $(date +%F)"
    echo "BUDS_MAC=\"$mac\""
    echo "FALLBACK_SINK=\"$sink\""
    [ -n "$t" ] && echo "TERMINAL_CMD=\"$t\""
  } > "$CONF"
  chmod 600 "$CONF" 2>/dev/null || true
  ok "wrote $CONF"
}

ensure_token() {
  if [ ! -f "$HOME/.config/bt-intent.token" ]; then
    ( umask 077; python3 -c "import secrets; print(secrets.token_urlsafe(24))" \
      > "$HOME/.config/bt-intent.token" ) 2>/dev/null \
      && ok "generated ~/.config/bt-intent.token (0600)" \
      || warn "python3 missing - phone integration token skipped"
  fi
}

# ------------------------------------------------------ device picks
# shared by install and config-only: sets REPLY_MAC + REPLY_SINK
pick_buds_and_sink() {
  local -a devs=()
  local d
  while IFS= read -r d; do devs+=("$d"); done < <(bluetoothctl devices 2>/dev/null | grep "^Device" || true)
  if [ "${#devs[@]}" = "0" ]; then
    warn "no paired bluetooth devices - pair first: bluetoothctl pair <MAC>"
    return 1
  fi
  numbered_pick "paired devices" "${devs[@]}" || return 1
  local m="${devs[$((PICK - 1))]}"           # "Device AA:BB:CC:DD:EE:FF name"
  m="$(echo "$m" | awk '{print $2}')"
  case "$m" in
    [0-9A-Fa-f][0-9A-Fa-f]:*|"") : ;;
    *) bad "odd MAC from device list: $m"; return 1 ;;
  esac
  local -a sinks=()
  local s
  while IFS= read -r s; do sinks+=("$s"); done < <(pactl list short sinks 2>/dev/null | awk '{print $2}' || true)
  if [ "${#sinks[@]}" = "0" ]; then
    warn "no audio sinks - is PipeWire running?"
    return 1
  fi
  local def
  def="$(pactl info 2>/dev/null | sed -n 's/^Default Sink: //p')"
  numbered_pick "audio sinks (fallback for when the buds are off)" "${sinks[@]}" || return 1
  local sink="${sinks[$((PICK - 1))]}"
  [ -n "$def" ] && [ "$sink" = "$def" ] && ok "$def was already the default: keeping"
  REPLY_MAC="$m"
  REPLY_SINK="$sink"
}

# ------------------------------------------------------ install flow
do_install() {
  head "full install / update"
  hr
  host_facts
  printf '  %s%s%s · %s\n' "$B" "$DISTRO" "$R" "$SESS"
  printf '  %s%s%s · terminal %s\n' "$B" "${PLASMA:-?}" "$R" "${TERMINAL_CMD:-none, will search}"
  local m=""
  # reuse an existing MAC so updates do not re-ask
  existing="$(sed -n 's/^BUDS_MAC="\(.*\)"/\1/p' "$CONF" 2>/dev/null | head -n 1)"
  if [ -n "$existing" ]; then
    printf '  %sexisting earbuds:%s %s%s%s\n' "$DIM" "$R" "$B" "$existing" "$R"
    ask_line "keep it? [y/N]"
    case "${REPLY,,}" in
      y|yes)
        # keep the learned fallback sink too, not just the MAC
        ks="$(sed -n 's/^FALLBACK_SINK="\(.*\)"/\1/p' "$CONF" 2>/dev/null | head -n 1)"
        do_install_steps "$existing" "${ks:-}"
        return
        ;;
    esac
  fi
  pick_buds_and_sink || return 1
  do_install_steps "$REPLY_MAC" "$REPLY_SINK"
}

do_install_steps() {
  local mac="${1:-}" sink="${2:-}"
  say "earbuds $mac · fallback $sink"
  write_config "$mac" "$sink"
  ensure_token
  # engine does file copies, docs, units; stdin is /dev/null so its
  # interactive blocks skip (config already written above)
  say "running install.sh engine..."
  if bash "$PKGDIR/install.sh" </dev/null; then
    ok "engine finished"
    # services are enabled by the engine; make sure they answer now
    systemctl --user daemon-reload 2>/dev/null || true
    host_facts; : # conflicts not needed
    printf '\n  %sn%s) tail maid-bt log in %s   %sr%s) open helper? ask later   %sENTER%s) done\n' \
      "$B" "$R" "${TERMINAL_CMD:-a terminal}" "$B" "$R" "$B" "$R"
    ask_line "follow up"
    case "${REPLY:-}" in
      n|N) launch_in_terminal tail -n 40 -f "$LOGDIR/maid-bt.log" ;;
      r|R) launch_in_terminal "$HOME/.local/bin/maid-bt-helper" 2>/dev/null || true ;;
    esac
    ok "all set: bluetooth-toggle.sh on|off|release|radio · porcelain for the tray"
  else
    bad "engine failed - scroll the output above"
    return 1
  fi
}

# ------------------------------------------------------ config only
do_config() {
  head "earbuds / fallback only"
  hr
  local cur_mac cur_sink
  cur_mac="$(sed -n 's/^BUDS_MAC="\(.*\)"/\1/p' "$CONF" 2>/dev/null | head -n 1)"
  cur_sink="$(sed -n 's/^FALLBACK_SINK="\(.*\)"/\1/p' "$CONF" 2>/dev/null | head -n 1)"
  printf '  current: buds %s%s%s · fallback %s%s%s\n' \
    "$B" "${cur_mac:-?}" "$R" "$B" "${cur_sink:-?}" "$R"
  if [ -z "$cur_mac" ]; then
    warn "config missing - run option 1 (install) once so the engine sets everything up"
    pause_or_done
    return
  fi
  ask_line "re-pick now? [y/N]"
  case "${REPLY,,}" in
    y|yes) : ;;
    *) say "kept as is"; return ;;
  esac
  pick_buds_and_sink || { pause_or_done; return; }
  write_config "$REPLY_MAC" "$REPLY_SINK"
  # the services read the conf when they start: a restart applies the
  # new MAC/sink without touching a single installed file
  say "restarting buds-fallback to apply..."
  if systemctl --user restart buds-fallback.service 2>/dev/null; then
    ok "config applied - no reinstall needed"
  else
    warn "could not restart buds-fallback.service"
  fi
  pause_or_done
}

# ---------------------------------------------------------- doctor
do_doctor() {
  head "system doctor"
  hr
  host_facts
  if [ -n "${PLASMA:-}" ]; then
    printf '  distro: %s%s%s · plasma %s%s%s\n' "$B" "$DISTRO" "$R" "$B" "$PLASMA" "$R"
  else
    printf '  distro: %s%s%s · plasma %s(n/a)%s\n' "$B" "$DISTRO" "$R" "$DIM" "$R"
  fi
  printf '  session: %s%s%s · default terminal %s%s%s\n' "$B" "$SESS" "$R" "$B" "${TERMINAL_CMD:-none}" "$R"
  local _desk="${XDG_CURRENT_DESKTOP:-n/a}"; printf '  desktop: %s%s%s\n' "$B" "$_desk" "$R"
  case "${_desk,,}" in
    *plasma*|*kde*) ok "KDE Plasma: supported (applet, integrations)" ;;
    *hyprland*|*sway*|*i3*) warn "compositor ${_desk}: CLI/TUI + bluetooth-toggle/maid-switch work; Plasma applet is KDE-only (support: partial/experimental, roadmap)" ;;
    *) say "compositor ${_desk}: core CLI/TUI expected to work; desktop integrations vary" ;;
  esac
  [ -f "$CONF" ] && grep -q "^BUDS_MAC=" "$CONF" 2>/dev/null \
    && ok "config exists: $CONF" \
    || warn "config missing/empty: $CONF"
  [ -d "$LOGDIR" ] && ok "logs: $LOGDIR" || warn "no $LOGDIR yet"
  systemctl --user is-active buds-fallback.service >/dev/null 2>&1 \
    && ok "buds-fallback.service active" \
    || warn "buds-fallback.service not running"
  if [ -d "$HOME/.local/share/plasma/plasmoids/com.local.btearbuds" ]; then
    ok "applet installed (KDE Plasma widget)"
  else
    case "${XDG_CURRENT_DESKTOP:-}" in
      *[Pp]lasma*|*[Kk][Dd][Ee]*) warn "applet not installed (~/.local/share/plasma/plasmoids)" ;;
      *) say "applet: KDE Plasma-only (not required on ${XDG_CURRENT_DESKTOP:-this session}; core CLI/TUI works)" ;;
    esac
  fi
  PORCELAIN="$(~/.local/bin/bluetooth-toggle.sh porcelain 2>/dev/null || echo unknown)"
  printf '  bluetooth state: %s%s%s\n' "$B" "$PORCELAIN" "$R"
  say "engine check:"
  bash "$PKGDIR/install.sh" --check 2>&1 | sed 's/^/    /' || true
  pause_or_done
}

pause_or_done() { printf '\n  %sENTER%s back to the menu' "$B" "$R"; read -r _; }

# ------------------------------------------------------ uninstall
do_uninstall() {
  head "uninstall"
  hr
  printf '  %sp%s) uninstall, keep configs (logs, MAC/tokens stay)\n' "$B" "$R"
  printf '  %sP%s) uninstall + purge everything (fresh machine)\n' "$B" "$R"
  printf '  %sq%s) cancel\n\n' "$B" "$R"
  ask_line "choice [p/P/q]:"
  case "${REPLY:-q}" in
    q|Q|cancel|Cancel|"") say "cancelled"; return ;;
    p)      say "engine uninstall (configs and logs stay)"
            bash "$PKGDIR/install.sh" --uninstall </dev/null || true ;;
    P)      say "engine uninstall with purge"
            bash "$PKGDIR/install.sh" --uninstall --purge </dev/null || true ;;
    *)      say "cancelled"; return ;;
  esac
  pause_or_done
}

# ------------------------------------------------------ boot intro
n64_boot() {
  # MAIDWARE boot, sized to the pane: letters fly in from alternating
  # edges of the screen to landing pads marked by spinning rotors, a
  # hue wave runs through the word as it assembles, and it all settles
  # bold. geometry comes from stty on every run, so it centers itself
  # on any pane. skips (boots straight up) when the terminal cannot
  # render it: no tty, dumb TERM, NO_COLOR, small pane, MAID_FAST=1.
  # any key skips ahead.
  [ -t 0 ] && [ -t 1 ] || return 0
  case "${TERM:-}" in "" | dumb | linux) return 0 ;; esac
  [ -z "${NO_COLOR:-}" ] || return 0
  [ "${MAID_FAST:-0}" = "1" ] && return 0
  [ "$COLS" -ge 34 ] 2>/dev/null || return 0
  [ "$ROWS" -ge 8 ] 2>/dev/null || return 0

  local -a letters=(M A I D W A R E)
  local -a rots=('|' '╱' '─' '╲')
  local -a pal=("\033[94m" "\033[96m" "\033[92m" "\033[93m" "\033[95m")
  local n=${#letters[@]}
  local slot=3
  local pad=$(( (COLS - n * slot) / 2 )); [ "$pad" -ge 0 ] || pad=0
  local -a reveal=()
  local i
  for ((i = 0; i < n; i++)); do reveal[i]=$((2 + i)); done
  local total=$((reveal[n - 1] + 2))
  local wordrow=$((ROWS / 2 - 2))

  printf '\033[?25l\033[0m'                    # hide cursor
  trap 'printf "\033[?25h\033[0m"' INT TERM    # never eat the cursor
  local f col glyph startcol
  for ((f = 0; f < total; f++)); do
    printf '\033[%d;1H\033[2K' "$wordrow"      # clear the word row once
    for ((i = 0; i < n; i++)); do
      col=$(( pad + i * slot + 1 ))              # where this letter lands
      if [ "$f" -ge "${reveal[i]}" ]; then
        # landed - the hue wave runs right to left as assembly grows
        glyph="$(printf "${pal[$(( (f + n - i) % ${#pal[@]} ))]}")"
        printf '\033[%d;%dH%s%s\033[0m' "$wordrow" "$col" "$glyph" "${letters[i]}"
      elif [ "$f" -lt $(( reveal[i] - 2 )) ]; then
        # landing pad: a dim rotor spins here until the letter moves in
        [ "$f" -gt 0 ] && printf '\033[%d;%dH\033[2m%s\033[0m' "$wordrow" "$col" \
          "${rots[$(( (f + i) % ${#rots[@]} ))]}"
      else
        # flying: two frames from the pane edge to the pad
        startcol=1; [ $(( i % 2 )) -eq 0 ] || startcol=$COLS
        [ "$f" -eq $(( reveal[i] - 2 )) ] && col=$startcol || col=$(( (col + startcol) / 2 ))
        glyph="$(printf "${pal[$(( (f + i) % ${#pal[@]} ))]}")"
        printf '\033[%d;%dH%s%s\033[0m' "$wordrow" "$col" "$glyph" "${letters[i]}"
      fi
    done
    # pacing + skip: clear k so EOF/timeout never reuses a stale byte.
    # in this pty env an EOF read returns rc=0 with k=EOT (0x04) - treat
    # EOT and NUL as "no key", so only a real keypress breaks the loop.
    k=""
    read -t 0.08 -n 1 -s k 2>/dev/null || true
    if [ -n "${k:-}" ] && [ "$k" != $'\004' ] && [ "$k" != $'\000' ]; then break; fi
  done
  # settle: assembled word, bold white, tagline one row down
  local word=""
  for ((i = 0; i < n; i++)); do word="$word ${letters[i]} "; done
  printf '\033[%d;1H\033[2K%*s\033[1;97m%s\033[0m' "$wordrow" "$pad" '' "$word"
  printf '\033[%d;1H\033[2K%*s\033[2m\u00b7 installer \u00b7 earbuds \u00b7 blue \u00b7\033[0m' \
    "$((wordrow + 1))" "$(( (COLS - 30) / 2 ))" ''
  sleep 0.45
  printf '\033[?25h\033[0m'
}

# ------------------------------------------------------ main menu
menu() {
  head "main menu"
  printf '  %stype a number and press Enter · %sq%s cancels%s\n\n' "$DIM" "$B" "$DIM" "$R"
  printf '  %s1%s) %sinstall / update%s  programs + config + services\n' "$B" "$R" "$B" "$R"
  printf '  %s2%s) %sconfig only%s       re-pick earbuds + fallback sink\n' "$B" "$R" "$B" "$R"
  printf '  %s3%s) %sdoctor%s           what does this machine say?\n' "$B" "$R" "$B" "$R"
  printf '  %s4%s) %suninstall%s        engine uninstall (--purge ask)\n' "$B" "$R" "$B" "$R"
  printf '  %sq%s) %squit%s\n' "$B" "$R" "$B" "$R"
  hr
  printf '  default terminal: %s%s%s   %s(used for log tail + helper windows)%s\n\n' \
    "$B" "${TERMINAL_CMD:-none found}" "$R" "$DIM" "$R"
  printf '  %s pick [1-4, q or cancel]: %s' "$B" "$R"
}

main() {
  n64_boot
  detect_terminal
  host_facts
  while :; do
    menu
    read -r REPLY
    case "${REPLY:-}" in
      1) do_install ;;
      2) do_config ;;
      3) do_doctor ;;
      4) do_uninstall ;;
      q|Q|cancel|Cancel|"") printf ' bye!\n'; return 0 ;;
    esac
  done
}

main "$@"
