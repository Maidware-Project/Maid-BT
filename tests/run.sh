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
# every shipped file is scanned, the desktop Exec included: those carry a
# @HOME@ placeholder that install.sh rewrites to this $HOME, so the repo
# never names a machine's own paths.
if grep -rn --exclude-dir=__pycache__ -iE "([0-9a-f]{2}:){5}[0-9a-f]{2}|/(home|Users)/[^/[:space:]]+|(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}" \
    "$PKGDIR/bin" "$PKGDIR/desktop" "$PKGDIR/plasmoid" \
    "$PKGDIR/watcher/maid-watcher" "$PKGDIR"/watcher/maid_core \
    "$PKGDIR/watcher/maid-watcher.desktop" "$PKGDIR/watcher/config.example.json" \
    "$PKGDIR/README.md" "$PKGDIR/CHANGELOG.md" "$PKGDIR/install.sh" 2>/dev/null \
    | grep -v "AA:BB:CC:DD:EE:FF"; then
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
[ -f "$PKGDIR/wireplumber/52-bt-max-quality.conf" ] || fail "max-quality conf missing"
grep -q "bluez5.codecs" \
  "$PKGDIR/wireplumber/52-bt-max-quality.conf" || fail "codec ladder missing"
grep -q "bluez5.enable-sbc-xq" \
  "$PKGDIR/wireplumber/52-bt-max-quality.conf" || fail "sbc-xq knob missing"
grep -q "QUALITY_LOCK" "$PKGDIR/bin/buds-fallback.sh" || fail "quality lock missing (fallback)"
grep -q "QUALITY_LOCK" "$PKGDIR/bin/bluetooth-toggle.sh" || fail "quality lock missing (toggle)"
grep -q "QUALITY_LOCK" "$PKGDIR/bluetooth-buds.conf.example" || fail "quality lock undocumented"
grep -q "52-bt-max-quality" "$PKGDIR/install.sh" || fail "installer skips max-quality"
ok "watcher extras"
grep -q "fallback_grab" "$PKGDIR/watcher/config.example.json" || fail "grab config missing"
grep -q "phones_up" "$PKGDIR/watcher/maid-watcher" || fail "grab logic missing"
ok "fallback grab present"
/usr/bin/python3 - "$PKGDIR/watcher" <<'PYEOF2' || fail "router unit failed"
import sys
sys.path.insert(0, sys.argv[1])
from maid_core import audio
moved = []
def fake(args):
    if args == ["get-default-sink"]:
        return "bluez_output.XX.1\n"
    if args == ["list", "sinks"]:
        return "Sink #44\n\tName: alsa_output.usb-dac.analog-stereo\nSink #61\n\tName: bluez_output.XX.1\n"
    if args == ["list", "sink-inputs"]:
        return ("Sink Input #10\n\tSink: 44\n\tapplication.name = \"Vesktop\"\n"
                "Sink Input #11\n\tSink: 61\n\tapplication.name = \"Firefox\"\n")
    if args[:1] == ["move-sink-input"]:
        moved.append(tuple(args))
        return ""
    return ""
audio._pactl = fake
assert audio.route_comms_to_default() == 1, "should move 1 stranded stream"
assert moved == [("move-sink-input", "10", "bluez_output.XX.1")], moved
print("router unit passed")
PYEOF2
ok "comms router unit"
mkdir -p /tmp/btstub
printf '#!/bin/bash\necho "2: bnep0: <UP> mtu 1500"\necho "    inet 192.168.44.1/24 scope global bnep0"\n' > /tmp/btstub/ip
chmod +x /tmp/btstub/ip
PATH=/tmp/btstub:/usr/bin:/bin /usr/bin/python3 - "$PKGDIR/watcher" <<'PYEOF2' || fail "bnep detect failed"
import os
import sys
import types
from unittest.mock import MagicMock
sys.path.insert(0, sys.argv[1])
for m in ["dbus", "dbus.mainloop", "dbus.mainloop.glib", "gi", "gi.repository"]:
    sys.modules[m] = MagicMock()
