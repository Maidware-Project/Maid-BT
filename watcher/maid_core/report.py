"""Shared presentation for maid-watcher status: the same facts as text for the terminal, one json line for

here claims quality, lossless or anything else that Bluetooth output cannot honestly be."""

import json


def text(ct, laptop, rows, bluev_caps=None):
    "The terminal layout (backward-compatible) with BlueV observability."
    lines = [f"chassis:   {ct} (laptop mode {'on' if laptop else 'off'})"]
    if bluev_caps:
        feats = [k for k, v in bluev_caps.items() if v is True]
        if feats:
            lines.append(f"  bluev features: {', '.join(feats)}")
    for r in rows:
        lines.append(f"{r['name']} [{r['mac']}]")
        lines.append(f"  connected: {r['connected']}")
        lines.append(f"  profile:   {r['profile']}")
        lines.append(f"  mic held by: {r['mic_text']}")
        lines.append(f"  battery:   {r['battery']}%")
        if r["case"] is not None:
            lines.append(f"  case:      {r['case']}")
        bluev = r.get("bluev")
        if bluev:
            state = bluev.get("state")
            reason = bluev.get("reason")
            if state:
                suffix = f" ({reason})" if reason else ""
                lines.append(f"  bluev:     {state}{suffix}")
            hint = bluev.get("phone_hint") or {}
            if hint:
                hstate = hint.get("_resolved_state") or hint.get("state")
                age = hint.get("_age_s")
                src = hint.get("source")
                extra = []
                if src:
                    extra.append(f"src={src}")
                if age is not None:
                    try:
                        extra.append(f"age={int(age)}s")
                    except Exception:
                        pass
                if hint.get("confidence") is not None:
                    extra.append(f"conf={hint.get('confidence')}")
                tail = f" [{', '.join(extra)}]" if extra else ""
                lines.append(f"  phone hint:{(' ' + hstate) if hstate else ''}{tail}")
            dsc = bluev.get("docked_silent_count")
            if dsc:
                lines.append(f"  dock probes: {dsc} silent")
    if not rows:
        lines.append("no devices configured - copy config.example.json to "
                     "~/.config/maid-watcher/config.json")
    return "\n".join(lines)


def shape(ct, laptop, rows, bluev_caps=None):
    "One json line. Belt: valid even with zero devices (an empty list, not a missing key)."
    payload = {
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
            **({"bluev": r.get("bluev")} if r.get("bluev") is not None else {}),
        } for r in rows],
    }
    if bluev_caps is not None:
        payload["bluev_capabilities"] = bluev_caps
    return json.dumps(payload)
