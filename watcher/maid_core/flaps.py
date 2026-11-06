"""A device being passed back and forth between the phone and this PC.

A charging phone wakes up and claims the buds, this PC reconnects, the
phone claims them again... Each hop alone is one unlucky drop; a whole
burst of them is a tug-of-war, and answering every hop with a profile
switch and a stream move is what the user hears as a sudden switch. So
the watcher counts the hops: once they add up to a storm it stands down
- no reconnect race, no profile switch, no routing - and the audio
moves wait for audible sound instead of the next charge event.
"""
from collections import deque

WINDOW_S = 120.0        # hops within this much time add up to one storm
LIMIT = 3               # this many recent hops = a tug-of-war
CALM_S = 600.0          # how long the watcher stands down after noticing
HOLD_S = 600.0          # a link held this long makes the history irrelevant


class FlapWatch:
    "Per device: when it dropped, whether that adds up to a storm, and when to stand back up."

    def __init__(self):
        self._downs = {}      # mac -> deque[epoch seconds of each disconnect]
        self._until = {}      # mac -> epoch the current stand-down ends

    def note_down(self, mac, now):
        "Another drop. Entries that no caller can care about anymore leave."
        q = self._downs.setdefault(mac, deque())
        q.append(now)
        while q and q[0] < now - HOLD_S:
            q.popleft()

    def last_down(self, mac, now):
        "Epoch of the most recent drop, or None."
        q = self._downs.get(mac)
        return q[-1] if q else None

    def hot(self, mac, now):
        """True while a storm is being counted or the stand-down still runs.
        Only drops inside the window count; an old burst never keeps a
        device hot once its calm is over."""
        if now < self._until.get(mac, 0.0):
            return True
        q = self._downs.get(mac)
        if not q:
            return False
        recent = 0
        for when in q:
            if when >= now - WINDOW_S:
                recent += 1
        return recent >= LIMIT

    def stand_down(self, mac, now):
        """Arm the calm if it is not already armed. True only for the first
        arming of a storm, so the notice goes out once, not on every hop."""
        if now < self._until.get(mac, 0.0):
            return False
        self._until[mac] = now + CALM_S
        return True

    def settled(self, mac, now):
        """True once, when a device has been quiet for HOLD_S: its whole
        history stops mattering and this forgets it."""
        q = self._downs.get(mac)
        if not q:
            return False
        if now - q[-1] >= HOLD_S:
            self._downs.pop(mac, None)
            self._until.pop(mac, None)
            return True
        return False

    def forget(self, mac):
        "A device removed from the config leaves everything behind at once."
        self._downs.pop(mac, None)
        self._until.pop(mac, None)
