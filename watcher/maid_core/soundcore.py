"""Soundcore vendor-protocol control over RFCOMM (Bluetooth Classic).

Clean-room implementation for the Maidware project, MIT-licensed, with
full credit to the GPL OpenSCQ30 project
(https://github.com/Oppzippy/OpenSCQ30) for reverse-engineering and
documenting the Soundcore vendor protocol. No OpenSCQ30 code was copied
or translated into this file; only wire facts (marker bytes, command
ids, field layouts) were used as the protocol reference.

Wire format (verified against the OpenSCQ30 protocol documentation):
  frame  = marker(5) + command(2 LE) + length(2 LE) + body + checksum(1)
  marker (out) = 08 EE 00 00 00, (in) = 09 FF 00 00 01
  length = 5 + 2 + 2 + len(body) + 1
  checksum = wrapping byte sum of everything before it

Commands used here:
  [1, 1]     request state update (response carries the full state)
  [6, 0x81]  set sound modes (7-byte body)

Applies to Soundcore models whose model DB entry carries the
"device-control" quirk. Each model binds through its own RFCOMM SPP
service UUID, discovered from the device at connect time
(0cf12d31-fac3-4553-bd80-d6832e7bXXXX family). State packets the parser
cannot recognise fail loud with the raw bytes count rather than
garbage-in-garbage-out.
"""
import fcntl
import os
import socket
import struct
import time

import dbus
import dbus.service

try:
    from dbus.mainloop.glib import DBusGMainLoop

    # Profile export/NewConnection needs an main-loop-attached connection;
    # this must be set BEFORE the first SystemBus() is created.
    DBusGMainLoop(set_as_default=True)
except Exception:  # noqa: BLE001 - no gi/dbus plugs available: fail loud later
    pass

from gi.repository import GLib

MARKER_OUT = bytes((0x08, 0xEE, 0x00, 0x00, 0x00))
MARKER_IN = bytes((0x09, 0xFF, 0x00, 0x00, 0x01))
CMD_GET_STATE = (0x01, 0x01)
CMD_SET_SOUND_MODES = (0x06, 0x81)
CMD_SET_EQ = (0x03, 0x87)

PROFILE_IFACE = "org.bluez.Profile1"
PROFILE_MANAGER = "org.bluez.ProfileManager1"
# soundcore SPP service uuids all carry this prefix; the tail picks the
# device generation (0cf12d31-fac3-4553-bd80-d6832e7b3957 for A3957)
UUID_PREFIX = "0cf12d31-fac3-4553-bd80-d6832e7b"

# ambient sound mode byte (state offset 119)
AMBIENT = {"noise": 0x00, "transparency": 0x01, "normal": 0x02}
# noise canceling mode byte (state offset 122)
NC_MODE = {"manual": 0x00, "adaptive": 0x01, "transport": 0x02}
TRANSPORT = {"plane": 0x00, "car": 0x03}


def checksum(data):
    """Wrapping byte sum (verified: OpenSCQ30 checksum test vectors)."""
    return sum(data) & 0xFF


def build_frame(command, body=b""):
    """Outbound packet -> bytes (Soundcore vendor framing)."""
    length = len(MARKER_OUT) + 2 + 2 + len(body) + 1
    head = MARKER_OUT + bytes(command) + struct.pack("<H", length) + body
    return head + bytes((checksum(head),))


class FrameReader:
    """Incrementally splits an RFCOMM byte stream into frames."""

    def __init__(self):
        self._buf = b""

    def feed(self, data):
        """Returns list of (command, body) tuples parsed from data."""
        self._buf += data
        frames = []
        while True:
            frames += self._drain()
            if len(self._buf) < 10:
                break
        return frames

    def _drain(self):
        # find the next inbound marker anywhere in the buffer
        start = self._buf.find(MARKER_IN)
        if start < 0:
            # keep the tail in case a marker straddles reads
            self._buf = self._buf[-4:]
            return []
        self._buf = self._buf[start:]
        if len(self._buf) < 10:
            return []
        (length,) = struct.unpack_from("<H", self._buf, 7)
        if length < 10 or length > 4096:
            # resync: corrupt frame length (device noise or garbage)
            self._buf = self._buf[1:]
            return []
        if len(self._buf) < length:
            return []
        frame, self._buf = self._buf[:length], self._buf[length:]
        end = frame[-1]
        if checksum(frame[:-1]) != end:
            return []  # bad checksum: silently drop, keep the stream
        command = tuple(frame[5:7])
        return [(command, frame[9:-1])]


