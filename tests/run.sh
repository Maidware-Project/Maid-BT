#!/usr/bin/env bash
# Maid BT test suite. Hardware-free: no adapter needed (paths degrade to
# "off"), no state changes (no connects/disconnects/power toggles).
set -u
PKGDIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
ok()   { PASS=$((PASS+1)); echo "ok $PASS - $1"; }
fail() { echo "NOT OK - $1"; exit 1; }

echo "== syntax =="
for f in "$PKGDIR"/bin/*.sh "$PKGDIR"/install.sh; do
  bash -n "$f" || fail "bash -n $f"
done
command -v shellcheck >/dev/null 2>&1 && shellcheck -S error "$PKGDIR"/bin/*.sh "$PKGDIR"/install.sh || true
ok "syntax"

echo "== personal data =="
if grep -rn -E "90:BF|SmartAction|soundcore|Liberty|Mothership|10\.0\.0|/home/visa" \
    "$PKGDIR/bin" "$PKGDIR/README.md" "$PKGDIR/CHANGELOG.md" "$PKGDIR/install.sh" 2>/dev/null \
    | grep -v "s|/home/visa|"; then
  fail "personal string leaked"
fi
ok "no personal data"

echo "== installer dry run =="
rm -rf /tmp/maidbt-t; mkdir -p /tmp/maidbt-t
HOME=/tmp/maidbt-t bash "$PKGDIR/install.sh" --check >/dev/null 2>&1 || fail "install --check"
[ -e /tmp/maidbt-t/.local/bin/bluetooth-toggle.sh ] && fail "dry run wrote files"
ok "installer dry run clean"

echo "== porcelain state readout =="
state=$(bash "$PKGDIR/bin/bluetooth-toggle.sh" porcelain 2>/dev/null || true)
case "$state" in
  off|on|buds) ok "porcelain -> $state" ;;
  *) fail "porcelain garbage: $state" ;;
esac

echo "== unconfigured daemon refuses =="
rm -rf /tmp/maidbt-t; mkdir -p /tmp/maidbt-t
out=$(XDG_RUNTIME_DIR=/tmp/maidbt-t HOME=/tmp/maidbt-t timeout 3 bash "$PKGDIR/bin/buds-fallback.sh" 2>&1 || true)
echo "$out" | grep -q "not configured" || fail "refusal message missing: $out"
ok "unconfigured refusal"

echo "== hands-off suppresses auto-grab =="
rm -rf /tmp/maidbt-t; mkdir -p /tmp/maidbt-t
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="test-sink"\n' > /tmp/maidbt-t/.config-bluetooth-buds.conf
mkdir -p /tmp/maidbt-t/.config
mv /tmp/maidbt-t/.config-bluetooth-buds.conf /tmp/maidbt-t/.config/bluetooth-buds.conf
date +%s > /tmp/maidbt-t/bt-hands-off
export XDG_RUNTIME_DIR=/tmp/maidbt-t
out=$(HOME=/tmp/maidbt-t timeout 8 bash "$PKGDIR/bin/buds-fallback.sh" 2>&1 || true)
echo "$out" | grep -q "auto-connect attempt" && fail "grabbed despite hands-off"
ok "hands-off honored"
rm -f /tmp/maidbt-t/bt-hands-off
out=$(HOME=/tmp/maidbt-t timeout 14 bash "$PKGDIR/bin/buds-fallback.sh" 2>&1 || true)
echo "$out" | grep -q "auto-connect attempt" || fail "no attempt without hands-off"
ok "retry fires when free"

echo "== cleanup =="
rm -rf /tmp/maidbt-t
ok "cleanup"
echo "ALL $PASS PASSED"
