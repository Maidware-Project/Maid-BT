#!/usr/bin/env bash
# audit-lib: one-line audit trail for Maid BT scripts.
# Writes to the journal AND to ~/MaidLogs/<tag>.log (visible folder).
# Source it with the guard so double-sourcing is harmless:
#   [ -z "${AUDIT_LIB_LOADED:-}" ] && { . "$_here/audit-lib.sh" || . "$HOME/.local/bin/audit-lib.sh"; }
AUDIT_LIB_LOADED=1
MAID_LOGDIR="$HOME/MaidLogs"

maid_audit() {
  local tag="$1"; shift
  logger -t "$tag" -- "$*" 2>/dev/null || true
  mkdir -p "$MAID_LOGDIR" 2>/dev/null || return 0
  printf '%s %s\n' "$(date +%F_%T)" "$*" >> "$MAID_LOGDIR/$tag.log" 2>/dev/null || true
}

# need <cmd> [hint]: hard requirement with a clean error (no traceback,
# no 127). Call it for tools the script cannot run without.
need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "missing required tool: $1${2:+ ($2)}" >&2
  echo "install it with your package manager, then rerun." >&2
  exit 2
}
