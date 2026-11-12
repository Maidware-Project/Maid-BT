#!/usr/bin/env bash
# this is truly my power
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
  echo "tui needs a terminal - run: bash install.sh --plain"
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

cls()  { printf '\033[H\033[2J'; }
rule() { printf '%*s\n' "${1:-$((COLS - 2))}" '' | tr ' ' '-'; }
head() {
  cls
  printf '%s MAID BT %s%s %s%s\n' "$INV" "$R" "$B" "$*" "$R"
  rule
}
hr()  { printf '%s%s%s\n' "$DIM" "$(printf '%*s' $((COLS - 2)) '' | tr ' ' '─')" "$R"; }
rel() { printf '%s' "$R"; }

ask_line() { # ask_line "prompt" -> $REPLY, input on the same line
  printf ' %s %s ' "$BL" "$*"; read -r REPLY || REPLY=""
}

_tty_restore() { stty "${_TTY_SAVED:-}" 2>/dev/null </dev/tty || true; printf '\033[?25h'; }

arrow_pick() {
  # arrow_pick "title" item1 item2... -> $PICK (1-based). Arrows move, Enter selects, q cancels; digits+Enter still work.
  [ $# -ge 1 ] || return 1
  local title="$1"; shift
  local -a items=("$@") n=${#items[@]} cur=1 typed="" k seq
  [ "$n" -ge 1 ] || return 1
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    local i=1; printf '\n'; for it in "${items[@]}"; do printf '  %s%2d)%s %s\n' "$B" "$i" "$R" "$it"; i=$((i+1)); done
    while :; do printf '  %s pick 1-%d, Enter for 1, or q: %s' "$B" "$n" "$R"; read -r REPLY
      case "${REPLY:-1}" in q|Q|cancel) return 1 ;; *[!0-9]*|"") continue ;; esac
      [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$n" ] && { PICK="$REPLY"; return 0; }
    done
  fi
  _TTY_SAVED=$(stty -g 2>/dev/null </dev/tty || true)
  trap '_tty_restore' INT TERM
  stty -echo -icanon min 1 time 0 2>/dev/null </dev/tty || true
  printf '\033[?25l\n\033[s'
  local i
  while :; do
    printf '\033[u\033[J  %s%s%s %s(↑↓ move · Enter select · type number · q cancel)%s\n' "$B" "$title" "$R" "$DIM" "$R"
    i=1
    for it in "${items[@]}"; do
      if [ "$i" -eq "$cur" ]; then printf '  %s❯ %2d) %s%s\033[K\n' "$CY$B" "$i" "$it" "$R"
      else printf '    %s%2d)%s %s\033[K\n' "$DIM" "$i" "$R" "$it"; fi
      i=$((i+1))
    done
    printf '  %s>%s %s\033[K' "$B" "$R" "${typed}"
    IFS= read -rsn1 k </dev/tty 2>/dev/null || k=""
    case "$k" in
      $'\x1b')
        IFS= read -rsn2 -t 0.08 seq </dev/tty 2>/dev/null || seq=""
        case "$seq" in '[A'|'OA') [ "$cur" -gt 1 ] && cur=$((cur-1)); typed="" ;; '[B'|'OB') [ "$cur" -lt "$n" ] && cur=$((cur+1)); typed="" ;; esac ;;
      ""|$'\n'|$'\r')
        if [ -n "$typed" ] && [[ "$typed" =~ ^[0-9]+$ ]] && [ "$typed" -ge 1 ] && [ "$typed" -le "$n" ]; then cur="$typed"; fi
        _tty_restore; trap - INT TERM; printf '\n'; PICK="$cur"; return 0 ;;
      q|Q) _tty_restore; trap - INT TERM; printf '\n'; return 1 ;;
      [0-9]) typed="${typed}${k}"; if [[ "$typed" =~ ^[0-9]+$ ]] && [ "$typed" -ge 1 ] && [ "$typed" -le "$n" ]; then cur="$typed"; fi ;;
      $'\x7f'|$'\b') typed="${typed%?}" ;;
    esac
  done
}

