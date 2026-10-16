# AGENTS.md - Maid BT (for AI assistants; humans see README.md)

One maintainer plus a few friends helping out. Keep changes small enough
to review, skip refactors nobody asked for, and ask before adding a
dependency. Never hide a behavior change inside a cleanup, and never let a
script tear down an audio link on its own.

Say what you actually did, not what you were asked to do. Audio bugs don't
show up in a stubbed run, so say plainly whether you tested on real earbuds
or only in the fake.

The assistant helps, a person decides. Bluetooth is fiddly enough on its
own, so keep the code readable.

Bash-first Bluetooth earbuds switcher. Lowercase terse voice in docs.

## Layout

- `bin/` toggle + `buds-fallback.sh` watcher + wrappers + intent server
- `watcher/` Maid Watcher daemon (`maid-watcher` + `maid_core/`) - Python
- `wireplumber/` opt-in PipeWire tweaks, `systemd/` user units,
  `plasmoid/` tray widget, `desktop/` launchers, `phone/` MacroDroid docs
- `install.sh` multi-distro installer, `tests/run.sh` full suite

## Rules

- Never commit personal data: no MACs, names, IPs, or home-dir paths
  (tests enforce this; `desktop/*.desktop` Exec paths use the rewrite
  convention handled by install.sh - that one pattern is exempt).
- New behavior ships **off** (opt-in prompts). Never auto-teardown audio
  links; warm-link over disconnect, backoff over hammering.
- Installer copies, never symlinks; backs up overwritten files.
- CODE_OF_CONDUCT.md applies to code, comments, and docs:
  technical scope, no politics, stay neutral.
- Commit style: short lowercase summaries with a prefix (`fix:`,
  `feat:`, `docs:`, `tests:`, `chore:`), one logical change each.
  Sign off every commit (`git commit -s`). Bug fixes cite `Fixes: #N`.

## Verify

- `bash tests/run.sh` - full suite, hardware-free (stubs), has sleeps
- `bash install.sh --check` - dry run, must write nothing
- `python3 -m py_compile watcher/maid-watcher watcher/maid_core/*.py`
- Personal-data grep lives in tests/run.sh - keep it green.

Before finishing: pass docs/REVIEW.md.
