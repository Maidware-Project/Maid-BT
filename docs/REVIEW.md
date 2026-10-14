# Review checklist — pass all five before any change ships

1. **Plain words.** Could a non-technical friend follow the README
   diff with no help? No jargon without an explanation next to it.
2. **Off by default.** New behavior ships opt-in. Nothing auto-tears
   down audio, nothing phones home, nothing surprises.
3. **Proven, not claimed.** `bash tests/run.sh` green, and anything
   touching hardware also verified live (`maid-watcher status`,
   real switch, real call) before commit.
4. **Docs match code.** README, CHANGELOG, and AGENTS.md updated in
   the same commit as the behavior. No personal data (MACs, names,
   IPs, home paths) — the suite enforces this.
5. **Uninstall story intact.** `install.sh --uninstall` still removes
   everything added, settings asked about, `--purge` total.
