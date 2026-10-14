# AGENTS.md — Maid BT (for AI assistants; humans see README.md)

One maintainer plus friends helping out — keep every change small,
reviewable, and justified. No drive-by refactors, no new dependencies
without asking, no behavior change hiding inside a cleanup.

People over AI, always: this project is human-built and human-reviewed.
AI assists, humans decide. Write code, messages, and docs a person can
follow with no assistant involved — clear names, plain language, no
cleverness. The goal is users who understand their system, not users
dependent on one.

Bash-first Bluetooth earbuds switcher. Lowercase terse voice in docs.

## Layout

- `bin/` toggle + `buds-fallback.sh` watcher + wrappers + intent server
- `watcher/` Maid Watcher daemon (`maid-watcher` + `maid_core/`) — Python
- `wireplumber/` opt-in PipeWire tweaks, `systemd/` user units,
  `plasmoid/` tray widget, `desktop/` launchers, `phone/` MacroDroid docs
- `install.sh` multi-distro installer, `tests/run.sh` full suite

## Rules

- Never commit personal data: no MACs, names, IPs, or home-dir paths
  (tests enforce this; `desktop/*.desktop` Exec paths use the rewrite
  convention handled by install.sh — that one pattern is exempt).
- New behavior ships **off** (opt-in prompts). Never auto-teardown audio
  links; warm-link over disconnect, backoff over hammering.
- Installer copies, never symlinks; backs up overwritten files.
- Commit style: short lowercase summaries.

## Verify

- `bash tests/run.sh` — full suite, hardware-free (stubs), has sleeps
- `bash install.sh --check` — dry run, must write nothing
- `python3 -m py_compile watcher/maid-watcher watcher/maid_core/*.py`
- Personal-data grep lives in tests/run.sh — keep it green.