numbered_pick() { arrow_pick "$@"; }

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
  # interactive blocks skip (config already written above). --plain keeps
  # it out of the TUI and avoids any accidental menu redraw.
  hr
  say "running install engine (output below)..."
  hr
  local rc=0
  bash "$PKGDIR/install.sh" --plain </dev/null || rc=$?
  hr
  if [ "$rc" -eq 0 ]; then
    ok "engine finished"
    systemctl --user daemon-reload 2>/dev/null || true
    printf '\n  %sn%s) tail maid-bt log in %s   %sr%s) open helper   %sENTER%s) back to menu\n' \
      "$B" "$R" "${TERMINAL_CMD:-a terminal}" "$B" "$R" "$B" "$R"
    ask_line "follow up"
    case "${REPLY:-}" in
      n|N) launch_in_terminal tail -n 40 -f "$LOGDIR/maid-bt.log" ;;
      r|R) launch_in_terminal "$HOME/.local/bin/maid-bt-helper" 2>/dev/null || true ;;
    esac
    ok "all set: bluetooth-toggle.sh on|off|release|radio · porcelain for the tray"
  else
    bad "engine failed (rc=$rc) - read the output above"
  fi
  pause_or_done
  return "$rc"
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
    *) say "kept as is"; pause_or_done; return ;;
  esac
  pick_buds_and_sink || { pause_or_done; return; }
  write_config "$REPLY_MAC" "$REPLY_SINK"
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
  local _desk="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-n/a}}}"
  printf '  desktop: %s%s%s' "$B" "$_desk" "$R"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x gpuishell >/dev/null 2>&1 && printf ' %s(+ GPUIShell/gpuishell)%s' "$DIM" "$R"
    pgrep -x horizon >/dev/null 2>&1 && printf ' %s(+ Event Horizon)%s' "$DIM" "$R"
    pgrep -x kineticwe >/dev/null 2>&1 && printf ' %s(+ KineticWE)%s' "$DIM" "$R"
  fi
  printf '\n'
  case "${_desk,,}" in
    *plasma*|*kde*) ok "KDE Plasma: supported (applet, integrations)" ;;
    *hyprland*|*sway*|*i3*) warn "compositor ${_desk}: CLI/TUI + bluetooth-toggle/maid-switch work; Plasma applet is KDE-only (partial/experimental; adapters iterative)" ;;
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
    p)      hr
            say "engine uninstall (configs and logs stay)"
            bash "$PKGDIR/install.sh" --plain --uninstall </dev/null || true ;;
    P)      hr
            say "engine uninstall with purge"
            bash "$PKGDIR/install.sh" --plain --uninstall --purge </dev/null || true ;;
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
  [ -t 1 ] || return 0
  case "${TERM:-}" in "" | linux) return 0 ;; esac
  [ -z "${NO_COLOR:-}" ] || return 0
  [ "${MAID_FAST:-0}" = "1" ] && return 0
  # refresh size from pty (globals may be stale in script/CI)
  local _sz; _sz="$(stty size 2>/dev/null </dev/tty)" || _sz="$(stty size 2>/dev/null)" || _sz=""
  if [ -n "$_sz" ]; then ROWS="${_sz%% *}"; COLS="${_sz##* }"; fi
  [ "${ROWS:-0}" -ge 1 ] 2>/dev/null || ROWS=24
  [ "${COLS:-0}" -ge 1 ] 2>/dev/null || COLS=80
  [ "$COLS" -ge 34 ] 2>/dev/null || COLS=80
  [ "$ROWS" -ge 8 ] 2>/dev/null || ROWS=24

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

update_from_github() {
  head "update (latest)"
  hr
  if ! command -v curl >/dev/null 2>&1; then bad "curl not found"; pause_or_done; return 1; fi
  local repo="Maidware-Project/Maid-BT"
  local tag url url_cb url_tag_cb url_main_cb
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -n "$tag" ]; then
    url="https://raw.githubusercontent.com/$repo/$tag/install.sh"
    url_tag_cb="https://codeberg.org/Maidware_Project/Maid-BT/raw/tag/$tag/install.sh"
  else
    url="https://raw.githubusercontent.com/$repo/main/install.sh"
    url_tag_cb=""
  fi
  url_main_cb="https://codeberg.org/Maidware_Project/Maid-BT/raw/branch/main/install.sh"
  say "fetching official installer: $url"
  local tmp; tmp="$(mktemp /tmp/maid-bt-update.XXXXXX.sh)"
  if curl -fsSL "$url" -o "$tmp" 2>/dev/null \
    || { [ -n "$url_tag_cb" ] && curl -fsSL "$url_tag_cb" -o "$tmp" 2>/dev/null; } \
    || curl -fsSL "$url_main_cb" -o "$tmp" 2>/dev/null; then
    ok "downloaded; running latest installer (--plain, keeps your config flow safe)"
    hr
    bash "$tmp" --plain </dev/null || warn "latest installer exited $?"
    rm -f "$tmp"
  else
    bad "download failed (tried GitHub and Codeberg)"
    rm -f "$tmp"
  fi
  pause_or_done
}

