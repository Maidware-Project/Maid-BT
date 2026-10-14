"""MPRIS media pause/resume (no playerctl needed)."""
import dbus

MPRIS_PREFIX = "org.mpris.MediaPlayer2."
EXCLUDE = ("kdeconnect",)


def _players(bus):
    out = []
    for name in bus.list_names():
        if not name.startswith(MPRIS_PREFIX):
            continue
        if any(x in name for x in EXCLUDE):
            continue
        try:
            obj = bus.get_object(name, "/org/mpris/MediaPlayer2")
            props = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
            status = str(props.Get("org.mpris.MediaPlayer2.Player",
                                   "PlaybackStatus"))
            out.append((name, status))
        except dbus.DBusException:
            continue
    return out


def pause_all(bus):
    """Pause playing players. Returns [names] that were playing."""
    paused = []
    for name, status in _players(bus):
        if status != "Playing":
            continue
        try:
            obj = bus.get_object(name, "/org/mpris/MediaPlayer2")
            dbus.Interface(obj, "org.mpris.MediaPlayer2.Player").Pause()
            paused.append(name)
        except dbus.DBusException:
            continue
    return paused


def resume(bus, names):
    for name in names:
        try:
            obj = bus.get_object(name, "/org/mpris/MediaPlayer2")
            dbus.Interface(obj, "org.mpris.MediaPlayer2.Player").Play()
        except dbus.DBusException:
            continue