g = {"__name__": "bt-test", "__file__": os.path.join(sys.argv[1], "maid-watcher")}
exec(compile(open(os.path.join(sys.argv[1], "maid-watcher")).read(), "maid-watcher", "exec"), g)
assert g["Daemon"]._bnep_up() is True, "bnep with inet not detected"
print("bnep detect passed")
PYEOF2
PATH=/usr/bin:/bin /usr/bin/python3 - "$PKGDIR/watcher" <<'PYEOF3' || fail "bnep absent misdetected"
import os
import sys
import types
from unittest.mock import MagicMock
sys.path.insert(0, sys.argv[1])
for m in ["dbus", "dbus.mainloop", "dbus.mainloop.glib", "gi", "gi.repository"]:
    sys.modules[m] = MagicMock()
g = {"__name__": "bt-test", "__file__": os.path.join(sys.argv[1], "maid-watcher")}
exec(compile(open(os.path.join(sys.argv[1], "maid-watcher")).read(), "maid-watcher", "exec"), g)
assert g["Daemon"]._bnep_up() is False, "no bnep must be False"
print("bnep absent passed")
PYEOF3
rm -rf /tmp/btstub
ok "bluetooth fallback link detect"
mkdir -p /tmp/micstub
cat > /tmp/micstub/pw-dump <<'STUBEOF'
#!/bin/bash
cat <<'JSONEOF'
[{"id": 7, "type": "PipeWire:Interface:Node", "info": {"state": "running", "props": {"media.class": "Stream/Input/Audio", "application.name": "Vesktop", "node.name": "chromium_capture"}}},
{"id": 9, "type": "PipeWire:Interface:Node", "info": {"state": "suspended", "props": {"media.class": "Stream/Input/Audio", "application.name": "Firefox", "node.name": "x"}}}
]
JSONEOF
STUBEOF
chmod +x /tmp/micstub/pw-dump
PATH=/tmp/micstub:/usr/bin:/bin /usr/bin/python3 - "$PKGDIR/watcher" <<'PYEOF2' || fail "mic holder detect failed"
import sys
sys.path.insert(0, sys.argv[1])
from maid_core import audio
holders = audio.mic_holders()
assert holders == [("Vesktop", "chromium_capture")], holders
print("mic holder detect passed")
PYEOF2
ok "mic holder detect"
rm -rf /tmp/micstub

echo "== degraded mode (missing/outdated deps) =="
mkdir -p /tmp/maidbt-emptybin
# strip PATH only for the script; check its output with a normal PATH, or
# grep itself can't be found and the check below reads as a false failure
( export PATH=/tmp/maidbt-emptybin
  /usr/bin/bash "$PKGDIR/bin/bluetooth-toggle.sh" status > /tmp/maidbt-deg.out 2>&1 )
code=$?
[ "$code" -eq 2 ] || fail "no clean exit without bluetoothctl (got $code)"
grep -q "missing required tool: bluetoothctl" /tmp/maidbt-deg.out || fail "no clean missing-tool message"
! grep -q "command not found" /tmp/maidbt-deg.out || fail "tool noise leaked"
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
# stubbed like the rest of the suite: no real bluez/pulse needed here
rm -rf /tmp/maidbt-p && mkdir -p /tmp/maidbt-p/stubs /tmp/maidbt-p/.config
cat > /tmp/maidbt-p/stubs/bluetoothctl <<'EOF'
#!/bin/bash
# fake adapter: powered, buds never connected
case "$*" in
  *show*) echo "Controller AA:BB:CC:DD:EE:FF test"; echo "Powered: yes" ;;
  *info*) echo "Device 11:22:33:44:55:66 (public)"; echo "Connected: no" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-p/stubs/pactl
