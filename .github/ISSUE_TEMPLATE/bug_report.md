---
name: Bug report
about: Something broke - tell it plainly, paste the diagnostics
title: "[bug] "
---

## What happened (plain words)

## What you expected

## Steps (what did you click / run?)

## Versions

- Maid BT commit:
- Distro + Plasma version:
- Earbuds model:

## Diagnostics (paste this - trim your MAC if posting publicly)

```
maid-watcher bugreport
```
<!-- run `maid-watcher bugreport`, paste the whole block below. attaching logs/screenshots is mandatory if they exist. -->

## Extra logs (if audio died)

```
journalctl --user -u buds-fallback -n 30 --no-pager
```
<!-- attaching the relevant log output is mandatory when reporting bugs. -->

---

**note:** before filing, please read `AGENTS.md` in this repo - it's there for a reason.
