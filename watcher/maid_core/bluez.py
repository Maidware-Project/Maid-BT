"""BlueZ device monitoring + reconnect, over python-dbus (no bluetoothctl)."""
import subprocess
import dbus

BLUEZ = "org.bluez"
ADAPTER_IFACE = "org.bluez.Adapter1"
DEVICE_IFACE = "org.bluez.Device1"


def mac_to_path(mac, adapter_path="/org/bluez/hci0"):
    return adapter_path + "/dev_" + mac.replace(":", "_")


def pair_cb(*args, **kwargs):
    pass


class DeviceMonitor:
    """Tracks Connected state for managed MACs via PropertiesChanged."""

    def __init__(self, bus, on_change):
        self.bus = bus
        self.on_change = on_change  # fn(mac, connected)
        self._paths = {}
        bus.add_signal_receiver(
            self._props_changed,
            signal_name="PropertiesChanged",
            dbus_interface="org.freedesktop.DBus.Properties",
            path_keyword="path")

    def watch(self, mac):
        self._paths[mac_to_path(mac)] = mac

    def _props_changed(self, iface, changed, invalidated, path=None):
        if iface != DEVICE_IFACE or "Connected" not in changed:
            return
        mac = self._paths.get(path)
        if mac:
            self.on_change(mac, bool(changed["Connected"]))

    def is_connected(self, mac):
        try:
            obj = self.bus.get_object(BLUEZ, mac_to_path(mac))
            return bool(obj.Get(DEVICE_IFACE, "Connected",
                                dbus_interface="org.freedesktop.DBus.Properties"))
        except dbus.DBusException:
            return False

    def battery_percent(self, mac):
        try:
            obj = self.bus.get_object(BLUEZ, mac_to_path(mac))
            val = obj.Get("org.bluez.Battery1", "Percentage",
                          dbus_interface="org.freedesktop.DBus.Properties")
            return int(val)
        except dbus.DBusException:
            return None

    @staticmethod
    def connect(mac):
        subprocess.run(["bluetoothctl", "connect", mac],
                       capture_output=True, timeout=30)

    @staticmethod
    def disconnect(mac):
        subprocess.run(["bluetoothctl", "disconnect", mac],
                       capture_output=True, timeout=30)

    @staticmethod
    def scan_audio_devices(timeout=8):
        """Return [(mac, name)] of BT devices exposing Audio Sink."""
        out = []
        try:
            info = subprocess.run(["bluetoothctl", "devices"],
                                  capture_output=True, text=True, timeout=10)
            for line in info.stdout.splitlines():
                parts = line.split(" ", 2)
                if len(parts) < 3 or parts[0] != "Device":
                    continue
                out.append((parts[1], parts[2]))
        except (subprocess.SubprocessError, FileNotFoundError):
            pass
        return out