# ------------------------------------------------------ main menu
menu_draw() {
  head "main menu"
  printf '  %s↑↓/arrows or type a number · Enter select · q quit/cancel%s\n\n' "$DIM" "$R"
  hr
  printf '  default terminal: %s%s%s   %s(used for log tail + helper windows)%s\n\n' \
    "$B" "${TERMINAL_CMD:-none found}" "$R" "$DIM" "$R"
}

menu_pick_action() {
  # sets REPLY to 1-6 or q
  local -a labels=("install / update  — programs + config + services"
                   "reinstall         — re-pick config, then install"
                   "update from GitHub — latest official installer"
                   "config only       — re-pick earbuds + fallback sink"
                   "doctor            — what does this machine say?"
                   "uninstall         — remove Maid BT (--purge ask)"
                   "quit")
  local n=${#labels[@]} cur=1 typed="" k seq i first=1
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf '  %s pick [1-6, q]: %s' "$B" "$R"; read -r REPLY || REPLY="q"; return 0
  fi
  _TTY_SAVED=$(stty -g 2>/dev/null </dev/tty || true)
  trap '_tty_restore' INT TERM
  stty -echo -icanon min 1 time 0 2>/dev/null </dev/tty || true
  printf '\033[?25l\n\033[s'
  local first=1
  while :; do
    printf '\033[u\033[J'
    i=1
    for it in "${labels[@]}"; do
      if [ "$i" -eq "$cur" ]; then printf '  %s❯ %s%s\033[K\n' "$CY$B" "$it" "$R"
      else printf '    %s%s%s\033[K\n' "$DIM" "$it" "$R"; fi
      i=$((i+1))
    done
    printf '  %s>%s %s\033[K' "$B" "$R" "${typed}"
    IFS= read -rsn1 k </dev/tty 2>/dev/null || k=""
    case "$k" in
      $'\x1b')
        IFS= read -rsn2 -t 0.08 seq </dev/tty 2>/dev/null || seq=""
        case "$seq" in '[A'|'OA') [ "$cur" -gt 1 ] && cur=$((cur-1)); typed="" ;; '[B'|'OB') [ "$cur" -lt "$n" ] && cur=$((cur+1)); typed="" ;; esac ;;
      ""|$'\n'|$'\r')
        if [ -n "$typed" ] && [[ "$typed" =~ ^[0-9]+$ ]] && [ "$typed" -ge 1 ] && [ "$typed" -le 6 ]; then cur="$typed"; fi
        _tty_restore; trap - INT TERM; printf '\n'
        [ "$cur" -eq 7 ] && REPLY="q" || REPLY="$cur"; return 0 ;;
      q|Q) _tty_restore; trap - INT TERM; printf '\n'; REPLY="q"; return 0 ;;
      [1-6]) typed="$k"; cur="$k" ;;
      $'\x7f'|$'\b') typed="" ;;
    esac
  done
}

main() {
  n64_boot
  detect_terminal
  host_facts
  while :; do
    menu_draw
    menu_pick_action
    case "${REPLY:-}" in
      1) do_install ;;
      2) head "reinstall"; hr; host_facts; pick_buds_and_sink && do_install_steps "$REPLY_MAC" "$REPLY_SINK" || pause_or_done ;;
      3) update_from_github ;;
      4) do_config ;;
      5) do_doctor ;;
      6) do_uninstall ;;
      q|Q|cancel|Cancel|"") printf ' bye!\n'; return 0 ;;
    esac
  done
}

main "$@"
