# AGENTS.md — Maid BT (for AI assistants; humans see README.md)

One maintainer plus friends helping out — keep every change small,
reviewable, and justified. No drive-by refactors, no new dependencies
without asking, no behavior change hiding inside a cleanup.

Honesty is non-negotiable: say what you actually did versus what you
were asked to do. Never claim a test ran, a build passed, or hardware
was verified unless it truly happened in this session. Report failures
and shortcuts plainly, mark uncertainty as uncertainty, and never hide
a skipped step behind vague wording.

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
- CODE_OF_CONDUCT.md applies to code, comments, and docs:
  technical scope, no politics, stay neutral.
- Commit style: short lowercase summaries with a prefix (`fix:`,
  `feat:`, `docs:`, `tests:`, `chore:`), one logical change each.
  Sign off every commit (`git commit -s`); AI-assisted work adds an
  `Assisted-by:` trailer naming the tool. Bug fixes cite `Fixes: #N`.

## Verify

- `bash tests/run.sh` — full suite, hardware-free (stubs), has sleeps
- `bash install.sh --check` — dry run, must write nothing
- `python3 -m py_compile watcher/maid-watcher watcher/maid_core/*.py`
- Personal-data grep lives in tests/run.sh — keep it green.

Before finishing: pass docs/REVIEW.md.
