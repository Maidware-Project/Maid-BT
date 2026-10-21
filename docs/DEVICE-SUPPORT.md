# Device support

## What "native Linux support" means

Maid BT never installs codecs, drivers, or vendor daemons. Everything
below ships in stock BlueZ + PipeWire; the suite only orchestrates
profiles, defaults, and reconnect policy on top. So a device either
works natively (its profile appears in your audio settings) or it has a
model-specific caveat - there is no Maid BT layer to fail.

| Capability | Ships with | Status on a modern distro |
|---|---|---|
| A2DP SBC (all streaming quality) | BlueZ + PipeWire | universal - every BT audio device |
| SBC-XQ (better SBC bitrate) | PipeWire | opt-in: Maid BT ships 52-bt-max-quality.conf |
| AAC | PipeWire encoder | works on devices that accept it (iPhone-grade quality) |
| aptX, aptX HD, aptX Adaptive | PipeWire | codecs listed per model below |
| LDAC | PipeWire (libldac) | on LDAC-labeled models below; Maid BT pins it with QUALITY_LOCK=1 |
| HFP / HSP (mic) | BlueZ + PipeWire | works; Maid BT routes chat-app mics off it (route-mic) |
| LE Audio (Auracast/ISO) | experimental | PipeWire supports it, most BT adapters lack ISO - Buds can go silent; Maid BT ships 53-bt-a2dp-only.conf as the guard |
| AVRCP battery | BlueZ Battery1 | Maid-watcher shows it; depth varies by vendor |

Also native, though not codec work:

- **Charging-case awareness** (`case_detect`): buds in a closed case
  power off and go silent; maid-watcher probes for that instead of
  retrying blindly.
- **Multipoint** (phone + PC linked at once): supported by the *device*
  itself; Maid BT lengthens hands-off windows (`MULTIPOINT=1`) so the
  two devices stop fighting over them.

## Known models and their quirks

Any earbuds/headset not listed here still gets full generic A2DP
support - the database only adds per-model knowledge (codec ladder,
multipoint, LE-Audio caveats, case behavior). Check any single device:

    maid-watcher model "Sony WF-1000XM5"

The database currently covers 304 known models across 38 brands:

