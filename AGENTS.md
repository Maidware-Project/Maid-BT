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

## What you can't do here

- The suite is hardware-free by design. A stubbed run cannot prove audio
  behavior; that needs real earbuds and a live PipeWire session.
- The watcher daemon reacts to real device events, and the wireplumber
  tweaks change a real stack. Neither is exercised by the suite.
- When you tested only in the fake, say so - it is the difference between
  "looks right" and "works".

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
  Sign off every commit - the trailer is exactly `Signed-off-by: visa`,
  no email. Bug fixes cite `Fixes: #N`.
- `watcher/` is mirrored from the maid-watcher repo and is the copy that
  ships: after changing it, keep the two byte-identical (`diff -r`).

## Never

- Never push. The maintainer pushes; commits stay local until asked.
- Never let a script tear down an audio link on its own, and never ship
  new behavior on by default.
- Never commit a MAC, a device name, an IP, or a home-dir path (the one
  documented Exec-path rewrite is the only exemption).
- Never report real-earbud behavior you did not actually observe.

## Boundaries (do not touch)

- Warm-link over disconnect, backoff over hammering - the reconnect
  strategy is the point of the tool.
- The personal-data grep in `tests/run.sh`; keep it green.
- The installer contract: copies, never symlinks, backs up; and the
  opt-in defaults for the wireplumber tweaks.

## Verify

- `bash tests/run.sh` - full suite, hardware-free (stubs), has sleeps
- `bash install.sh --check` - dry run, must write nothing
- `python3 -m py_compile watcher/maid-watcher watcher/maid_core/*.py`
- Personal-data grep lives in tests/run.sh - keep it green.

## Making a change

1. `git status -sb` first. A commit or a sync can land while you work,
   and amending something already pushed leaves duplicate commits.
2. Make the smallest diff that solves the stated problem.
3. Run `bash tests/run.sh` and `bash install.sh --check`.
4. On real earbuds, watch an actual connect and disconnect. If you could
   not, say the change is stub-only.
5. Pass `docs/REVIEW.md`, then commit with a sign-off. Do not push.

## References

- `README.md` - what it does, supported distros, opt-in tweaks
- `docs/REVIEW.md` - the checklist to pass before a change ships
- `CONTRIBUTING.md` - how to take part
- `CODE_OF_CONDUCT.md` - scope, and what stays out of the repo
- `CHANGELOG.md` - what changed, release by release
- `SECURITY.md` - how to report a security problem