def _s8(v):
    return v - 256 if v >= 128 else v


def _band_state(v):
    """State EQ band byte (offset-encoded) -> dB*10, None = 0xFF."""
    if v == 0xFF:
        return None  # band not present right now
    return v - 120


def _battery(level):
    # Soundcore scales levels 0-9; their app shows "9/10" for 0x08,
    # so percent = (level + 1) * 10 (level 8 -> 90%)
    return min(100, (level + 1) * 10)


def parse_state(body):
    """Parse a [1, 1] state packet body into a plain dict.

    Layout verified against the OpenSCQ30 A3957 device-faker state
    packet. Offsets are fixed from that layout; a future firmware that
    shifts fields will fail loud (length checks + sane serial/ANC
    semantics) instead of silently reporting wrong values.
    """
    if len(body) < 147:
        raise ValueError("state packet too short (%d bytes)" % len(body))

    def u(i):
        return body[i]

    anc = {
        "ambient": {0: "noise", 1: "transparency", 2: "normal"}.get(
            u(119), "unknown(%d)" % u(119)),
        "ambient_cycle": u(118),
        "nc_manual_strength": (u(120) >> 4) & 0x0F,
        "nc_adaptive_strength": u(120) & 0x0F,
        "transparency": {0: "full", 1: "vocal"}.get(u(121),
                                                    "unknown(%d)" % u(121)),
        "nc_mode": {0: "manual", 1: "adaptive",
                    2: "transport"}.get(u(122), "unknown(%d)" % u(122)),
        "wind_noise": bool(u(123) & 0x01),
        "adaptive_sensitivity": u(124),
        "transportation": {0: "plane", 3: "car"}.get(u(125),
                                                     "unknown(%d)" % u(125)),
    }
    return {
        "battery_left": _battery(u(2)),
        "battery_right": _battery(u(3)),
        "battery_case": _battery(u(37)),
        "charging_left": bool(u(4)),
        "charging_right": bool(u(5)),
        "anc": anc,
        "ldac": bool(u(129)),
        "dual_connection": bool(u(130)),
        "eq_preset_left": u(38),
        "eq_preset_right": u(39),
        # EQ bands: offset-encoded bytes (0x78 = 0 dB flat, 0xFF = absent)
        "eq_left": [_band_state(u(40 + i)) for i in range(10)],
        "eq_right": [_band_state(u(50 + i)) for i in range(10)],
        "firmware": "".join(chr(u(6 + i)) for i in range(5)
                            if 32 <= u(6 + i) < 127),
        "serial": "".join(chr(u(16 + i)) for i in range(16)
                          if 32 <= u(16 + i) < 127),
        "raw_len": len(body),
    }


def _band_byte(value):
    """EQ band value (dB*10) -> packet byte (offset encoding).

    Verified against upstream volume_adjustments: byte = value - MIN,
    MIN=-120 (so 0x78 = 0 dB flat), 0xFF reserved as not-present.
    """
    b = int(value) + 120
    if not 0 <= b <= 0xFE:
        raise ValueError("EQ band out of range -12.0..+13.4 dB")
    return b


def eq_body(state, vols):
    """Equalizer write body per upstream a3957 set_equalizer_configuration.

    vols: 10 band values in dB*10, applied to both ears. Preset/id bytes
    are preserved from the device (state offsets 38/39); HearID is kept
    DISABLED so the raw slider curve takes effect (same rule upstream
    EqualizerStateModifier applies). Returns the packet body.
    """
    if len(vols) != 10:
        raise ValueError("need exactly 10 band values (-120..134 each, "
                         "0.1 dB units)")
    body = bytearray()
    body += bytes((state["eq_preset_left"], state["eq_preset_right"]))
    body.append(0)                               # favorite music genre
    body += bytes(_band_byte(v) for v in vols)   # left
    body += bytes(_band_byte(v) for v in vols)   # right
    body += b"\x00\x00"                          # unknown pair
    body.append(0)                               # hearid off
    body += bytes(20)                            # hearid volumes L+R
    body += b"\x00\x00\x00\x00"                  # hearid time (BE u32)
    body.append(0)                               # hearid type: initial curve
    body += bytes(20)                            # custom hearid volumes
    # active (interleaved) section: band,0,band,0 ...
    for v in vols:
        body += bytes((_band_byte(v), 0x00))
    body += b"\x00\x00"
    return bytes(body)


