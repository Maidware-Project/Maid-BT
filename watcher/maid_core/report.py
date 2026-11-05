"""Shared presentation for maid-watcher status: the same facts as text for the terminal, one json line for

here claims quality, lossless or anything else that Bluetooth output cannot honestly be."""

import json


def text(ct, laptop, rows):
    "The terminal layout exactly as it always printed (unchanged for people)."
    lines = [f"chassis:   {ct} (laptop mode {'on' if laptop else 'off'})"]
    for r in rows:
        lines.append(f"{r['name']} [{r['mac']}]")
        lines.append(f"  connected: {r['connected']}")
        lines.append(f"  profile:   {r['profile']}")
        lines.append(f"  mic held by: {r['mic_text']}")
        lines.append(f"  battery:   {r['battery']}%")
        if r["case"] is not None:
            lines.append(f"  case:      {r['case']}")
    if not rows:
        lines.append("no devices configured - copy config.example.json to "
                     "~/.config/maid-watcher/config.json")
    return "\n".join(lines)


def shape(ct, laptop, rows):
    "One json line. Belt: valid even with zero devices (an empty list, not a missing key)."
    return json.dumps({
        "chassis": ct,
        "laptop_mode": bool(laptop),
        "devices": [{
            "name": r["name"],
            "mac": r["mac"],
            "connected": bool(r["connected"]),
            "profile": r["profile"],
            "mic_holders": list(r.get("holders") or []),
            "battery": r["battery"],
            "case": r["case"],
        } for r in rows],
    })
