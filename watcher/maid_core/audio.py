"""Audio helpers: PipeWire first, PulseAudio fallback (Linux Mint and
older stacks run PulseAudio, where wpctl/pw-dump do not exist). Every
helper degrades to None/False/[] instead of raising."""
import json
import subprocess


def _run(*args, timeout=10):
    try:
        return subprocess.run(args, capture_output=True, text=True,
                              timeout=timeout)
    except (subprocess.SubprocessError, FileNotFoundError):
        return None


def _pw_dump():
    p = _run("pw-dump")
    if not p or p.returncode != 0:
        return []
    try:
        return json.loads(p.stdout)
    except ValueError:
        return []


def bluez_card_id(mac):
    """PipeWire card id for a BT device, or None."""
    mac_uc = mac.upper().replace(":", "_")
    for node in _pw_dump():
        info = node.get("info", {})
        props = info.get("props", {})
        if props.get("device.bus") != "bluetooth":
            continue
        if mac_uc not in str(props.get("device.name", "")).upper():
            continue
        # PipeWire exposes BT cards as Interface:Device nodes.
        ntype = str(node.get("type", "")).lower()
        if "device" in ntype or "card" in ntype:
            return node.get("id")
    # fallback: wpctl status parse
    p = _run("wpctl", "status")
    if p and p.stdout:
        import re
        for line in p.stdout.splitlines():
            if "bluez" in line.lower() and "card" in line.lower():
                m = re.search(r"(\d+)\.", line)
                if m:
                    return int(m.group(1))
    # fallback: PulseAudio card index (pactl works on both stacks)
    idx = pactl_bluez_card_index(mac)
    if idx is not None:
        return idx
    return None


def pactl_bluez_card_index(mac):
    """PulseAudio 'Card #N' index for a BT device, or None."""
    import re
    p = _run("pactl", "list", "cards")
    if not p or not p.stdout:
        return None
    mac_us = mac.upper().replace(":", "_")
    cur = None
    for line in p.stdout.splitlines():
        m = re.match(r"Card #(\d+)", line)
        if m:
            cur = m.group(1)
        if cur is not None and ("bluez_card." + mac_us) in line:
            return cur
    return None


def set_profile_a2dp(mac):
    """Force high-fidelity A2DP sink profile on the BT card.

    Card object ids go stale across reconnects and the bare
    'a2dp-sink' alias does not always stick, so re-resolve the card and
    walk explicit codec profiles until one holds. Never leaves the card
    worse than found: restores the previous profile on failure.
    """
    import time
    prev = active_profile(mac)
    for profile in ("a2dp-sink", "a2dp_sink",
                    "a2dp-sink-aac", "a2dp-sink-sbc"):
        card = bluez_card_id(mac)
        if card is None:
            continue
        p = _run("wpctl", "set-profile", str(card), profile)
        if not (p and p.returncode == 0):
            continue
        time.sleep(1)
        if (active_profile(mac) or "").startswith("a2dp"):
            return True
    # PulseAudio fallback (Mint, or wpctl failing): underscore names.
    # Harmless on PipeWire too - pactl speaks to the same server.
    import subprocess
    card_name = "bluez_card." + mac.upper().replace(":", "_")
    for profile in ("a2dp_sink", "a2dp_sink_aac", "a2dp_sink_sbc",
                    "a2dp_sink_ldac"):
        try:
            r = subprocess.run(
                ["pactl", "set-card-profile", card_name, profile],
                capture_output=True, timeout=10)
        except (subprocess.SubprocessError, FileNotFoundError):
            return False
        if r.returncode != 0:
            continue
        time.sleep(1)
        if (active_profile(mac) or "").startswith("a2dp"):
            return True
    if (active_profile(mac) or "off") == "off" \
            and (prev or "off") != "off":
        card = bluez_card_id(mac)
        if card is not None:
            _run("wpctl", "set-profile", str(card), prev)
    return False


