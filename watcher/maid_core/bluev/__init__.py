"""Maid BT: Maid Watcher BlueV Protocol - device state/confidence model.

Combines local BT probing, PC connection/flap signals, and optional
phone-side hints (MAC connection state) into a per-device state used to
drive reconnect/dock policy.

States:
  connected_to_pc      - connected to this PC
  connected_to_phone   - phone hint says connected to phone (fresh)
  out_available        - out of case / available (advertising/pageable)
  docked               - high confidence in charging case (silent probes)
  unknown              - insufficient/expired evidence
"""
from __future__ import annotations

import json
import os
import time

RUNTIME_DIR = os.path.join("/run/user", str(os.getuid()))
PHONE_HINTS_PATH = os.path.join(RUNTIME_DIR, "maid-bluev-phone.json")
DEFAULT_HINT_TTL_S = 300


def _now():
    return time.time()


def load_phone_hints(path=PHONE_HINTS_PATH):
    try:
        with open(path) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return {}
        devs = data.get("devices", {})
        if not isinstance(devs, dict):
            return {}
        return devs
    except (OSError, ValueError, TypeError):
        return {}


def phone_hint_state(hints, mac, ttl_s=DEFAULT_HINT_TTL_S, now=None):
    now = _now() if now is None else now
    rec = hints.get(mac) or hints.get(mac.upper()) or hints.get(mac.lower())
    if not isinstance(rec, dict):
        return None
    try:
        ts = float(rec.get("ts", 0))
    except (TypeError, ValueError):
        return None
    if ts <= 0 or (now - ts) > ttl_s:
        return None
    st = str(rec.get("state", ""))
    if st == "connected":
        return "connected_to_phone"
    if st == "disconnected":
        return "disconnected_from_phone"
    return None


class DeviceState:
    __slots__ = ("mac", "state", "updated_at", "docked_silent_count",
                 "docked_silent_since", "last_out_evidence", "reason")

    def __init__(self, mac):
        self.mac = mac
        self.state = "unknown"
        self.updated_at = 0.0
        self.docked_silent_count = 0
        self.docked_silent_since = None
        self.last_out_evidence = 0.0
        self.reason = "init"

    def set_state(self, state, reason="", now=None):
        now = _now() if now is None else now
        if self.state != state or reason:
            self.state = state
            self.reason = reason or self.reason
        self.updated_at = now


class BlueV:
    def __init__(self, cfg=None):
        self.cfg = cfg or {}
        self.devices = {}  # mac -> DeviceState
        self._hints_mtime = None
        self._hints = {}
        self._hints_ttl_s = int((self.cfg.get("bluev") or {}).get("phone_hint_ttl_s", DEFAULT_HINT_TTL_S))
        self._docked_confirmations = int((self.cfg.get("bluev") or {}).get("docked_confirmations", 2))
        self._docked_confirm_window_s = int((self.cfg.get("bluev") or {}).get("docked_confirm_window_s", 600))

    def ensure(self, mac):
        st = self.devices.get(mac)
        if st is None:
            st = self.devices[mac] = DeviceState(mac)
        return st

    def refresh_hints(self):
        try:
            mtime = os.path.getmtime(PHONE_HINTS_PATH)
        except OSError:
            mtime = None
        if mtime == self._hints_mtime:
            return
        self._hints_mtime = mtime
        self._hints = load_phone_hints(PHONE_HINTS_PATH)

    def phone_state(self, mac, now=None):
        self.refresh_hints()
        return phone_hint_state(self._hints, mac, ttl_s=self._hints_ttl_s, now=now)

    def note_connected_pc(self, mac, now=None):
        now = _now() if now is None else now
        st = self.ensure(mac)
        st.set_state("connected_to_pc", "pc_connected", now)
        st.docked_silent_count = 0
        st.docked_silent_since = None
        st.last_out_evidence = now

    def note_out_evidence(self, mac, reason="out", now=None):
        now = _now() if now is None else now
        st = self.ensure(mac)
        st.last_out_evidence = now
        st.docked_silent_count = 0
        st.docked_silent_since = None
        if st.state in ("docked", "unknown"):
            st.set_state("out_available", reason, now)

    def note_pc_disconnected(self, mac, now=None):
        now = _now() if now is None else now
        st = self.ensure(mac)
        if st.state == "connected_to_pc":
            st.set_state("unknown", "pc_disconnected", now)

    def resolve(self, mac, pc_connected, probe_verdict=None, now=None):
        """Return (state, reason) for mac given current signals.

        probe_verdict: True (out/advertising), False (silent), None (unknown/unavailable)
        """
        now = _now() if now is None else now
        st = self.ensure(mac)
        phone = self.phone_state(mac, now=now)

        if pc_connected:
            st.set_state("connected_to_pc", "pc_connected", now)
            st.docked_silent_count = 0
            st.docked_silent_since = None
            st.last_out_evidence = now
            return st.state, st.reason

        # Not connected to PC: phone hint takes precedence for ownership.
        if phone == "connected_to_phone":
            st.set_state("connected_to_phone", "phone_hint", now)
            st.docked_silent_count = 0
            st.docked_silent_since = None
            return st.state, st.reason

        # Probe evidence
        if probe_verdict is True:
            st.note_out_evidence(mac, "probe_advertising", now)
            return st.state, st.reason

        if probe_verdict is False:
            # Silent probe: candidate for docked, but smooth/confirm over time.
            if st.docked_silent_since is None or (now - st.docked_silent_since) > self._docked_confirm_window_s:
                st.docked_silent_since = now
                st.docked_silent_count = 0
            st.docked_silent_count += 1
            if st.docked_silent_count >= self._docked_confirmations:
                st.set_state("docked", "silent_probes", now)
            elif st.state == "connected_to_phone":
                # phone says disconnected (or expired handled above) but still silent once: unknown, wait for confirm
                st.set_state("unknown", "silent_unconfirmed", now)
            elif st.state not in ("docked", "out_available"):
                st.set_state("unknown", "silent_unconfirmed", now)
            return st.state, st.reason

        # probe_verdict is None (unavailable) or no probe: keep best-known non-docked state, but don't assert docked
        if st.state == "connected_to_pc":
            st.set_state("unknown", "pc_disconnected", now)
        elif st.state == "docked":
            # keep docked until contradicted by evidence, but don't strengthen
            pass
        elif phone == "disconnected_from_phone" and st.state == "unknown":
            st.reason = "phone_disconnected"
        return st.state, st.reason

    def should_suppress_reconnect(self, mac, now=None):
        state, _ = self.resolve(mac, pc_connected=False, probe_verdict=None, now=now)
        return state in ("connected_to_phone",)

    def should_treat_docked(self, mac, now=None):
        state, _ = self.resolve(mac, pc_connected=False, probe_verdict=None, now=now)
        return state == "docked"
