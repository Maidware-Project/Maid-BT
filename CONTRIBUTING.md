# contributing

small, reviewable changes only - one logical change per pull request.
keep a cleanup and a behavior change in separate patches. read AGENTS.md
first; it applies to humans and AI assistants alike. maintained by
Maidware Project.

## commits

- short lowercase summaries with a prefix: `fix:`, `feat:`, `docs:`,
  `tests:`, `chore:` - e.g. `fix: retry bluetooth connect with backoff`
- sign off every commit (`git commit -s` appends it):
  `Signed-off-by: Your Name <you@example.com>` - the developer's
  certificate of origin, your word that you may contribute it
- AI-assisted work gets an `Assisted-by:` trailer naming the tool, e.g.
  `Assisted-by: opencode (muse-spark)`. the kernel requires it; so do we.
  never claim a hardware check you didn't run.
- bug fixes name what they fix: `Fixes: #123` or `Closes: #123`

## before opening anything

- `bash tests/run.sh` green, output pasted in the pull request. it's
  hardware-free - every adapter and sink is stubbed - and covers the
  watcher extras, degraded mode, the hands-off rule, auto-switch, the
  quality lock, HSP rescue and multipoint release.
- anything that reaches real audio also needs a live check: `maid-watcher
  status`, a real switch, a real call. say which you did.
- `bash install.sh --check` writes nothing
- CI must be green before review - a green run on your machine is the
  start, not the finish
- no personal data anywhere (MACs, names, IPs, home paths). the suite
  greps for it, minus the desktop Exec path install.sh rewrites by design

## know your patch

understand every line you send, assistant-written ones included. if you
can't say what a line does, don't send it.

you need basic linux, and some patience for bluetooth. this repo moves
people's audio around, so "should work" doesn't get merged.

reviewers here are people, not bots: expect to answer questions about your
patch, and don't open one you can't back up. unattended drive-by or bot
PRs get closed.

## issues

use the bug report template and paste the diagnostics it asks for, minus
your MAC address if you're posting in public. "it doesn't work" with
nothing attached gets closed with a pointer back here.

behavior: CODE_OF_CONDUCT.md (technical scope only, no politics,
stay neutral).
