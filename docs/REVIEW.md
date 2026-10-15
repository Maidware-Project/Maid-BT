# before it goes in

five things to check before a change lands.

1. plain words. could a non-technical friend follow the README diff with
   no help? no jargon without an explanation next to it.
2. off by default. new behavior ships opt-in. nothing auto-tears down
   audio, nothing phones home, nothing surprises.
3. proven, not claimed. `bash tests/run.sh` green, and anything touching
   hardware also verified live (`maid-watcher status`, real switch, real
   call) before commit.
4. docs match code. README, CHANGELOG and AGENTS.md updated in the same
   commit as the behavior. no personal data (MACs, names, IPs, home
   paths) - the suite enforces this.
5. uninstall story intact. `install.sh --uninstall` still removes
   everything it added, settings are asked about, `--purge` is total.
