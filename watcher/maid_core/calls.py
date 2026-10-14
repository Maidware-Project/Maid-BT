"""KDE Connect call detection -> call mode (pause, mute Discord).

Watches org.kde.kdeconnect.device.telephony callReceived(sss) on every
paired phone. End-of-call is detected by keyword heuristic plus a safety
timer, so unknown event schemas fail safe (mode always exits).
"""
import subprocess
import dbus

TELEPHONY_IFACE = "org.kde.kdeconnect.device.telephony"
KDECONNECT = "org.kde.kdeconnect"

END_WORDS = ("end", "idle", "miss", "reject", "cancel", "declin",
             "finish", "hangup", "bye")
ACTIVE_WORDS = ("ring", "talk", "call", "answer", "dial", "incoming",
                "outgoing", "active", "oncall")


def classify_event(args):
    """('active'|'ended'|'unknown') from signal args, case-insensitive."""
    text = " ".join(str(a) for a in args).lower()
    if any(w in text for w in END_WORDS):
        return "ended"
    if any(w in text for w in ACTIVE_WORDS):
        return "active"
    return "unknown"


def phone_paths(bus):
    """D-Bus object paths of paired phones."""
    paths = []
    try:
        obj = bus.get_object(KDECONNECT, "/modules/kdeconnect")
        # enumerate via daemon device list
        daemon = bus.get_object(KDECONNECT, "/org/kde/kdeconnect/daemon")
        iface = dbus.Interface(daemon, "org.kde.kdeconnect.daemon")
        for dev_id in iface.devices():
            paths.append("/modules/kdeconnect/devices/" + str(dev_id))
    except dbus.DBusException:
        pass
    if not paths:
        # fallback: parse kdeconnect-cli ids
        try:
            p = subprocess.run(["kdeconnect-cli", "--list-devices", "--id-only"],
                               capture_output=True, text=True, timeout=10)
            for line in p.stdout.splitlines():
                dev_id = line.strip()
                if dev_id:
                    paths.append("/modules/kdeconnect/devices/" + dev_id)
        except (subprocess.SubprocessError, FileNotFoundError):
            pass
    return paths


class CallWatcher:
    def __init__(self, bus, on_call_start, on_call_end):
        self.bus = bus
        self.on_call_start = on_call_start
        self.on_call_end = on_call_end
        self.in_call = False
        for path in phone_paths(bus):
            try:
                bus.add_signal_receiver(
                    self._call_received,
                    signal_name="callReceived",
                    dbus_interface=TELEPHONY_IFACE,
                    path=path)
            except dbus.DBusException:
                continue

    def _call_received(self, *args):
        verdict = classify_event(args)
        if verdict == "ended":
            if self.in_call:
                self.in_call = False
                self.on_call_end("call ended")
        elif verdict == "active":
            if not self.in_call:
                self.in_call = True
                info = " ".join(str(a) for a in args if a) or "unknown caller"
                self.on_call_start(info)
        else:
            # unknown schema: treat as activity, log args for tuning
            if not self.in_call:
                self.in_call = True
                self.on_call_start("phone event: " + " ".join(map(str, args)))
