"""Charging-case inference for Maid Watcher (BlueZ).

A closed charging case powers the buds down: they stop advertising and
stop answering. With the lid open, they advertise again - and BlueZ
surfaces live observations of that during a discovery window as Device1
property updates (RSSI churn, or the device connecting on its own).

So "advertising within the window" ~ out of the case; "radio-silent for
a whole probe window" ~ docked. Probing is deliberately passive: a
short windowed discovery filtered to the managed MAC. No connect
attempts, no page storms, one discovery at a time (adapter-global).

Return contract for visible():
  True   buds observed distinctly in the window -> out of the case
  False  full window elapsed, nothing observed  -> docked (or dead)
  None   discovery unavailable (adapter off / not ready / rfkill)
         -> unknown; callers must not claim "docked" off this
"""
import threading
import time
import dbus

from .bluez import BLUEZ, ADAPTER_IFACE, DEVICE_IFACE, mac_to_path

OBJECT_MANAGER_IFACE = "org.freedesktop.DBus.ObjectManager"

_probe_lock = threading.Lock()  # discovery is adapter-global: serialize


class DockProbe:
    """Passive one-MAC advertising probe ("are the buds in the case?")."""

    def __init__(self, mac, adapter_path="/org/bluez/hci0"):
        self.mac = mac
        self.path = mac_to_path(mac)
        self.adapter_path = adapter_path

    def _snap(self, bus):
        """Device1 property dict right now ({} when unknown)."""
        try:
            om = dbus.Interface(bus.get_object(BLUEZ, "/"),
                                OBJECT_MANAGER_IFACE)
            objs = om.GetManagedObjects(dbus_interface=OBJECT_MANAGER_IFACE)
        except dbus.DBusException:
            return {}
        return objs.get(self.path, {}).get(DEVICE_IFACE, {})

    def visible(self, window_s=8, poll_s=1.0):
        """Advertised-at-least-once oracle. See module docstring."""
        with _probe_lock:
            bus = None
            started = False
            seen = False
            try:
                bus = dbus.SystemBus()
                ad = dbus.Interface(
                    bus.get_object(BLUEZ, self.adapter_path), ADAPTER_IFACE)
                try:
                    # keep discovery noise limited to this one MAC
                    ad.SetDiscoveryFilter(
                        {"Addresses": dbus.Array([self.mac], signature="s"),
                         "Transport": "auto"},
                        dbus_interface=ADAPTER_IFACE)
                except dbus.DBusException:
                    pass  # clockwork fallback: unfiltered scan, oracle
                    # still works - stale props simply never churn.
                ad.StartDiscovery(dbus_interface=ADAPTER_IFACE)
                started = True
            except dbus.DBusException:
                return None  # cannot scan right now: unknown

            prev = self._snap(bus)
            deadline = time.time() + max(1, int(window_s))
            while time.time() < deadline and not seen:
                time.sleep(poll_s)
                props = self._snap(bus)
                if props.get("Connected"):
                    seen = True  # lid-open wake connected by itself
                    break
                # fresh observation = RSSI gained or changed since the
                # last snapshot; stale values from an old discovery
                # never churn, so a docked device stays uniformly quiet
                was, now_ = prev.get("RSSI"), props.get("RSSI")
                if (was is None and now_ is not None) \
                        or (was is not None and now_ != was):
                    seen = True
                prev = props
            return seen
        # unreachable: with-block always returns via the seen path above
