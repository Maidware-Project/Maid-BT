#!/usr/bin/env python3
# bt-intent-server: tiny LAN HTTP listener so the phone (MacroDroid) can push
# playback/call intent to this PC. Token-gated, stdlib only.
#   GET /phone_playing?token=... -> park PC audio, hands-off 4h (phone wins)
#   GET /phone_paused?token=...  -> clear hands-off (PC may grab back)
#   GET /call_start?token=...    -> park PC audio, hands-off 2h (calls win)
#   GET /call_end?token=...      -> clear hands-off
#   GET /health?token=...        -> ok (connectivity test from MacroDroid)
#   GET /phone_device?token=...&mac=...&state=connected|disconnected
#                                -> BlueV phone hint for Maid Watcher
import hmac
import json
import os
import shutil
import subprocess
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MAID_INTENT_PORT", "8899"))
HOME = os.path.expanduser("~")
TOGGLE = (shutil.which("bluetooth-toggle.sh")
          or os.path.expanduser("~/.local/bin/bluetooth-toggle.sh")
          or "/usr/bin/bluetooth-toggle.sh")
HANDS = os.path.join("/run/user", str(os.getuid()), "bt-hands-off")
BLUEV_PHONE_HINTS = os.path.join("/run/user", str(os.getuid()), "maid-bluev-phone.json")


def load_token():
    try:
        with open(os.path.join(HOME, ".config/bt-intent.token")) as f:
            return f.read().strip()
    except OSError:
        return ""


TOKEN = load_token()


def run_toggle(action):
    try:
        p = subprocess.run([TOGGLE, action], capture_output=True, text=True, timeout=90)
        tail = (p.stdout + p.stderr).strip().splitlines()[-3:]
        return p.returncode, "\n".join(tail)
    except Exception as e:  # noqa: BLE001 - report anything, never crash the server
        return 1, str(e)


def set_handsoff(seconds):
    try:
        with open(HANDS, "w") as f:
            f.write(f"{int(time.time())} {int(seconds)}")
    except OSError:
        pass


def clear_handsoff():
    try:
        os.remove(HANDS)
    except OSError:
        pass


def _norm_mac(mac):
    mac = (mac or "").strip().upper().replace("-", ":")
    parts = mac.split(":")
    if len(parts) == 6 and all(len(p) == 2 for p in parts):
        return ":".join(parts)
    return None


def update_bluev_phone_hint(mac, state):
    """Persist phone-reported device connection hint for Maid Watcher BlueV."""
    mac = _norm_mac(mac)
    if mac is None:
        return False, "bad mac"
    state = (state or "").strip().lower()
    if state in ("connected", "connected_to_phone", "up", "on"):
        state = "connected"
    elif state in ("disconnected", "disconnected_from_phone", "down", "off"):
        state = "disconnected"
    else:
        return False, "bad state"
    try:
        if os.path.exists(BLUEV_PHONE_HINTS):
            with open(BLUEV_PHONE_HINTS) as f:
                data = json.load(f)
            if not isinstance(data, dict):
                data = {}
        else:
            data = {}
    except (OSError, ValueError, TypeError):
        data = {}
    devices = data.get("devices")
    if not isinstance(devices, dict):
        devices = {}
    devices[mac] = {"state": state, "ts": time.time(), "source": "phone"}
    data["devices"] = devices
    try:
        tmp = BLUEV_PHONE_HINTS + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, BLUEV_PHONE_HINTS)
        return True, "ok"
    except OSError as e:
        return False, str(e)


class Handler(BaseHTTPRequestHandler):
    server_version = "bt-intent/1.0"
    timeout = 60  # per-connection socket cap: trickled requests can't
    # hold a thread forever (plus token gate + tiny handlers + expiry
    # via the phone flow itself; LAN-only by design, see README).

    def log_message(self, fmt, *args):  # journal-friendly single lines
        # NEVER log the query string: legacy ?token= auth would otherwise
        # land in the journal where log readers could reuse it.
        safe = [a.split("?", 1)[0] if isinstance(a, str) else a for a in args]
        print(f"[bt-intent] {self.client_address[0]} {fmt % tuple(safe)}", flush=True)

    def _token_ok(self):
        # preferred: X-Token header (never appears in logs).
        # legacy: ?token= query (still accepted, never logged).
        hdr = self.headers.get("X-Token", "")
        if hdr and TOKEN and hmac.compare_digest(hdr, TOKEN):
            return True
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        tok = qs.get("token", [""])[0]
        return bool(TOKEN) and hmac.compare_digest(tok, TOKEN)

    def do_GET(self):  # noqa: N802 - http.server naming
        parts = urllib.parse.urlparse(self.path)
        if not self._token_ok():
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"forbidden")
            return

        path = parts.path.rstrip("/") or "/"
        if path == "/phone_playing":
            code, out = run_toggle("release")
            set_handsoff(14400)  # 4h: phone owns the buds until it pauses
            body = f"release rc={code}\n{out}"
        elif path == "/phone_paused":
            clear_handsoff()
            body = "hands-off cleared"
        elif path == "/call_start":
            code, out = run_toggle("release")
            set_handsoff(7200)  # 2h: calls own the buds until call ends
            body = f"release rc={code}\n{out}"
        elif path == "/call_end":
            clear_handsoff()
            body = "hands-off cleared"
        elif path == "/health":
            body = "ok"
        elif path == "/phone_device":
            qs = urllib.parse.parse_qs(parts.query)
            mac = (qs.get("mac") or [""])[0]
            state = (qs.get("state") or [""])[0]
            ok, msg = update_bluev_phone_hint(mac, state)
            if not ok:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(msg.encode())
                return
            body = f"bluev {mac} {state}"
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"unknown endpoint")
            return

        raw = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[bt-intent] listening on 0.0.0.0:{PORT}", flush=True)
    srv.serve_forever()
