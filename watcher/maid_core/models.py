"""Known earbuds/headsets database: per-model quirks for Maid Watcher.

The suite is device-agnostic at heart (Macs, profiles, batteries are all
MAC-driven). What IS model-specific: whether the buds do real Bluetooth
multipoint (phone+PC stay linked, so hands-off windows must be long),
the codec ladder the model can actually deliver (ldac/aac/aptx...),
LE-Audio dual-mode quirks (silent buds on adapters without ISO), how the
model docks (charging case vs pocket/power-off), and ecosystem-only
switching that Linux cannot control (Samsung Auto Switch, Apple).

lookup() matches a Bluetooth alias/name case-insensitively on brand and
model fragments; the longest alias wins. Unknown devices get the safe
generic profile: neither multipoint, LDAC-less ladder (skip), generic
case behavior - everything degrades gracefully and never breaks a
connect. Forks: append to BRAND_MODELS (one line per model), never
hard-code logic on names.
"""
import re

# brand: (default quirks, [model name fragments])
# quirks: m=multipoint, le=LE-Audio dual-mode quirk, l=ldac, a=aac,
#         x=aptX family, c=charging case, e=ecosystem-only switching,
#         s=vendor device-control (Soundcore RFCOMM protocol; see
#         maid_core/soundcore.py - protocol facts derived from the
#         GPL OpenSCQ30 project, implemented fresh here, MIT-licensed)
BRAND_MODELS = {
    "soundcore": ("m l a c s", [
        "Liberty 3 Pro", "Liberty 4", "Liberty 4 NC", "Liberty 5",
        "Liberty 5 Pro", "Liberty 5 Pro Max", "Liberty Buds 2",
        "Space A40", "P40i", "Sport X20", "V20i", "AeroFit",
        "AeroFit Pro", "AeroFit 2", "AeroClip", "C30i", "C40i",
        # headphones and remaining supported family: vendor control
        # codes live in DEVICE_CODES below
        "Q11i", "Q20i", "Q30", "Life Q35", "Life Tune", "Life Tune Pro",
        "Vortex", "Life 2 Neo", "Space One", "Space Q45",
        "Space One Pro", "Motion+", "Life Dot 2S", "Life Dot 2 NC",
        "Life Note 3", "Life Note 3S", "Life A2 NC", "Life P3",
        "Life P2 Mini", "A20i", "P20i", "R50i", "Liberty Air 2 Pro",
        "P30i", "C50i", "P31i", "R60i NC", "Sleep A30",
    ]),
    "sony": ("m l a c le", [
        "WF-C510", "WF-C710N", "WF-1000XM4", "WF-1000XM5", "WF-1000XM6",
        "LinkBuds S", "LinkBuds Fit", "LinkBuds Open", "LinkBuds Clip",
    ]),
    "jbl": ("m a x c", [
        "Live Pro 2", "Live Free 2", "Live Flex 3", "Live Buds 3",
        "Live Beam 3", "Live Beam 4", "Tour Pro 2", "Tour Pro 3",
        "Tune Buds", "Tune Beam 2", "Endurance Race 2", "Soundgear Sense",
    ]),
    "samsung": ("e a c", [
        "Galaxy Buds2 Pro", "Galaxy Buds3", "Galaxy Buds3 Pro",
        "Galaxy Buds4", "Galaxy Buds4 Pro",
    ]),
    "bose": ("m a c", [
        "QuietComfort Earbuds II", "QuietComfort Ultra Earbuds",
        "Ultra Open Earbuds", "QuietComfort Earbuds",
    ]),
    "sennheiser": ("m l a c", [
        "MOMENTUM True Wireless 3", "MOMENTUM True Wireless 4",
        "MOMENTUM True Wireless 5", "MOMENTUM Sport", "MOMENTUM 4",
        "ACCENTUM True Wireless", "CX True Wireless",
        "CX Plus True Wireless",
    ]),
    "technics": ("m l a c", [
        "EAH-AZ40M2", "EAH-AZ60M2", "EAH-AZ80", "EAH-AZ100",
    ]),
    "jabra": ("m x a c", [
        "Elite 3", "Elite 4", "Elite 5", "Elite 7 Pro", "Elite 7 Active",
        "Elite 8 Active", "Elite 8 Active Gen 2", "Elite 10",
        "Elite 10 Gen 2", "Elite 85t", "Evolve2 Buds",
    ]),
    "nothing": ("m a c", ["Ear (1)", "Ear (2)", "Ear ", "Ear (a)",
                          "Ear (open)", "CMF Buds Pro 2", "CMF Buds"]),
    "cmf": ("m a c", ["Buds Pro 2", "Buds 2 Plus", "Buds"]),
    "huawei": ("m l a c le", [
        "FreeBuds 3", "FreeBuds 4", "FreeBuds 4i", "FreeBuds 5",
        "FreeBuds 5i", "FreeBuds 6", "FreeBuds 6i", "FreeBuds Pro",
        "FreeBuds Pro 2", "FreeBuds Pro 3", "FreeBuds Pro 4",
    ]),
    "oneplus": ("m a x c", [
        "OnePlus Buds Pro", "OnePlus Buds Pro 2", "OnePlus Buds Pro 3",
        "OnePlus Buds 3", "OnePlus Buds 4", "Nord Buds 2",
        "Nord Buds 3", "Nord Buds 3 Pro", "Nord Buds 4 Pro",
    ]),
    "oppo": ("m a c", [
        "Enco X", "Enco X2", "Enco X3", "Enco X3s", "Enco Air4",
        "Enco Air4 Pro", "Enco Air5", "Enco Air5s", "Enco Air5 Pro",
        "Enco Clip2",
    ]),
    "xiaomi": ("m l a c", [
        "Xiaomi Buds 3", "Xiaomi Buds 3T Pro", "Xiaomi Buds 4 Pro",
        "Xiaomi Buds 5", "Xiaomi Buds 5 Pro", "Xiaomi Buds 6",
    ]),
    "redmi": ("m a c", [
        "Redmi Buds 3 Pro", "Redmi Buds 4 Pro", "Redmi Buds 5",
        "Redmi Buds 5 Pro", "Redmi Buds 6", "Redmi Buds 6 Pro",
        "Redmi Buds 6 Lite", "Redmi Buds 6 Active", "Redmi Buds 8 Lite",
    ]),
    "earfun": ("m a x c", [
        "Air Pro 3", "Air Pro 4", "Air Pro 4i", "Air Pro 4+",
        "Air 2", "Air 2 NC", "Clip ", "Clip 2", "OpenJump",
    ]),
    "soundpeats": ("m a c", [
        "Air4", "Air4 Lite", "Air4 Pro", "Air5", "Air5 Pro", "Air5 Pro+",
        "Air6 HS", "Capsule3 Pro+", "H2", "H3", "Opera 05", "Engine4",
        "C30", "PearlClip Pro",
    ]),
    "edifier": ("m l a c", [
        "W240TN", "W220T", "W260NC", "W320TN", "NeoBuds Pro 3",
        "NeoBuds Planar", "STAX Spirit S10", "X2 Pro", "X2 Plus",
        "X3 Pro", "X5 Pro", "TWS1 Pro 2", "JoyBuds", "TO-U6+", "TO-U7 Pro",
    ]),
    "qcy": ("m a c", [
        "MeloBuds Pro", "MeloBuds Neo", "MeloBuds A30", "MeloBuds N20",
        "MeloBuds N30", "MeloBuds N50", "MeloBuds N60", "MeloBuds N70",
        "T13", "T13 Pro", "Crossky C30", "Crossky C30S", "Crossky C50",
        "Crossky Link", "Crossky GTR2", "AilyBuds Pro+",
        "AilyBuds Clear",
    ]),
    "baseus": ("m x a c", [
        "Bowie M2s", "Bowie 30", "Bowie 35", "Bowie E17", "Bowie E18",
        "Bowie E19", "Bowie E19s", "Bowie WM02s", "Bowie WX5",
        "Bowie MC1", "Bowie MC2", "Bowie MC2 S", "Bowie MC2 Air",
        "Bowie MC2 Open", "Bass BP1", "Bass BC1", "Bass BC2",
        "Bass BF1", "Bass EP10", "AirNora 2", "Inspire XC1",
    ]),
    "1more": ("m l a c", [
        "ComfoBuds 2", "ColorBuds 2", "EVO", "Aero",
        "PistonBuds Pro Q30", "Fit SE Open Earbuds S30",
    ]),
    "jlab": ("m a c", [
        "JBuds Air Pro", "JBuds ANC", "JBuds Mini", "JBuds Pods ANC",
        "Go Pop ANC", "Work Buds", "Epic Lab Edition",
        "Epic Sport ANC 3", "JBuds Sport ANC 4",
    ]),
    "skullcandy": ("m a c", [
        "Rail", "Grind", "Grind Fuel", "Push Active", "Push Play Active",
        "Push ANC Active", "Sesh ANC Active", "Dime 3", "Dime Evo",
        "Indy ANC",
    ]),
    "audio-technica": ("m l a c", [
        "ATH-TWX7", "ATH-TWX9", "ATH-TWX9MK2", "ATH-CKS50TW",
        "ATH-CKS50TW2",
    ]),
    "shokz": ("m a c", ["OpenFit", "OpenFit Air", "OpenFit 2"]),
    "tozo": ("m a c", [
        "Golden X1", "Golden X2", "NC20", "NC20 Pro", "OpenBuds",
        "OpenEgo", "OpenWear", "O2 Open Buds",
    ]),
    "honor": ("m a c", [
        "Earbuds 3 Pro", "Earbuds X5", "Earbuds 4", "Earbuds Open",
        "CHOICE Earbuds Clip 2 Pro",
    ]),
    "realme": ("m a c", [
        "Buds Air 3", "Buds Air 5 Pro", "Buds Air 8", "Buds Air 8 Pro",
        "Buds N1", "Buds T310", "Buds T500 Pro", "Buds T500",
    ]),
    "vivo": ("m l a c", [
        "TWS 3 Pro", "TWS 3e", "TWS 4", "TWS 4 HiFi", "TWS Air3 Pro",
        "TWS Air Pro",
    ]),
    "beats": ("e a c", [
        "Studio Buds", "Fit Pro", "Powerbeats Pro", "Powerbeats Fit",
    ]),
    "apple": ("e a c", ["AirPods", "AirPods Pro", "AirPods Max"]),
    "cambridge audio": ("m l c", ["Melomania A100"]),
    "cleer": ("m l c", ["ARC 3"]),
    "noble audio": ("m x c", ["Osprey"]),
    "akg": ("m x c", ["N5"]),
    "devialet": ("m x c", ["Gemini II"]),
    "belkin": ("m a c", ["SoundForm Pulse"]),
    "sudio": ("m a c", ["A3", "Nio"]),
}

