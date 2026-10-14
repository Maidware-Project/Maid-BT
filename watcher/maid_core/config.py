"""Config load/save for maid-watcher."""
import json
import os

DEFAULTS = {
    "devices": [],
    "reconnect": {"initial_delay_s": 5, "max_delay_s": 120, "give_up_after": 10},
    "calls": {"enabled": True, "pause_media": True, "mute_discord": True,
              "max_call_mode_s": 300},
    "battery": {"warn_percent": 25, "critical_percent": 12, "poll_s": 120},
    "saver": {"enabled": False, "idle_minutes": 30},
}

CONFIG_PATH = os.path.expanduser("~/.config/maid-watcher/config.json")


def load(path=CONFIG_PATH):
    cfg = json.loads(json.dumps(DEFAULTS))
    if os.path.exists(path):
        with open(path) as f:
            user = json.load(f)
        for key, val in user.items():
            if isinstance(val, dict) and isinstance(cfg.get(key), dict):
                cfg[key].update(val)
            else:
                cfg[key] = val
    cfg["devices"] = sorted(cfg.get("devices", []),
                            key=lambda d: d.get("priority", 99))[:3]
    return cfg
