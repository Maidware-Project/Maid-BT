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
        if (props.get("device.bus") == "bluetooth"
                and mac_uc in str(props.get("device.name", "")).upper()):
            if "card" in str(node.get("type", "")).lower() \
                    or "Card" in str(node.get("type", "")):
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
    """Force high-fidelity A2DP sink profile on the BT card."""
    card = bluez_card_id(mac)
    if card is None:
        return False
    for profile in ("a2dp-sink", "a2dp_sink"):
        p = _run("wpctl", "set-profile", str(card), profile)
        if p and p.returncode == 0:
            return True
    return False


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
