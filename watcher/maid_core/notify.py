"""Desktop notifications (freedesktop, Plasma-safe)."""
import subprocess


def send(summary, body="", urgency="normal"):
    try:
        subprocess.run(["notify-send", "-u", urgency, "-a", "Maid Watcher",
                        summary, body],
                       capture_output=True, timeout=5)
    except (subprocess.SubprocessError, FileNotFoundError):
        pass
