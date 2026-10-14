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
python3 -m py_compile "$PKGDIR"/watcher/maid-watcher "$PKGDIR"/watcher/maid_core/*.py || fail "watcher py_compile"
ok "syntax"

echo "== personal data =="
# NOTE: watcher/maid-watcher.desktop carries an Exec=/home/visa/... path on
# purpose (install.sh rewrites it, same convention as desktop/*.desktop).
if grep -rn -E "90:BF|SmartAction|soundcore|Liberty|Mothership|10\.0\.0|/home/visa" \
    "$PKGDIR/bin" "$PKGDIR/watcher/maid-watcher" "$PKGDIR"/watcher/maid_core \
    "$PKGDIR/watcher/config.example.json" \
    "$PKGDIR/README.md" "$PKGDIR/CHANGELOG.md" "$PKGDIR/install.sh" 2>/dev/null \
    | grep -vE "s\\|/home/visa"; then
  fail "personal string leaked"
fi
ok "no personal data"

echo "== watcher extras =="
[ -x "$PKGDIR/watcher/maid-watcher" ] || fail "watcher not executable"
python3 - <<EOF || fail "watcher unit checks"
import sys
sys.path.insert(0, "$PKGDIR/watcher")
from maid_core.config import laptop_mode
assert laptop_mode({"laptop": {"mode": "on"}}) is True
assert laptop_mode({"laptop": {"mode": "off"}}) is False
assert laptop_mode({}) is False
print("watcher unit checks passed")
EOF
[ -f "$PKGDIR/watcher/maid-watcher.desktop" ] || fail "watcher desktop missing"
[ -f "$PKGDIR/watcher/maid-watcher.service" ] || fail "watcher unit missing"
grep -q "MemoryMax" "$PKGDIR/watcher/maid-watcher.service" || fail "watcher unit has no RAM cap"
grep -q "maid_audit maid-bt" "$PKGDIR/bin/bluetooth-toggle.sh" || fail "toggle not audited"
grep -q "audit-lib.sh" "$PKGDIR/bin/buds-fallback.sh" || fail "fallback audit lib missing"
grep -q "MaidLogs" "$PKGDIR/bin/audit-lib.sh" || fail "audit log dir missing"
grep -q "def audit" "$PKGDIR/watcher/maid_core/notify.py" || fail "watcher audit missing"
grep -q "MaidLogs" "$PKGDIR/install.sh" || fail "installer hides log location"
grep -q 'rm -f "$HOME/.config/autostart/maid-watcher.desktop"' "$PKGDIR/install.sh" || fail "installer allows double daemon"
[ -f "$PKGDIR/wireplumber/51-bt-no-suspend.conf" ] || fail "no-suspend conf missing"
grep -q "session.suspend-timeout-seconds" \
  "$PKGDIR/wireplumber/51-bt-no-suspend.conf" || fail "suspend knob missing"
grep -q "bluez_output" \
  "$PKGDIR/wireplumber/51-bt-no-suspend.conf" || fail "bluez match missing"
ok "watcher extras"

echo "== degraded mode (missing/outdated deps) =="
mkdir -p /tmp/maidbt-emptybin
( export PATH=/tmp/maidbt-emptybin
  /usr/bin/bash "$PKGDIR/bin/bluetooth-toggle.sh" status > /tmp/maidbt-deg.out 2>&1
  [ "$?" -eq 2 ] || fail "no clean exit without bluetoothctl"
  grep -q "missing required tool: bluetoothctl" /tmp/maidbt-deg.out || fail "no clean missing-tool message"
  ! grep -q "command not found" /tmp/maidbt-deg.out || fail "tool noise leaked" )
ok "clean failure without bluetoothctl"
/usr/bin/python3 - "$PKGDIR/watcher" <<'PYEOF2' || fail "watcher degraded helpers crashed"
import os, sys
os.environ["PATH"] = "/tmp/maidbt-emptybin"
sys.path.insert(0, sys.argv[1])
from maid_core import audio
assert audio.bluez_card_id("AA:BB:CC:DD:EE:FF") is None
assert audio.set_profile_a2dp("AA:BB:CC:DD:EE:FF") is False
assert audio.find_app_streams(["discord"]) == []
assert audio.active_profile("AA:BB:CC:DD:EE:FF") is None
print("watcher degraded helpers clean")
PYEOF2
ok "watcher helpers survive missing tools"
rm -rf /tmp/maidbt-emptybin /tmp/maidbt-deg.out

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
rm -rf /tmp/maidbt-t; mkdir -p /tmp/maidbt-t/stubs /tmp/maidbt-t/.config
cat > /tmp/maidbt-t/stubs/bluetoothctl <<'EOF'
#!/bin/bash
# fake adapter: always powered, buds never connected, connects always fail
case "$*" in
  *show*) echo "Controller AA:BB:CC:DD:EE:FF test"; echo "	Powered: yes" ;;
  *info*) echo "Device 11:22:33:44:55:66 (public)"; echo "	Connected: no" ;;
  *connect*) echo "Failed to connect: not available"; exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x /tmp/maidbt-t/stubs/bluetoothctl
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="test-sink"\n' > /tmp/maidbt-t/.config/bluetooth-buds.conf
export PATH="/tmp/maidbt-t/stubs:$PATH"
date +%s > /tmp/maidbt-t/bt-hands-off
export XDG_RUNTIME_DIR=/tmp/maidbt-t
out=$(HOME=/tmp/maidbt-t timeout 8 bash "$PKGDIR/bin/buds-fallback.sh" 2>&1 || true)
echo "$out" | grep -q "auto-connect attempt" && fail "grabbed despite hands-off"
ok "hands-off honored"
rm -f /tmp/maidbt-t/bt-hands-off
out=$(HOME=/tmp/maidbt-t timeout 14 bash "$PKGDIR/bin/buds-fallback.sh" 2>&1 || true)
echo "$out" | grep -q "auto-connect attempt" || fail "no attempt without hands-off"
ok "retry fires when free"

echo "== generic headset auto-switch =="
rm -rf /tmp/maidbt-g; mkdir -p /tmp/maidbt-g/stubs /tmp/maidbt-g/.config /tmp/maidbt-g/state
cat > /tmp/maidbt-g/stubs/bluetoothctl <<'EOF'
#!/bin/bash
case "$*" in
  *show*) printf 'Controller STUB\n\tPowered: yes\n' ;;
  *Paired*) echo "Device AA:BB:CC:DD:EE:FF Test Headset" ;;
  *11:22:33:44:55:66*) echo "Connected: no" ;;
  *AA:BB:CC:DD:EE:FF*) printf 'UUID: Audio Sink (0000110b-0000-1000-8000-00805f9b34fb)\n\tConnected: no\nAlias: Test Headset\n' ;;
  *info*) echo "Alias: Test Headset" ;;
  *connect*) echo "Failed to connect"; exit 1 ;;
  *) exit 1 ;;
esac
exit 0
EOF
cat > /tmp/maidbt-g/stubs/pactl <<'EOF'
#!/bin/bash
S="${STUBSTATE:-/tmp}"
case "$*" in
  *short*sinks*) cat "$S/sinks" 2>/dev/null ;;
  *short*sink-inputs*) echo "11 testsink 10 PipeWire" ;;
  *info*) echo "Default Sink: $(cat "$S/default" 2>/dev/null)" ;;
  *set-default-sink*) echo "set-default $2" >> "$S/calls"; echo "$2" > "$S/default" ;;
  *suspend-sink*) : ;;
  *move-sink-input*) echo "move $2 -> $3" >> "$S/calls" ;;
  *list*cards*) : ;;
esac
exit 0
EOF
chmod +x /tmp/maidbt-g/stubs/*
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="testsink-fallback"\n' > /tmp/maidbt-g/.config/bluetooth-buds.conf
export STUBSTATE=/tmp/maidbt-g/state
export PATH="/tmp/maidbt-g/stubs:$PATH" XDG_RUNTIME_DIR=/tmp/maidbt-g
echo "11 testsink" > /tmp/maidbt-g/state/sinks
echo "testsink" > /tmp/maidbt-g/state/default
HOME=/tmp/maidbt-g timeout 30 bash "$PKGDIR/bin/buds-fallback.sh" > /tmp/maidbt-g/daemon.log 2>&1 &
DPID=$!
sleep 3
[ -f /tmp/maidbt-g/state/calls ] && fail "switched with nothing new"
grep -q "priority connect attempt to headset AA:BB:CC:DD:EE:FF" /tmp/maidbt-g/daemon.log || fail "no priority sweep for paired headset"
ok "silent on steady state + priority sweep attempted"
echo "77 bluez_output.AA_BB_CC_DD_EE_FF.1" >> /tmp/maidbt-g/state/sinks
sleep 5
grep -q "set-default bluez_output.AA_BB_CC_DD_EE_FF.1" /tmp/maidbt-g/state/calls || fail "no auto-switch to new headset"
grep -q "move 11 -> bluez_output.AA_BB_CC_DD_EE_FF.1" /tmp/maidbt-g/state/calls || fail "streams not moved"
[ "$(cat /tmp/maidbt-g/state/default)" = "bluez_output.AA_BB_CC_DD_EE_FF.1" ] || fail "default not flipped"
ok "new headset grabbed + routed"
n_before=$(grep -c "testsink-fallback" /tmp/maidbt-g/state/calls || true)
sed -i '/bluez_output/d' /tmp/maidbt-g/state/sinks
sleep 7
n_after=$(grep -c "testsink-fallback" /tmp/maidbt-g/state/calls || true)
[ "$n_after" -gt "$n_before" ] || fail "vanished default not parked"
ok "vanished device parked on fallback"
kill "$DPID" 2>/dev/null || true
wait 2>/dev/null || true
rm -rf /tmp/maidbt-g
export PATH=$(echo "$PATH" | sed 's|/tmp/maidbt-g/stubs:||')
unset STUBSTATE

echo "== cleanup =="
rm -rf /tmp/maidbt-t
ok "cleanup"
echo "ALL $PASS PASSED"