def active_profile(mac):
    """Active card profile name for a BT device, or None."""
    import re
    p = _run("pactl", "list", "cards")
    if not p or not p.stdout:
        return None
    mac_us = mac.upper().replace(":", "_")
    in_card = False
    for line in p.stdout.splitlines():
        if line.startswith("Card #"):
            in_card = False
        if "bluez_card." + mac_us in line:
            in_card = True
        if in_card:
            m = re.search(r"Active Profile:\s*(\S+)", line)
            if m:
                return m.group(1)
    return None


def _has_pw():
    """True when PipeWire tools exist (false on PulseAudio-only Mint)."""
    import shutil
    return shutil.which("pw-dump") is not None


def _pactl_streams():
    """Fallback stream list via pactl: [(id:int, app:str, recording:bool)]."""
    import re
    out = []
    for args, recording in ((["list", "sink-inputs"], False),
                            (["list", "source-outputs"], True)):
        cur_id, cur_app = None, ""
        for line in _pactl(args).splitlines():
            m = re.match(r"(?:Sink Input|Source Output) #(\d+)", line)
            if m:
                if cur_id is not None:
                    out.append((cur_id, cur_app, recording))
                cur_id, cur_app = int(m.group(1)), ""
                continue
            m = re.match(r'\s*application\.name = "(.*)"', line)
            if m:
                cur_app = m.group(1)
        if cur_id is not None:
            out.append((cur_id, cur_app, recording))
    return out


def find_app_streams(patterns):
    """Return [ids] of app stream nodes matching app name patterns."""
    ids = []
    for node in _pw_dump():
        info = node.get("info", {})
        props = info.get("props", {})
        app = (str(props.get("application.name", "")) + " "
               + str(props.get("node.name", ""))).lower()
        media_class = str(info.get("props", {}).get("media.class", ""))
        if any(pat.lower() in app for pat in patterns) and (
                "Stream/Input" in media_class or "Stream/Output" in media_class):
            ids.append(node.get("id"))
    if ids or _has_pw():
        return ids
    # PulseAudio fallback (Mint): ids are pactl stream numbers.
    return [sid for sid, app, _rec in _pactl_streams()
            if any(pat.lower() in app.lower() for pat in patterns)]


def set_mute(node_id, mute):
    import subprocess
    p = _run("wpctl", "set-mute", str(node_id), "1" if mute else "0")
    if p and p.returncode == 0:
        return True
    # PulseAudio fallback: try both stream directions.
    val = "1" if mute else "0"
    for cmd in (["set-sink-input-mute", str(node_id), val],
                ["set-source-output-mute", str(node_id), val]):
        try:
            r = subprocess.run(["pactl"] + cmd, capture_output=True,
                               timeout=10)
            if r.returncode == 0:
                return True
        except (subprocess.SubprocessError, FileNotFoundError):
            continue
    return False


COMMS_PATTERNS = ("discord", "vesktop", "webcord", "vencord")


def _pactl(args):
    import subprocess
    try:
        p = subprocess.run(["pactl"] + args, capture_output=True,
                           text=True, timeout=10)
        return p.stdout if p.returncode == 0 else ""
    except (subprocess.SubprocessError, FileNotFoundError):
        return ""


def default_sink_name():
    out = _pactl(["get-default-sink"]).strip()
    return out or None


def default_source_name():
    out = _pactl(["get-default-source"]).strip()
    return out or None


