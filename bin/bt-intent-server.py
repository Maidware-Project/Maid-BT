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
# Safer default: local-only. Set MAID_INTENT_BIND=0.0.0.0 explicitly for LAN access.
BIND_ADDR = os.environ.get("MAID_INTENT_BIND", "127.0.0.1")
ALLOW_QUERY_TOKEN = os.environ.get("MAID_INTENT_ALLOW_QUERY_TOKEN", "0") == "1"
HOME = os.path.expanduser("~")
RATE_LIMIT_WINDOW_S = int(os.environ.get("MAID_INTENT_RATE_WINDOW_S", "10"))
RATE_LIMIT_MAX = int(os.environ.get("MAID_INTENT_RATE_MAX", "30"))
_RATE = {}  # ip -> [window_start, count]
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


def update_bluev_phone_hint(mac, state, extra=None):
    """Persist phone-reported device connection hint for Maid Watcher BlueV.

    Accepts richer payload fields (backward-compatible): reported ts, source,
    confidence, transport/profile, adapter, active/call hints, device name, etc.
    """
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
    rec = {"state": state, "ts": time.time(), "source": "phone"}
    if isinstance(extra, dict):
        # preserve a few safe/optional fields for observability and future policy
        for k in ("reported_ts", "confidence", "transport", "profile", "adapter",
                  "device_name", "active", "call", "source", "note", "seq"):
            if k in extra:
                v = extra.get(k)
                if isinstance(v, (str, int, float, bool)) or v is None:
                    rec[k] = v
        # normalize reported_ts if provided
        try:
            if "reported_ts" in rec:
                rec["reported_ts"] = float(rec["reported_ts"])
        except Exception:
            rec.pop("reported_ts", None)
        try:
            if "confidence" in rec:
                c = float(rec["confidence"])
                if c < 0: c = 0.0
                if c > 1: c = 1.0
                rec["confidence"] = c
        except Exception:
            rec.pop("confidence", None)
        if "source" in rec and isinstance(rec["source"], str):
            rec["source"] = rec["source"][:64]
        else:
            rec["source"] = "phone"
    devices[mac] = rec
    data["devices"] = devices
    try:
        tmp = BLUEV_PHONE_HINTS + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(tmp, BLUEV_PHONE_HINTS)
        try:
            os.chmod(BLUEV_PHONE_HINTS, 0o600)
        except OSError:
            pass
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

    def _rate_limited(self):
        ip = self.client_address[0]
        now = time.time()
        win_start, count = _RATE.get(ip, (now, 0))
        if now - win_start >= RATE_LIMIT_WINDOW_S:
            win_start, count = now, 0
        count += 1
        _RATE[ip] = (win_start, count)
        # opportunistic cleanup
        if len(_RATE) > 512:
            stale = [k for k, v in _RATE.items() if now - v[0] >= RATE_LIMIT_WINDOW_S * 2]
            for k in stale:
                _RATE.pop(k, None)
        return count > RATE_LIMIT_MAX

    def _token_ok(self):
        # preferred: X-Token header (never appears in logs).
        # legacy query token is disabled by default; enable only if explicitly opted in.
        hdr = self.headers.get("X-Token", "")
        if hdr and TOKEN and hmac.compare_digest(hdr, TOKEN):
            return True
        if not ALLOW_QUERY_TOKEN:
            return False
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        tok = qs.get("token", [""])[0]
        return bool(TOKEN) and hmac.compare_digest(tok, TOKEN)

    def _read_json_body(self):
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except Exception:
            length = 0
        if length <= 0 or length > 65536:
            return None
        try:
            raw = self.rfile.read(length)
            data = json.loads(raw.decode("utf-8", errors="replace"))
            return data if isinstance(data, dict) else None
        except Exception:
            return None

    def _handle_intent(self, path, qs, payload=None):
        if path == "/phone_playing":
            code, out = run_toggle("release")
            set_handsoff(14400)  # 4h: phone owns the buds until it pauses
            return 200, f"release rc={code}\n{out}"
        if path == "/phone_paused":
            clear_handsoff()
            return 200, "hands-off cleared"
        if path == "/call_start":
            code, out = run_toggle("release")
            set_handsoff(7200)  # 2h: calls own the buds until call ends
            return 200, f"release rc={code}\n{out}"
        if path == "/call_end":
            clear_handsoff()
            return 200, "hands-off cleared"
        if path == "/health":
            return 200, "ok"
        if path == "/phone_device":
            payload = payload or {}
            mac = (qs.get("mac") or [payload.get("mac", "")])[0]
            state = (qs.get("state") or [payload.get("state", "")])[0]
            extra = dict(payload)
            extra.pop("mac", None)
            extra.pop("state", None)
            ok, msg = update_bluev_phone_hint(mac, state, extra=extra)
            if not ok:
                return 400, msg
            norm = _norm_mac(mac) or mac
            return 200, f"bluev {norm} {state}"
        return 404, "unknown endpoint"

    def do_GET(self):  # noqa: N802 - http.server naming
        parts = urllib.parse.urlparse(self.path)
        if self._rate_limited():
            self.send_response(429)
            self.end_headers()
            self.wfile.write(b"rate limited")
            return
        if not self._token_ok():
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"forbidden")
            return

        path = parts.path.rstrip("/") or "/"
        qs = urllib.parse.parse_qs(parts.query)
        status, body = self._handle_intent(path, qs, None)

        raw = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):  # noqa: N802 - http.server naming
        parts = urllib.parse.urlparse(self.path)
        if self._rate_limited():
            self.send_response(429)
            self.end_headers()
            self.wfile.write(b"rate limited")
            return
        if not self._token_ok():
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"forbidden")
            return
        path = parts.path.rstrip("/") or "/"
        qs = urllib.parse.parse_qs(parts.query)
        payload = self._read_json_body()
        # Backward-compatible: POST accepted for intents, primarily /phone_device
        if path != "/phone_device" and payload is None:
            payload = None
        status, body = self._handle_intent(path, qs, payload)
        raw = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


if __name__ == "__main__":
    srv = ThreadingHTTPServer((BIND_ADDR, PORT), Handler)
    print(f"[bt-intent] listening on {BIND_ADDR}:{PORT}", flush=True)
    srv.serve_forever()
