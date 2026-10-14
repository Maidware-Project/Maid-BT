"""Desktop notifications (freedesktop, Plasma-safe)."""
import subprocess

try:
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    _HAVE_DBUS = True
except ImportError:
    _HAVE_DBUS = False

_action_handlers = {}


def _ensure_listener(session_bus=None):
    if not _HAVE_DBUS:
        return None
    try:
        bus = session_bus or dbus.SessionBus()
        bus.add_signal_receiver(
            _on_action, signal_name="ActionInvoked",
            dbus_interface="org.freedesktop.Notifications")
        return bus
    except dbus.DBusException:
        return None


def _on_action(notif_id, action_key):
    cb = _action_handlers.pop(int(notif_id), None)
    if cb:
        try:
            cb(str(action_key))
        except Exception:
            pass


def send(summary, body="", urgency="normal", actions=None,
         on_action=None, session_bus=None):
    """Notify; with actions=[(key, label)] the callback fires on click.

    Falls back to plain notify-send (no actions) without D-Bus.
    """
    if actions and _HAVE_DBUS:
        try:
            bus = _ensure_listener(session_bus)
            if bus is not None:
                obj = bus.get_object("org.freedesktop.Notifications",
                                     "/org/freedesktop/Notifications")
                iface = dbus.Interface(
                    obj, "org.freedesktop.Notifications")
                flat = []
                for key, label in actions:
                    flat += [key, label]
                urg = {"low": 0, "normal": 1, "critical": 2}.get(urgency, 1)
                nid = iface.Notify("Maid Watcher", 0, "audio-headphones",
                                   summary, body, flat,
                                   {"urgency": dbus.Byte(urg)}, 15000)
                if on_action:
                    _action_handlers[int(nid)] = on_action
                return int(nid)
        except Exception:
            pass
    try:
        subprocess.run(["notify-send", "-u", urgency, "-a", "Maid Watcher",
                        summary, body],
                       capture_output=True, timeout=5)
    except (subprocess.SubprocessError, FileNotFoundError):
        pass
    return 0
