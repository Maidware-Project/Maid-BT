"""Config load/save for maid-watcher."""
import json
import os

DEFAULTS = {
    "devices": [],
    "reconnect": {"initial_delay_s": 5, "max_delay_s": 120, "give_up_after": 10,
                  "op_cooldown_s": 10},
    "recover": {"adapter_cycle": True},
    "calls": {"enabled": True, "pause_media": True, "mute_discord": True,
              "max_call_mode_s": 300},
    "battery": {"warn_percent": 25, "critical_percent": 12, "poll_s": 120},
    "saver": {"enabled": False, "idle_minutes": 30},
    "fallback_grab": {"enabled": False},
    "bt_fallback": {"enabled": False},
    "route_comms": {"enabled": True},
    "laptop": {"mode": "auto"},
}

# SMBIOS chassis types that run on battery at least sometimes.
PORTABLE_CHASSIS = {8, 9, 10, 11, 14, 30, 31, 32}


def chassis_type():
    try:
        with open("/sys/class/dmi/id/chassis_type") as f:
            return int(f.read().strip().split()[0])
    except (OSError, ValueError, IndexError):
        return None


def short_name(dev):
    """Short display name: explicit `short` field, else brand + number.

    "Acme Buds 5" -> "Acme 5". Used in notifications.
    """
    if dev.get("short"):
        return dev["short"]
    import re
    name = dev.get("name", dev.get("mac", "?"))
    words = name.split()
    if not words:
        return name
    brand = words[0].capitalize()
    nums = re.findall(r"\d+", name)
    return f"{brand} {nums[-1]}" if nums else brand


def laptop_mode(cfg):
    """True when radio-gentle laptop behavior applies."""
    mode = cfg.get("laptop", {}).get("mode", "auto")
    if mode == "on":
        return True
    if mode == "off":
        return False
    ct = chassis_type()
    return ct in PORTABLE_CHASSIS if ct is not None else False

CONFIG_PATH = os.path.expanduser("~/.config/maid-watcher/config.json")


def load(path=CONFIG_PATH):
    cfg = json.loads(json.dumps(DEFAULTS))
    if os.path.exists(path):
        try:
            with open(path) as f:
                user = json.load(f)
        except ValueError as e:
            raise SystemExit(f"bad config {path}: {e} - fix it or remove the file")
        for key, val in user.items():
            if isinstance(val, dict) and isinstance(cfg.get(key), dict):
                cfg[key].update(val)
            else:
                cfg[key] = val
    cfg["devices"] = sorted(cfg.get("devices", []),
                            key=lambda d: d.get("priority", 99))[:2]
    return cfg