| Brand | Default quirks | Models |
|---|---|---|
| 1more | multipoint, ldac, aac, charging-case | ComfoBuds 2, ColorBuds 2, EVO, Aero, PistonBuds Pro Q30, Fit SE Open Earbuds S30 |
| akg | multipoint, aptx, charging-case | N5 |
| apple | ecosystem, aac, charging-case | AirPods, AirPods Pro, AirPods Max |
| audio-technica | multipoint, ldac, aac, charging-case | ATH-TWX7, ATH-TWX9, ATH-TWX9MK2, ATH-CKS50TW, ATH-CKS50TW2 |
| baseus | multipoint, aptx, aac, charging-case | Bowie M2s, Bowie 30, Bowie 35, Bowie E17, Bowie E18, Bowie E19, Bowie E19s, Bowie WM02s, Bowie WX5, Bowie MC1, Bowie MC2, Bowie MC2 S, Bowie MC2 Air, Bowie MC2 Open, Bass BP1, Bass BC1, Bass BC2, Bass BF1, Bass EP10, AirNora 2, Inspire XC1 |
| beats | ecosystem, aac, charging-case | Studio Buds, Fit Pro, Powerbeats Pro, Powerbeats Fit |
| belkin | multipoint, aac, charging-case | SoundForm Pulse |
| bose | multipoint, aac, charging-case | QuietComfort Earbuds II, QuietComfort Ultra Earbuds, Ultra Open Earbuds, QuietComfort Earbuds |
| cambridge audio | multipoint, ldac, charging-case | Melomania A100 |
| cleer | multipoint, ldac, charging-case | ARC 3 |
| cmf | multipoint, aac, charging-case | Buds Pro 2, Buds 2 Plus, Buds |
| devialet | multipoint, aptx, charging-case | Gemini II |
| earfun | multipoint, aac, aptx, charging-case | Air Pro 3, Air Pro 4, Air Pro 4i, Air Pro 4+, Air 2, Air 2 NC, Clip , Clip 2, OpenJump |
| edifier | multipoint, ldac, aac, charging-case | W240TN, W220T, W260NC, W320TN, NeoBuds Pro 3, NeoBuds Planar, STAX Spirit S10, X2 Pro, X2 Plus, X3 Pro, X5 Pro, TWS1 Pro 2, JoyBuds, TO-U6+, TO-U7 Pro |
| honor | multipoint, aac, charging-case | Earbuds 3 Pro, Earbuds X5, Earbuds 4, Earbuds Open, CHOICE Earbuds Clip 2 Pro |
| huawei | multipoint, ldac, aac, charging-case, le-audio-dual | FreeBuds 3, FreeBuds 4, FreeBuds 4i, FreeBuds 5, FreeBuds 5i, FreeBuds 6, FreeBuds 6i, FreeBuds Pro, FreeBuds Pro 2, FreeBuds Pro 3, FreeBuds Pro 4 |
| jabra | multipoint, aptx, aac, charging-case | Elite 3, Elite 4, Elite 5, Elite 7 Pro, Elite 7 Active, Elite 8 Active, Elite 8 Active Gen 2, Elite 10, Elite 10 Gen 2, Elite 85t, Evolve2 Buds |
| jbl | multipoint, aac, aptx, charging-case | Live Pro 2, Live Free 2, Live Flex 3, Live Buds 3, Live Beam 3, Live Beam 4, Tour Pro 2, Tour Pro 3, Tune Buds, Tune Beam 2, Endurance Race 2, Soundgear Sense |
| jlab | multipoint, aac, charging-case | JBuds Air Pro, JBuds ANC, JBuds Mini, JBuds Pods ANC, Go Pop ANC, Work Buds, Epic Lab Edition, Epic Sport ANC 3, JBuds Sport ANC 4 |
| noble audio | multipoint, aptx, charging-case | Osprey |
| nothing | multipoint, aac, charging-case | Ear (1), Ear (2), Ear , Ear (a), Ear (open), CMF Buds Pro 2, CMF Buds |
| oneplus | multipoint, aac, aptx, charging-case | OnePlus Buds Pro, OnePlus Buds Pro 2, OnePlus Buds Pro 3, OnePlus Buds 3, OnePlus Buds 4, Nord Buds 2, Nord Buds 3, Nord Buds 3 Pro, Nord Buds 4 Pro |
| oppo | multipoint, aac, charging-case | Enco X, Enco X2, Enco X3, Enco X3s, Enco Air4, Enco Air4 Pro, Enco Air5, Enco Air5s, Enco Air5 Pro, Enco Clip2 |
| qcy | multipoint, aac, charging-case | MeloBuds Pro, MeloBuds Neo, MeloBuds A30, MeloBuds N20, MeloBuds N30, MeloBuds N50, MeloBuds N60, MeloBuds N70, T13, T13 Pro, Crossky C30, Crossky C30S, Crossky C50, Crossky Link, Crossky GTR2, AilyBuds Pro+, AilyBuds Clear |
| realme | multipoint, aac, charging-case | Buds Air 3, Buds Air 5 Pro, Buds Air 8, Buds Air 8 Pro, Buds N1, Buds T310, Buds T500 Pro, Buds T500 |
| redmi | multipoint, aac, charging-case | Redmi Buds 3 Pro, Redmi Buds 4 Pro, Redmi Buds 5, Redmi Buds 5 Pro, Redmi Buds 6, Redmi Buds 6 Pro, Redmi Buds 6 Lite, Redmi Buds 6 Active, Redmi Buds 8 Lite |
| samsung | ecosystem, aac, charging-case | Galaxy Buds2 Pro, Galaxy Buds3, Galaxy Buds3 Pro, Galaxy Buds4, Galaxy Buds4 Pro |
| sennheiser | multipoint, ldac, aac, charging-case | MOMENTUM True Wireless 3, MOMENTUM True Wireless 4, MOMENTUM True Wireless 5, MOMENTUM Sport, MOMENTUM 4, ACCENTUM True Wireless, CX True Wireless, CX Plus True Wireless |
| shokz | multipoint, aac, charging-case | OpenFit, OpenFit Air, OpenFit 2 |
| skullcandy | multipoint, aac, charging-case | Rail, Grind, Grind Fuel, Push Active, Push Play Active, Push ANC Active, Sesh ANC Active, Dime 3, Dime Evo, Indy ANC |
| sony | multipoint, ldac, aac, charging-case, le-audio-dual | WF-C510, WF-C710N, WF-1000XM4, WF-1000XM5, WF-1000XM6, LinkBuds S, LinkBuds Fit, LinkBuds Open, LinkBuds Clip |
| soundcore | multipoint, ldac, aac, charging-case, device-control | Liberty 3 Pro, Liberty 4, Liberty 4 NC, Liberty 5, Liberty 5 Pro, Liberty 5 Pro Max, Liberty Buds 2, Space A40, P40i, Sport X20, V20i, AeroFit, AeroFit Pro, AeroFit 2, AeroClip, C30i, C40i, Q11i, Q20i, Q30, Life Q35, Life Tune, Life Tune Pro, Vortex, Life 2 Neo, Space One, Space Q45, Space One Pro, Motion+, Life Dot 2S, Life Dot 2 NC, Life Note 3, Life Note 3S, Life A2 NC, Life P3, Life P2 Mini, A20i, P20i, R50i, Liberty Air 2 Pro, P30i, C50i, P31i, R60i NC, Sleep A30 |
| soundpeats | multipoint, aac, charging-case | Air4, Air4 Lite, Air4 Pro, Air5, Air5 Pro, Air5 Pro+, Air6 HS, Capsule3 Pro+, H2, H3, Opera 05, Engine4, C30, PearlClip Pro |
| sudio | multipoint, aac, charging-case | A3, Nio |
| technics | multipoint, ldac, aac, charging-case | EAH-AZ40M2, EAH-AZ60M2, EAH-AZ80, EAH-AZ100 |
| tozo | multipoint, aac, charging-case | Golden X1, Golden X2, NC20, NC20 Pro, OpenBuds, OpenEgo, OpenWear, O2 Open Buds |
| vivo | multipoint, ldac, aac, charging-case | TWS 3 Pro, TWS 3e, TWS 4, TWS 4 HiFi, TWS Air3 Pro, TWS Air Pro |
| xiaomi | multipoint, ldac, aac, charging-case | Xiaomi Buds 3, Xiaomi Buds 3T Pro, Xiaomi Buds 4 Pro, Xiaomi Buds 5, Xiaomi Buds 5 Pro, Xiaomi Buds 6 |


## Quirk notes

- **multipoint** - the buds keep phone and PC linked at once. Enable
  dual-connection in the brand app, then set `MULTIPOINT=1`.
- **ldac / aac / aptx** - the model's high-quality codec band; with
  `QUALITY_LOCK=1` Maid BT pins the best one after every switch.
- **le-audio-dual** - dual-mode LE buds may go silent on adapters
  without ISO support; the shipped 53-bt-a2dp-only.conf prevents it.
- **charging-case** - model ships a powered charging case, so docked
  buds go fully silent (case_detect handles this).
- **ecosystem** - switching lives only in the vendor app (Samsung Auto
  Switch, Apple/Beats ecosystem). Linux cannot control it; Maid BT
  manages the PC side of the dance instead.

---

<!-- generated by docs/gen-device-support.py from watcher/maid_core/models.py -->
<!-- regenerate with: python3 docs/gen-device-support.py -->