QFLAG = {"m": "multipoint", "le": "le-audio-dual", "l": "ldac",
         "a": "aac", "x": "aptx", "c": "charging-case", "e": "ecosystem",
         "s": "device-control"}

# Vendor device-control capability (Soundcore RFCOMM vendor protocol):
# model alias -> vendor model code. "Liberty 5" style names resolve
# here after the plain brand lookup so controls can be offered from the
# GUI. Codes verified against the OpenSCQ30 supported-device table; the
# protocol implementation itself is our own (see maid_core/soundcore.py).
DEVICE_CODES = {
    "Q11i": "A3005", "Q20i": "A3004", "Life Q35": "A3027",
    "Q30": "A3028", "Life Tune": "A3029", "Life Tune Pro": "A3030",
    "Vortex": "A3031", "Life 2 Neo": "A3033", "Space One": "A3035",
    "Space Q45": "A3040", "Space One Pro": "A3062",
    "Motion+": "A3116", "C30i": "A3330", "AeroClip": "A3388",
    "V20i": "A3876", "Liberty 2 Pro": "A3909", "Life Dot 2S": "A3926",
    "Liberty 2 Pro+": "A3930", "Life Dot 2 NC": "A3931",
    "Life Note 3": "A3933", "Life A2 NC": "A3935",
    "Space A40": "A3936", "Life P3": "A3939", "Life P2 Mini": "A3944",
    "Liberty 4 NC": "A3947", "A20i": "A3948", "P20i": "A3949",
    "Liberty Air 2 Pro": "A3951", "Liberty 3 Pro": "A3952",
    "Liberty 4": "A3953", "P40i": "A3955", "Liberty 5": "A3957",
    "P30i": "A3959", "Sport X20": "A3968", "C50i": "D1101",
    "P31i": "D1202", "R60i NC": "D1202C", "Sleep A30": "D1301",
}

