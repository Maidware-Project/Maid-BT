"""Battery polling + idle saver for managed earbuds."""
from . import notify


class BatteryWatch:
    def __init__(self, cfg, monitor):
        self.cfg = cfg["battery"]
        self.saver = cfg["saver"]
        self.monitor = monitor
        self.warned = set()
        self.crit_warned = set()
        self.idle_since = {}

    def poll(self, devices):
        from . import audio
        for dev in devices:
            mac = dev["mac"]
            if not self.monitor.is_connected(mac):
                self.warned.discard(mac)
                self.crit_warned.discard(mac)
                self.idle_since.pop(mac, None)
                continue
            pct = self.monitor.battery_percent(mac)
            if pct is not None:
                if pct <= self.cfg["critical_percent"]:
                    if mac not in self.crit_warned:
                        self.crit_warned.add(mac)
                        notify.send(f"{dev.get('name', mac)} battery critical",
                                    f"{pct}% — charge soon", "critical")
                elif pct <= self.cfg["warn_percent"]:
                    if mac not in self.warned:
                        self.warned.add(mac)
                        notify.send(f"{dev.get('name', mac)} battery low",
                                    f"{pct}% remaining")
                else:
                    self.warned.discard(mac)
                    self.crit_warned.discard(mac)
            # idle saver (opt-in): disconnect after N quiet minutes
            if self.saver.get("enabled"):
                import time
                if audio.earbuds_active(mac):
                    self.idle_since.pop(mac, None)
                else:
                    if mac not in self.idle_since:
                        self.idle_since[mac] = time.time()
                    idle_min = (time.time() - self.idle_since[mac]) / 60
                    if idle_min >= self.saver.get("idle_minutes", 30):
                        notify.send("Battery saver",
                                    f"Disconnecting idle {dev.get('name', mac)}")
                        self.monitor.disconnect(mac)
                        self.idle_since.pop(mac, None)