def sound_modes_body(state, ambient="normal", nc_mode=None,
                     manual_strength=None, transparency=None,
                     transportation=None, adaptive_sensitivity=None):
    """Build the 7-byte [6, 0x81] body.

    The buds dislike transitions the Soundcore app never performs
    (upstream implements a whole state-migration engine around this),
    so every sub-field is kept at its CURRENT value and only the
    requested axis changes:
      ambient: normal / transparency / vocal / noise
      nc_mode: manual / adaptive / transport (noise mode only)
      manual_strength 0-5: noise-cancel level (goes into the high nibble
      of the combined byte; adaptive nibble is preserved)
      transparency: "full"/"vocal" override (default follows ambient)
    """
    cur = state["anc"]
    raw = (cur["nc_manual_strength"] << 4) | cur["nc_adaptive_strength"]
    amb_byte = {"normal": 0x02, "transparency": 0x01, "vocal": 0x01,
                "noise": 0x00}.get(ambient)
    if amb_byte is None:
        raise ValueError("ambient must be normal/transparency/vocal/noise, "
                         "got %r" % (ambient,))
    # transparency byte: vocal=1, everything else canonical 0 (unused
    # while noise canceling anyway)
    transparent_byte = (0x00 if transparency in (None, "full")
                        else 0x01 if transparency == "vocal"
                        else 0x00) if ambient == "vocal" else 0x00
    # NC sub-mode: keep the buds' current one where it is meaningful
    if nc_mode is None:
        nc_byte = {"manual": 0x00, "adaptive": 0x01,
                   "transport": 0x02}.get(cur["nc_mode"], 0)
    else:
        nc_byte = NC_MODE.get(nc_mode)
        if nc_byte is None:
            raise ValueError("nc mode must be manual/adaptive/transport, "
                             "got %r" % (nc_mode,))
    if amb_byte == 0x02:
        nc_byte = 0x00  # normal mode: no canceling engaged
        nc_settings = raw
    else:
        nc_settings = raw
    if manual_strength is not None:
        m = int(manual_strength)
        if not 0 <= m <= 5:
            raise ValueError("manual strength must be 0-5")
        nc_settings = (m << 4) | (nc_settings & 0x0F)
    if transportation is None:
        transport_byte = {"plane": 0x00, "car": 0x03}.get(
            cur["transportation"], 0)
    else:
        transport_byte = TRANSPORT.get(transportation)
        if transport_byte is None:
            raise ValueError("transportation must be plane/car, got %r"
                             % (transportation,))
    adaptive = cur["adaptive_sensitivity"] \
        if adaptive_sensitivity is None else int(adaptive_sensitivity)
    if not 0 <= adaptive <= 0xFF:
        raise ValueError("adaptive sensitivity out of range")
    return bytes((amb_byte, nc_settings, transparent_byte, nc_byte,
                  0x00, adaptive, transport_byte))


def _dev_path(mac):
    return "/org/bluez/hci0/dev_" + \
        str(mac).upper().replace(":", "_")


def find_profile_uuid(mac):
    """Return the device's soundcore SPP uuid, or raise."""
    bus = dbus.SystemBus()
    dev = dbus.Interface(bus.get_object("org.bluez", _dev_path(mac)),
                         dbus.PROPERTIES_IFACE)
    uuids = [str(u).lower() for u in dev.Get("org.bluez.Device1", "UUIDs")]
    hits = [u for u in uuids if u.startswith(UUID_PREFIX)]
    if not hits:
        raise ValueError(
            "no soundcore control service on %s (uuids: %d known) - "
            "model DB device-control quirk mismatch?" % (mac, len(uuids)))
    return hits[0]


class _Profile(dbus.service.Object):
    """BlueZ profile shim: accepts the fd the buds dial back on."""

    def __init__(self, bus, path, sink, want_path):
        super().__init__(bus, path)
        self._sink = sink
        self._want_path = want_path

    @dbus.service.method(PROFILE_IFACE)
    def Release(self):
        pass  # we unregister explicitly; nothing to release

    @dbus.service.method(PROFILE_IFACE, in_signature="oha{sv}",
                         out_signature="")
    def NewConnection(self, device, fd, properties):
        # BlueZ dials back over the profile's own UUID (per-model SPP), so
        # anything arriving here is our buds; keep the handler void per
        # the Profile1 D-Bus docs.
        self._sink["fd"] = fd.take()

    @dbus.service.method(PROFILE_IFACE, in_signature="s", out_signature="")
    def RequestDisconnection(self, device):
        pass


def _control_lock_path():
    """Per-user lock file shared by every Maid BT process."""
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    folder = os.path.join(base, "maid-bt")
    try:
        os.makedirs(folder, mode=0o700, exist_ok=True)
    except OSError:
        folder = "/tmp"
    return os.path.join(folder, "soundcore-control.lock")


