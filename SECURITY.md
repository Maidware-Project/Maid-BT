# security

Maid BT switches bluetooth audio around. how it is kept safe:

- the phone-facing listener is a local socket, gated by a token in
  `~/.config/bt-intent.token` and checked with a constant-time compare. the
  token is never written to the log, and the socket has a per-connection
  timeout so a trickled request cannot hold a thread open.
- new behavior ships off. nothing auto-tears down an audio link on its own.
- no downloads, no telemetry, nothing phones home; external commands use
  argv lists, never a shell string.

to report a problem, open an issue on the repository.
