"""PipeWire audio helpers via wpctl/pw-dump (no extra deps)."""
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


def find_app_streams(patterns):
    """Return [ids] of PipeWire stream nodes matching app name patterns."""
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
    return ids


def set_mute(node_id, mute):
    p = _run("wpctl", "set-mute", str(node_id), "1" if mute else "0")
    return bool(p and p.returncode == 0)


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
    """mpv IPC sockets to drive (user enables with input-ipc-server)."""
    import os
    candidates = []
    env = os.environ.get("MPV_SOCKET", "")
    if env:
        candidates.append(env)
    home = os.path.expanduser("~")
    candidates += ["/tmp/mpvsocket",
                   os.path.join(home, ".config/mpv/socket")]
    return [c for c in candidates if os.path.exists(c)]


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