def _take_control_lock(timeout):
    """Serialise RFCOMM sessions.

    BlueZ lets one process register a profile UUID at a time, and the
    buds accept one control session at a time. Two directions (the
    settings window reading EQ while the device page reads battery)
    used to race: the loser got "org.bluez.Error.NotPermitted: UUID
    already registered". A file lock makes the second caller wait its
    turn instead of failing.
    """
    fd = os.open(_control_lock_path(), os.O_CREAT | os.O_RDWR, 0o600)
    end = time.time() + timeout
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.ftruncate(fd, 0)
            os.write(fd, str(os.getpid()).encode())
            return fd
        except BlockingIOError:
            if time.time() >= end:
                os.close(fd)
                raise RuntimeError(
                    "the buds' control channel is busy (another Maid BT "
                    "action is still running); try again in a moment")
            time.sleep(0.1)


def _connect_rfcomm(mac, uuid, timeout=8.0):
    """Open the device's RFCOMM socket the BlueZ-supported way.

    Register a client profile, ask the buds to connect to it
    (ConnectProfile), take the socket fd they dial back with. This is
    the same flow the upstream tool performs over the bluer crate.
    """
    bus = dbus.SystemBus()
    path = "/org/maidware/bt/soundcore"
    want = _dev_path(mac)
    sink = {}
    mainloop = GLib.MainLoop()
    profile = _Profile(bus, path, sink, want)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"),
                             PROFILE_MANAGER)
    props = {"Name": dbus.String("Maid BT soundcore controller"),
             "Role": dbus.String("Client"),
             "RequireAuthentication": dbus.Boolean(False),
             "RequireAuthorization": dbus.Boolean(False)}
    registered = False
    fired = {"deadline": False}
    deadline = None
    tick = None

    def trigger():
        dev = dbus.Interface(bus.get_object("org.bluez", want),
                             "org.bluez.Device1")
        # Do not wait for ConnectProfile's reply: BlueZ often never sends
        # one for SPP client profiles, but it dials the profile back over
        # NewConnection almost immediately. A synchronous call blocked the
        # GLib loop for the whole timeout (25s reads in the settings UI).
        def failed(exc):
            sink.setdefault("error", str(exc))

        try:
            dev.ConnectProfile(uuid, reply_handler=lambda: None,
                               error_handler=failed, timeout=timeout)
        except Exception as exc:  # noqa: BLE001 - any failure: keep waiting
            sink.setdefault("error", str(exc))

    def watch():
        if sink.get("fd") is not None:
            sink["tick_done"] = True
            mainloop.quit()
            return False
        if sink.get("error") and sink.get("tick", 0) > 20:
            sink["tick_done"] = True
            mainloop.quit()
            return False
        sink["tick"] = sink.get("tick", 0) + 1
        return True

    def _deadline():
        fired["deadline"] = True
        mainloop.quit()

    try:
        # BlueZ releases a profile asynchronously. The previous CLI
        # process may have closed its connection a moment ago, or a
        # concurrent reader may still be tearing down: retry the
        # registration briefly instead of failing the whole read.
        for attempt in range(6):
            try:
                manager.RegisterProfile(path, uuid, props)
                registered = True
                break
            except dbus.exceptions.DBusException as exc:
                name = getattr(exc, "get_dbus_name", lambda: "")()
                if (name == "org.bluez.Error.NotPermitted"
                        and "already registered" in str(exc)):
                    if attempt == 0:
                        # clear a registration left by this same process
                        # (a failed first pass in Device.open's retry)
                        try:
                            manager.UnregisterProfile(path)
                        except Exception:  # noqa: BLE001
                            pass
                    time.sleep(0.3 * (attempt + 1))
                    continue
                raise
        if not registered:
            raise RuntimeError(
                "the soundcore control profile is still held by another "
                "process; close other Maid BT windows and retry")

        deadline = GLib.timeout_add(int(timeout * 1000), _deadline)
        # dbus-python + GLib: call ConnectProfile from inside the running
        # loop (a thread calling into the shared connection is not safe)
        GLib.idle_add(trigger)
        tick = GLib.timeout_add(100, watch)
        mainloop.run()
    finally:
        # spent sources self-remove (GLib), so removing them prints
        # "Source ID N was not found" warnings on every run: only remove
        # sources that are still armed
        if deadline is not None and not fired["deadline"]:
            try:
                GLib.source_remove(deadline)
            except Exception:  # noqa: BLE001
                pass
        if tick is not None and fired["deadline"] and not sink.get("tick_done"):
            try:
                GLib.source_remove(tick)
            except Exception:  # noqa: BLE001
                pass
        if registered:
            # give BlueZ a moment to finish releasing the profile; without
            # this, the next (retry) call sees "UUID already registered"
            for _ in range(4):
                try:
                    manager.UnregisterProfile(path)
                    break
                except Exception:  # noqa: BLE001
                    time.sleep(0.2)
        try:
            profile.remove_from_connection()
        except Exception:  # noqa: BLE001
            pass

    if sink.get("fd") is None:
        detail = sink.get("error")
        raise RuntimeError(
            "control channel %s did not open within %.0fs%s"
            % (uuid, timeout, ": " + detail if detail else ""))
    return socket.socket(fileno=sink["fd"], family=socket.AF_BLUETOOTH,
                         type=socket.SOCK_STREAM,
                         proto=socket.BTPROTO_RFCOMM)


