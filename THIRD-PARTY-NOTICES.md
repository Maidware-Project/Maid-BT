# third-party and credits

Everything in Maid BT is Maidware work under the **GPL-3.0-or-later** license in `LICENSE`. None of the items below
is bundled: Maid BT either references knowledge, or calls other programs your distribution already
has. This file names them, so nobody has to dig through sources to find who deserves the credit.

## Referenced for knowledge

- OpenSCQ30 (https://github.com/Oppzippy/OpenSCQ30), GPL-3.0. It reverse-engineered and documented
  the Soundcore vendor protocol. `bin/maid-soundcore` and `watcher/maid_core/soundcore.py` are a
  clean-room port of that protocol: only wire facts (marker bytes, command ids, field layouts) were
  used as the reference. No OpenSCQ30 code was copied or translated. The credit also shows where
  users can see it: `bin/maid-soundcore`, `watcher/maid_core/soundcore.py`, and the settings window
  in the plasma applet. `docs/DEVICE-SUPPORT.md` is generated from our own model database
  (`watcher/maid_core/models.py`), not from their documentation.

## Called at runtime, not bundled

These must exist on your system; your distribution ships them, Maid BT only runs them:

- bluetoothctl (BlueZ, GPL-2.0-or-later): pair, trust, connect, list devices.
- pactl (PulseAudio): move default sinks and show stream state. libpulse is LGPL-2.1-or-later;
  PulseAudio's command line tools are GPL-2.0-or-later.
- rfkill (util-linux, GPL-2.0): the soft block Maid BT lifts and sets for on/off.
- WirePlumber (MIT): the files in `wireplumber/` are small directives written for the system's own
  WirePlumber. Nothing from WirePlumber itself is copied.

## Used while building, not shipped

- nfpm (https://nfpm.goreleaser.com), MIT: `packaging/packages.sh` builds the deb and rpm packages
  with it. nfpm is not part of those packages.

## Optional integrations

- MacroDroid and Tasker (Android, commercial, their own licenses):
  `phone/README-macrodroid-tasker.md` shows how to start Maid BT from them. Nothing from either
  ships in Maid BT, nothing of Maid BT ships to the phone.

Everything else in this repository is original Maidware work. Corrections welcome
(see CONTRIBUTING.md); if a credit is missing or wrong, open an issue or pull request.
