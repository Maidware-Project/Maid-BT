# Non-systemd service examples (Maid BT)

Maid BT’s core CLI/TUI works without systemd. On systemd user sessions the installer can enable user services (e.g. `buds-fallback.service`, `bt-intent.service`, `maid-watcher.service`). On non-systemd setups, start the daemons from your session/init manager instead.

> These are **examples/templates**. Adjust paths, users, and environment for your distro (OpenRC/runit/s6/dinit), and ensure the scripts are installed (usually under `~/.local/bin/`).

## Common daemons
- **buds-fallback watcher**: `~/.local/bin/buds-fallback.sh` (auto-connect + fallback sink park)
- **intent listener** (optional, phone -> PC LAN): `python3 ~/.local/bin/bt-intent-server.py`
- **Maid Watcher daemon** (optional): `~/.local/bin/maid-watcher run`

All should run in the **user session** with access to your D-Bus session, PipeWire/PulseAudio, and BlueZ.

## OpenRC (user/session example approach)
OpenRC is typically system-level; for user-session daemons you can start them from your compositor/desktop autostart, or use a user supervisor. Example wrapper script you can launch at login:

```sh
#!/bin/sh
# ~/.local/bin/maid-bt-user-services.sh
~/.local/bin/buds-fallback.sh &
# python3 ~/.local/bin/bt-intent-server.py &
# ~/.local/bin/maid-watcher run &
wait
```

If you run OpenRC user services via a supervisor (or distro-specific user-service support), create service scripts that exec the commands above as your user with the correct `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, etc.

## runit (user service example)
Create a user service directory (paths vary by distro, e.g. `~/.runit/sv/` or system-managed user runsvdir):

`~/.runit/sv/maid-bt-buds-fallback/run`:
```sh
#!/bin/sh
exec ~/.local/bin/buds-fallback.sh
```

`~/.runit/sv/maid-bt-intent/run` (optional):
```sh
#!/bin/sh
exec /usr/bin/python3 ~/.local/bin/bt-intent-server.py
```

`~/.runit/sv/maid-watcher/run` (optional):
```sh
#!/bin/sh
exec ~/.local/bin/maid-watcher run
```

Make them executable and link into your runsvdir (e.g. `ln -s ~/.runit/sv/maid-bt-buds-fallback ~/.runit/service/`).

## Notes
- On non-systemd systems, `systemctl --user ...` commands shown by some scripts/docs won’t apply; start/restart the daemons via your init/supervisor instead.
- If PipeWire/WirePlumber are user services, ensure they are running before starting Maid BT watchers.
- For troubleshooting, run `bluetooth-toggle.sh --doctor` and check logs/output from the daemon you started manually.