class Device:
    """Stateful client for one pair of soundcore buds."""

    def __init__(self, mac, timeout=8.0):
        self.mac = str(mac).upper()
        self.timeout = timeout
        self._sock = None
        self._lock_fd = None
        self.state = None

    def open(self):
        if self._sock is not None:
            return self
        if self._lock_fd is None:
            self._lock_fd = _take_control_lock(self.timeout + 2)
        try:
            try:
                self._open_once()
            except Exception:
                # the buds often still hold the previous control session
                # (a GUI refresh or an apply that just ran); one settle +
                # retry clears most transient unreads. Real outages fail
                # after this too - that is honest. Keep the file lock
                # across the retry so no other process can slip in.
                time.sleep(1.0)
                self._close_socket()
                self._open_once()
        except Exception:
            self._release_lock()
            raise
        return self

    def _open_once(self):
        uuid = find_profile_uuid(self.mac)
        self._sock = _connect_rfcomm(self.mac, uuid, self.timeout)
        self._reader = FrameReader()
        self._wait_state()
        return self

    def _close_socket(self):
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    def _release_lock(self):
        if self._lock_fd is not None:
            try:
                fcntl.flock(self._lock_fd, fcntl.LOCK_UN)
            except OSError:
                pass
            try:
                os.close(self._lock_fd)
            except OSError:
                pass
            self._lock_fd = None

    def close(self):
        self._close_socket()
        self._release_lock()

    def __enter__(self):
        return self.open()

    def __exit__(self, *exc):
        self.close()

    def _send(self, command, body=b""):
        self._sock.sendall(build_frame(command, body))

    def _recv_until(self, want, deadline=4.0):
        """Read frames until one with `want` command arrives."""
        import time
        end = time.time() + deadline
        self._sock.settimeout(0.5)
        while time.time() < end:
            try:
                data = self._sock.recv(4096)
                if not data:
                    break
                frames = self._reader.feed(data)
            except socket.timeout:
                continue
            for command, body in frames:
                if command == want:
                    return body
        raise TimeoutError("no response for command %s" % (want,))

    def _wait_state(self):
        self._send(CMD_GET_STATE)
        body = self._recv_until(CMD_GET_STATE)
        self.state = parse_state(body)
        return self.state

    def set_eq(self, vols):
        """Write a custom 10-band equalizer curve (both ears), then
        read the state back; the curve persists in the buds themselves.
        vols in dB*10 (-120..134), clamped to the app range of
        +/-12.0 dB (=-120..120) to avoid the untested top end."""
        if self._sock is None:
            raise RuntimeError("Device.open() first")
        safe = [max(-120, min(120, int(v))) for v in vols]
        self._send(CMD_SET_EQ, eq_body(self.state, safe))
        try:
            self._recv_until(CMD_SET_EQ, 2.0)  # ack (empty); ignore
        except TimeoutError:
            pass
        return self._wait_state()

    def set_anc(self, ambient="normal", nc_mode=None, manual_strength=None,
                transparency=None, transportation=None):
        """Write sound modes, then read the state back for verification.

        Returns the fresh state dict (raises when the buds reject the
        change, so the caller can show an error instead of lying).
        """
        if self._sock is None:
            raise RuntimeError("Device.open() first")
        body = sound_modes_body(self.state, ambient, nc_mode,
                                manual_strength, transparency,
                                transportation)
        self._send(CMD_SET_SOUND_MODES, body)
        try:
            self._recv_until(CMD_SET_SOUND_MODES, 2.0)  # ack (ok, ignore)
        except TimeoutError:
            pass
        return self._wait_state()