chmod +x /tmp/maidbt-p/stubs/*
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="test-sink"\n' > /tmp/maidbt-p/.config/bluetooth-buds.conf
state=$(PATH="/tmp/maidbt-p/stubs:$PATH" HOME=/tmp/maidbt-p bash "$PKGDIR/bin/bluetooth-toggle.sh" porcelain 2>/dev/null || true)
case "$state" in
  off|on|buds) ok "porcelain -> $state" ;;
  *) fail "porcelain garbage (stub adapter, expected off|on|buds): '$state'" ;;
esac
rm -rf /tmp/maidbt-p

echo "== unconfigured daemon refuses =="
# buds-fallback checks `need bluetoothctl` / `need pactl` before it reads its
# config, so without stubs this test passes or fails on whatever the host has
# installed - ubuntu ci has no bluez and never reached the refusal we want.
rm -rf /tmp/maidbt-t; mkdir -p /tmp/maidbt-t/stubs
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-t/stubs/bluetoothctl
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-t/stubs/pactl
chmod +x /tmp/maidbt-t/stubs/*
out=$(PATH="/tmp/maidbt-t/stubs:$PATH" XDG_RUNTIME_DIR=/tmp/maidbt-t HOME=/tmp/maidbt-t timeout 3 bash "$PKGDIR/bin/buds-fallback.sh" 2>&1 || true)
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
# silence cross-boundary side effects: no real phone pings, no real popups.
printf '#!/bin/bash\nexit 1\n' > /tmp/maidbt-t/stubs/kdeconnect-cli
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-t/stubs/notify-send
# pactl is the daemon's second hard requirement, and ubuntu ci has no
# pulseaudio-utils - without this stub the daemon quits before ever trying.
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-t/stubs/pactl
chmod +x /tmp/maidbt-t/stubs/*
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
# silence cross-boundary side effects: no real phone pings, no real popups.
printf '#!/bin/bash\nexit 1\n' > /tmp/maidbt-g/stubs/kdeconnect-cli
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-g/stubs/notify-send
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

echo "== quality lock pins LDAC =="
rm -rf /tmp/maidbt-q; mkdir -p /tmp/maidbt-q/stubs /tmp/maidbt-q/.config /tmp/maidbt-q/state
cat > /tmp/maidbt-q/stubs/bluetoothctl <<'EOF'
#!/bin/bash
case "$*" in
  *show*) printf 'Controller STUB\n\tPowered: yes\n' ;;
  *11:22:33:44:55:66*) printf 'Device 11:22:33:44:55:66 Test Buds\n\tConnected: yes\n' ;;
  *) exit 1 ;;
esac
exit 0
EOF
cat > /tmp/maidbt-q/stubs/pactl <<'EOF'
#!/bin/bash
S="${STUBSTATE:-/tmp}"
case "$*" in
  *short*cards*) echo "99 bluez_card.11_22_33_44_55_66" ;;
  *list*cards*) printf 'Card #99\n\tName: bluez_card.11_22_33_44_55_66\n\tActive Profile: a2dp-sink-sbc\n' ;;
  *set-card-profile*) echo "profile $2 -> $3" >> "$S/calls" ;;
  *short*sinks*) echo "77 bluez_output.11_22_33_44_55_66.1" ;;
  *short*sink-inputs*) : ;;
  *info*) echo "Default Sink: bluez_output.11_22_33_44_55_66.1" ;;
  *set-default-sink*|*suspend-sink*|*move-sink-input*) : ;;
esac
exit 0
EOF
chmod +x /tmp/maidbt-q/stubs/*
# silence cross-boundary side effects: no real phone pings, no real popups.
printf '#!/bin/bash\nexit 1\n' > /tmp/maidbt-q/stubs/kdeconnect-cli
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-q/stubs/notify-send
chmod +x /tmp/maidbt-q/stubs/*
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="test-sink"\nQUALITY_LOCK=1\n' > /tmp/maidbt-q/.config/bluetooth-buds.conf
STUBSTATE=/tmp/maidbt-q/state PATH="/tmp/maidbt-q/stubs:$PATH" XDG_RUNTIME_DIR=/tmp/maidbt-q \
  HOME=/tmp/maidbt-q timeout 6 bash "$PKGDIR/bin/buds-fallback.sh" > /tmp/maidbt-q/daemon.log 2>&1 || true
grep -q "quality lock -> LDAC (was a2dp-sink-sbc)" /tmp/maidbt-q/daemon.log || fail "quality lock did not fire"
grep -q "profile bluez_card.11_22_33_44_55_66 -> a2dp-sink" /tmp/maidbt-q/state/calls || fail "LDAC profile not set"
ok "quality lock pins LDAC"
rm -rf /tmp/maidbt-q

echo "== hsp rescue needs free mic =="
rm -rf /tmp/maidbt-h; mkdir -p /tmp/maidbt-h/stubs /tmp/maidbt-h/.config /tmp/maidbt-h/state
cat > /tmp/maidbt-h/stubs/bluetoothctl <<'EOF'
#!/bin/bash
case "$*" in
  *show*) printf 'Controller STUB\n\tPowered: yes\n' ;;
  *11:22:33:44:55:66*) printf 'Device 11:22:33:44:55:66 Test Buds\n\tConnected: yes\n' ;;
  *) exit 1 ;;
esac
exit 0
EOF
cat > /tmp/maidbt-h/stubs/pactl <<'EOF'
#!/bin/bash
S="${STUBSTATE:-/tmp}"
case "$*" in
  *short*cards*) echo "99 bluez_card.11_22_33_44_55_66" ;;
  *list*cards*) printf 'Card #99\n\tName: bluez_card.11_22_33_44_55_66\n\tActive Profile: headset-head-unit\n' ;;
  *set-card-profile*) echo "profile $2 -> $3" >> "$S/calls" ;;
  *short*sinks*) echo "77 bluez_output.11_22_33_44_55_66.1" ;;
  *short*sink-inputs*) : ;;
  *short*sources*) echo "3 bluez_input.11_22_33_44_55_66.0" ;;
  *source-outputs*)
    if [ "${MIC_BUSY:-0}" = "1" ]; then
      printf 'Source Output #7\n\tSource: 3\n\tProperties:\n\tapplication.name = "TestCall"\n'
    fi
    ;;
  *info*) echo "Default Sink: bluez_output.11_22_33_44_55_66.1" ;;
  *set-default-sink*|*suspend-sink*|*move-sink-input*) : ;;
esac
exit 0
EOF
chmod +x /tmp/maidbt-h/stubs/*
# silence cross-boundary side effects: no real phone pings, no real popups.
printf '#!/bin/bash\nexit 1\n' > /tmp/maidbt-h/stubs/kdeconnect-cli
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-h/stubs/notify-send
chmod +x /tmp/maidbt-h/stubs/*
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="test-sink"\nQUALITY_LOCK=1\n' > /tmp/maidbt-h/.config/bluetooth-buds.conf
# free mic: stuck HSP gets rescued to LDAC
MIC_BUSY=0 STUBSTATE=/tmp/maidbt-h/state PATH="/tmp/maidbt-h/stubs:$PATH" XDG_RUNTIME_DIR=/tmp/maidbt-h \
  HOME=/tmp/maidbt-h timeout 6 bash "$PKGDIR/bin/buds-fallback.sh" > /tmp/maidbt-h/daemon.log 2>&1 || true
grep -q "rescued HSP -> LDAC (mic free)" /tmp/maidbt-h/daemon.log || fail "hsp rescue did not fire"
grep -q "profile bluez_card.11_22_33_44_55_66 -> a2dp-sink" /tmp/maidbt-h/state/calls || fail "rescue did not set LDAC"
# busy mic: a real call means hands off, no rescue, no profile write
rm -f /tmp/maidbt-h/state/calls /tmp/maidbt-h/daemon.log
MIC_BUSY=1 STUBSTATE=/tmp/maidbt-h/state PATH="/tmp/maidbt-h/stubs:$PATH" XDG_RUNTIME_DIR=/tmp/maidbt-h \
  HOME=/tmp/maidbt-h timeout 6 bash "$PKGDIR/bin/buds-fallback.sh" > /tmp/maidbt-h/daemon.log 2>&1 || true
grep -q "rescued HSP" /tmp/maidbt-h/daemon.log && fail "rescued during a call!"
[ -s /tmp/maidbt-h/state/calls ] && fail "profile written during a call!"
ok "hsp rescue needs free mic"
rm -rf /tmp/maidbt-h

echo "== multipoint release parks all day =="
rm -rf /tmp/maidbt-m; mkdir -p /tmp/maidbt-m/stubs /tmp/maidbt-m/.config
cat > /tmp/maidbt-m/stubs/bluetoothctl <<'EOF'
#!/bin/bash
case "$*" in
  *show*) printf 'Controller STUB\n\tPowered: yes\n' ;;
  *11:22:33:44:55:66*) printf 'Device 11:22:33:44:55:66 Test Buds\n\tConnected: yes\n' ;;
  *) exit 1 ;;
esac
exit 0
EOF
cat > /tmp/maidbt-m/stubs/pactl <<'EOF'
#!/bin/bash
case "$*" in
  *info*) echo "Default Sink: testsink" ;;
  *short*sinks*) echo "77 bluez_output.11_22_33_44_55_66.1" ;;
esac
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-m/stubs/systemctl
printf '#!/bin/bash\nexit 0\n' > /tmp/maidbt-m/stubs/notify-send
printf '#!/bin/bash\nexit 1\n' > /tmp/maidbt-m/stubs/kdeconnect-cli
chmod +x /tmp/maidbt-m/stubs/*
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="test-sink"\nMULTIPOINT=1\n' > /tmp/maidbt-m/.config/bluetooth-buds.conf
PATH="/tmp/maidbt-m/stubs:$PATH" XDG_RUNTIME_DIR=/tmp/maidbt-m HOME=/tmp/maidbt-m \
  bash "$PKGDIR/bin/bluetooth-toggle.sh" release >/dev/null 2>&1
[ "$(awk '{print $2}' /tmp/maidbt-m/bt-hands-off 2>/dev/null)" = "28800" ] || fail "multipoint release did not park 8h"
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="test-sink"\n' > /tmp/maidbt-m/.config/bluetooth-buds.conf
rm -f /tmp/maidbt-m/bt-hands-off
PATH="/tmp/maidbt-m/stubs:$PATH" XDG_RUNTIME_DIR=/tmp/maidbt-m HOME=/tmp/maidbt-m \
  bash "$PKGDIR/bin/bluetooth-toggle.sh" release >/dev/null 2>&1
[ "$(awk '{print NF}' /tmp/maidbt-m/bt-hands-off 2>/dev/null)" = "1" ] || fail "single-link release lost its short window"
ok "multipoint release parks all day"
rm -rf /tmp/maidbt-m

echo "== intent server auth =="
rm -rf /tmp/maidbt-i; mkdir -p /tmp/maidbt-i/.config
python3 -c "import secrets; print(secrets.token_urlsafe(24))" > /tmp/maidbt-i/.config/bt-intent.token
chmod 600 /tmp/maidbt-i/.config/bt-intent.token
HOME=/tmp/maidbt-i MAID_INTENT_PORT=8891 python3 "$PKGDIR/bin/bt-intent-server.py" > /tmp/maidbt-i/srv.log 2>&1 &
SRV=$!
sleep 2
TOK=$(cat /tmp/maidbt-i/.config/bt-intent.token)
[ "$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8891/health?token=wrong")" = "403" ] || fail "bad token not rejected"
[ "$(curl -s "http://127.0.0.1:8891/health?token=$TOK")" = "ok" ] || fail "good query token rejected"
[ "$(curl -s -H "X-Token: $TOK" "http://127.0.0.1:8891/health")" = "ok" ] || fail "good header token rejected"
[ "$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8891/nope?token=$TOK")" = "404" ] || fail "unknown path not 404"
kill "$SRV" 2>/dev/null || true
wait "$SRV" 2>/dev/null || true
grep -q "$TOK" /tmp/maidbt-i/srv.log && fail "token leaked into logs"
ok "intent server auth"
rm -rf /tmp/maidbt-i

echo "== cleanup =="
rm -rf /tmp/maidbt-t
ok "cleanup"
echo "ALL $PASS PASSED"