def route_comms_to_default(patterns=COMMS_PATTERNS):
    """Move matching playback streams onto the default sink.

    Playback only - microphone routing is never touched. Returns the
    number of streams moved. Streams already on the default are left
    alone, so this is a no-op aligner, not a hijack.
    """
    import re
    default = default_sink_name()
    if not default:
        return 0
    # map sink index -> name
    sinks = {}
    cur = None
    for line in _pactl(["list", "sinks"]).splitlines():
        m = re.match(r"Sink #(\d+)", line)
        if m:
            cur = m.group(1)
        m = re.match(r"\s*Name: (\S+)", line)
        if m and cur is not None:
            sinks[cur] = m.group(1)
    moved = 0

    def flush():
        nonlocal moved
        if cur_id is not None and cur_sink is not None:
            if any(pat.lower() in cur_app.lower() for pat in patterns) \
                    and sinks.get(cur_sink) != default:
                _pactl(["move-sink-input", cur_id, default])
                moved += 1

    cur_id, cur_app, cur_sink = None, "", None
    for line in _pactl(["list", "sink-inputs"]).splitlines():
        m = re.match(r"Sink Input #(\d+)", line)
        if m:
            flush()
            cur_id, cur_app, cur_sink = m.group(1), "", None
            continue
        m = re.match(r"\s*Sink: (\d+)", line)
        if m:
            cur_sink = m.group(1)
            continue
        m = re.match(r'\s*application\.name = "(.*)"', line)
        if m:
            cur_app = m.group(1)
    flush()
    return moved


def mic_holders():
    """[(app, node)] holding any microphone open right now.

    An open mic forces HFP mode, which blocks A2DP. Lesson learned
    2026-10-14: Vesktop idling on mic silently vetoed every profile
    switch with zero errors logged anywhere.
    """
    out = []
    for node in _pw_dump():
        info = node.get("info", {})
        props = info.get("props", {})
        if "Stream/Input" not in str(props.get("media.class", "")):
            continue
        if info.get("state") != "running":
            continue
        out.append((str(props.get("application.name", "?")),
                    str(props.get("node.name", "?"))))
    return out


def bt_mic_holders(mac=None):
    """Subset of mic_holders() capturing from a Bluetooth mic.

    Only these block A2DP - a capture on a USB mic is harmless.
    Matches node/target names containing bluez (or the device MAC).
    """
    mac_us = (mac or "").upper().replace(":", "_")
    out = []
    for node in _pw_dump():
        info = node.get("info", {})
        props = info.get("props", {})
        if "Stream/Input" not in str(props.get("media.class", "")):
            continue
        if info.get("state") != "running":
            continue
        blob = (str(props.get("node.name", "")) + " "
                + str(props.get("target.object", ""))).lower()
        if "bluez" in blob or (mac_us and mac_us in blob.upper()):
            out.append((str(props.get("application.name", "?")),
                        str(props.get("node.name", "?"))))
    return out


def _pactl_ok(args):
    import subprocess
    try:
        return subprocess.run(["pactl"] + args, capture_output=True,
                              timeout=10).returncode == 0
    except (subprocess.SubprocessError, FileNotFoundError):
        return False


def move_recording_to_source(patterns, source_name):
    """Move matching recording streams to the given source.

    Used to free the BT mic (e.g. onto a USB mic) without killing the
    call. Returns moved count. pactl-based: works on PulseAudio too.
    """
    import re
    moved = 0
    cur_id, cur_app = None, ""
    for line in _pactl(["list", "source-outputs"]).splitlines():
        m = re.match(r"Source Output #(\d+)", line)
        if m:
            if cur_id is not None and any(
                    pat.lower() in cur_app.lower() for pat in patterns):
                if _pactl_ok(["move-source-output", cur_id, source_name]):
                    moved += 1
            cur_id, cur_app = m.group(1), ""
            continue
        m = re.match(r'\s*application\.name = "(.*)"', line)
        if m:
            cur_app = m.group(1)
    if cur_id is not None and any(
            pat.lower() in cur_app.lower() for pat in patterns):
        if _pactl_ok(["move-source-output", cur_id, source_name]):
            moved += 1
    return moved