# compiled once: alias -> (brand, quirks)
_ALIASES = None


def _build():
    global _ALIASES
    if _ALIASES is not None:
        return _ALIASES
    table = {}
    for brand, (flags, models) in BRAND_MODELS.items():
        quirks = set()
        for f in flags.split():
            if f in QFLAG:
                quirks.add(QFLAG[f])
        for model in models:
            alias = (brand + " " + model).strip().lower()
            # squash variant spacing/punctuation: "ear (a)" ~ "ear a"
            key = re.sub(r"[^a-z0-9]+", " ", alias).strip()
            table[key] = (brand, model, frozenset(quirks))
    _ALIASES = table
    return _ALIASES


def lookup(name):
    """Match a Bluetooth alias against the database.

    Returns {"brand", "model", "quirks", "device"} (quirks = sorted
    tuple; device = vendor control code when known, else ""), never
    raises, never invents a device it did not match: unknowns get
    {"brand": None, "model": name, "quirks": (), "device": ""}.
    """
    table = _build()
    raw = re.sub(r"[^a-z0-9]+", " ", str(name or "").lower()).strip()
    if not raw:
        return {"brand": None, "model": "", "quirks": (), "device": ""}
    hit = table.get(raw)
    if hit:
        return _shaped(hit)
    # containment: "soundcore liberty 5 by anker" ~ "soundcore liberty 5"
    best, bestlen = None, 0
    for key, val in table.items():
        if key and key in raw and len(key) > bestlen:
            best, bestlen = val, len(key)
    if best:
        return _shaped(best)
    # bare-brand match ("soundcore v20i" contains brand at least)
    frag = raw.split(" ", 1)[0]
    for key, val in table.items():
        if key == frag:
            return _shaped(val)
    return {"brand": None, "model": name, "quirks": (), "device": ""}


def _shaped(hit):
    brand, model, quirks = hit
    return {"brand": brand, "model": model, "quirks": quirks,
            "device": DEVICE_CODES.get(model, "") if "device-control"
            in quirks else ""}