def earbuds_active(mac):
    """True if any running stream links to the BT device."""
    mac_uc = mac.upper()
    for node in _pw_dump():
        info = node.get("info", {})
        if info.get("state") != "running":
            continue
        blob = json.dumps(info)
        if mac_uc.replace(":", "_") in blob.upper() or "bluez" in blob.lower():
            return True
    if _has_pw():
        return False
    # PulseAudio fallback: any RUNNING stream on a bluez sink/source.
    import re
    bluez_sinks, bluez_sources = set(), set()
    cur = None
    for line in _pactl(["list", "sinks"]).splitlines():
        m = re.match(r"Sink #(\d+)", line)
        if m:
            cur = ("sink", m.group(1))
        elif cur is not None and "bluez" in line.lower() \
                and ("Name:" in line or "node.name" in line):
            bluez_sinks.add(cur[1])
    for line in _pactl(["list", "sources"]).splitlines():
        m = re.match(r"Source #(\d+)", line)
        if m:
            cur = ("source", m.group(1))
        elif cur is not None and "bluez" in line.lower() \
                and ("Name:" in line or "node.name" in line):
            bluez_sources.add(cur[1])
    for args, want in ((["list", "sink-inputs"], bluez_sinks),
                       (["list", "source-outputs"], bluez_sources)):
        cur_sink, running = None, False
        for line in _pactl(args).splitlines():
            if re.match(r"(?:Sink Input|Source Output) #\d+", line):
                if running and cur_sink in want:
                    return True
                cur_sink, running = None, False
            elif re.match(r"\s*State: RUNNING", line):
                running = True
            else:
                m = re.match(r"\s*Sink: (\d+)", line)
                if m:
                    cur_sink = m.group(1)
    return False


# Typical one-way Bluetooth codec latencies (seconds, conservative).
# Software cannot remove codec delay; players must be offset instead.
CODEC_LATENCY = {
    "sbc": 0.20,
    "sbc_xq": 0.22,
    "aac": 0.20,
    "aptx": 0.15,
    "aptx_hd": 0.20,
    "ldac": 0.30,
}


def codec_of_profile(profile):
    """'aac' from 'a2dp-sink-aac'; None for non-A2DP profiles."""
    if not profile or not profile.startswith("a2dp"):
        return None
    parts = profile.split("a2dp-sink", 1)
    if len(parts) < 2 or not parts[1].strip("-_"):
        return None
    return parts[1].strip("-_").lower()


def mpv_sockets():
    """mpv IPC sockets to drive (user enables with input-ipc-server).

    Only real sockets owned by this user count: on a shared machine
    anyone could otherwise plant /tmp/mpvsocket and receive the
    commands sent through it. $XDG_RUNTIME_DIR is checked before /tmp.
    """
    import os
    import stat
    candidates = []
    env = os.environ.get("MPV_SOCKET", "")
    if env:
        candidates.append(env)
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if runtime:
        candidates.append(os.path.join(runtime, "mpv/socket"))
    candidates += ["/tmp/mpvsocket",
                   os.path.join(os.path.expanduser("~"), ".config/mpv/socket")]
    found = []
    for path in candidates:
        try:
            st = os.lstat(path)
        except OSError:
            continue
        if stat.S_ISSOCK(st.st_mode) and st.st_uid == os.getuid():
            found.append(path)
    return found


def set_mpv_delay(seconds):
    """Set mpv audio-delay on all reachable instances. Returns count."""
    import json as _json
    import socket as _socket
    done = 0
    msg = (_json.dumps({"command": ["set_property", "audio-delay",
                                    round(seconds, 2)]}) + "\n").encode()
    for path in mpv_sockets():
        try:
            sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
            sock.settimeout(3)
            sock.connect(path)
            sock.sendall(msg)
            sock.recv(4096)
            sock.close()
            done += 1
        except OSError:
            continue
    return done


def apply_av_offset(mac):
    """Offset mpv to the current codec latency. Returns delay or None."""
    delay = CODEC_LATENCY.get(codec_of_profile(active_profile(mac)))
    if delay is None:
        return None
    if set_mpv_delay(-delay) > 0:
        return -delay
    return None
