# phone remote: flip the buds without touching the PC

two ways, mix however you want.

## buttons (manual)

PC side, KDE Connect Settings → Run commands (they run on the PC):

| Name | Command |
|---|---|
| PC only | `~/.local/bin/bluetooth-toggle.sh on` |
| Phone only | `~/.local/bin/bluetooth-toggle.sh release` |
| Radio only | `~/.local/bin/bluetooth-toggle.sh radio` |
| Bluetooth Off | `~/.local/bin/bluetooth-toggle.sh off` |

phone side: open the device → Run commands. for home-screen one-tap
buttons: long-press home → Widgets → KDE Connect → Run command → pick
device + command. PC pings the phone on every switch so both ends agree.

## intent push (automatic)

phone tells the PC what's playing over LAN. needs: PC on a stable
address (DHCP reservation), TCP **8899** open on the PC firewall, token
from `~/.config/bt-intent.token`. base: `http://PC_IP:8899`.

| phone does | GET this | PC does |
|---|---|---|
| music starts (on the buds) | `/phone_playing` | parks audio, hands off 4h |
| music stops | `/phone_paused` | hands-off cleared, PC may grab back |
| call starts | `/call_start` | parks audio, hands off 2h |
| call ends | `/call_end` | hands-off cleared |
| buds connected/disconnected on phone (BlueV hint) | `/phone_device?mac=AA:BB:CC:DD:EE:FF&state=connected` (or `disconnected`) | stores per-device phone-connection hint for Maid Watcher BlueV policy |
| testing | `/health` | returns `ok` |

send the token as an `X-Token` header. `?token=` still works but rides
in the URL, so prefer the header.

### BlueV phone hints (per-device, WIP groundwork)

Maid Watcher can use phone-reported per-device connection hints to avoid
racing reconnects when the buds are currently owned by the phone and to
improve dock/availability confidence.

- Endpoint: `GET /phone_device?token=...&mac=AA:BB:CC:DD:EE:FF&state=connected|disconnected`
  - `mac`: the earbuds' Bluetooth MAC address (same one managed by Maid BT)
  - `state`: `connected` when the phone is connected to that device, `disconnected` when it is not
- Hints are stored in `/run/user/<uid>/maid-bluev-phone.json` and consumed by Maid Watcher (TTL/configurable via `bluev.phone_hint_ttl_s`).
- **Automatic reporting (recommended):** in MacroDroid/Tasker/OpenTasker, add triggers for Bluetooth connected/disconnected to the specific earbuds MAC/name and call `/phone_device` with the matching `mac` and `state`. This works over the existing intent server path and does not require a custom Android app.
- **KDE Connect-assisted/manual:** you can also expose PC-side "Run Command" actions in KDE Connect that hit the local intent server for a known MAC (e.g. via `curl -H "X-Token: $(cat ~/.config/bt-intent.token)" "http://127.0.0.1:8899/phone_device?mac=AA:BB:CC:DD:EE:FF&state=connected"`), useful for quick manual hints; automatic per-device state detection still needs an Android-side trigger/app.

MacroDroid (free fits, 4 macros): trigger `Music/Sound Playing`
(Playing/Stopped), `Call Active` (Any), `Call Ended`; constrain to
bluetooth connected to your buds; action `HTTP Request` GET the URLs.
battery Unrestricted or the OS kills it in the background. aggressive
battery killers are common, not just samsung: xiaomi/redmi/poco
(autostart + No restrictions), huawei/honor (manual app launch),
oneplus/oppo/realme (don't optimize + background activity on),
vivo/iqoo (autostart + background power). pixels/motorola/nothing are
usually fine stock. exact menus move every update - dontkillmyapps.com
has per-brand steps.

Tasker (paid, no ads): same thing with State `BT Connected` + Event
`UI → Notification` for media, State `Phone → Call` / Event `Phone Idle`
for calls. needs notification access + unrestricted battery (same
killers list as above: samsung, xiaomi, huawei, oneplus, oppo, vivo -
exempt the app or it dies in background).

OpenTasker (FOSS, on-device, no account): use an **HTTP Request** action
(GET) to the same endpoints. send the token as an `X-Token` header
(preferred); `?token=` still works but avoid it in URLs. example profiles:
- **phone playing:** media/audio playing context (or app/media trigger you
  trust) + BT connected to your buds → `GET /phone_playing`
- **phone paused:** inverse/exit of that context → `GET /phone_paused`
- **call start/end:** phone call state active / idle → `GET /call_start`,
  `GET /call_end`
- **BlueV hint:** BT connected/disconnected to the buds MAC → `GET
  /phone_device?mac=AA:BB:CC:DD:EE:FF&state=connected|disconnected`

OpenTasker runs locally with no cloud runtime; keep it battery-unrestricted
like the others so background triggers fire reliably.

## notes

token rides plain HTTP on your own LAN - fine at home, never expose
8899 past your router. phone stuff is off by default at install; core
switching never touches the network.

BlueV phone hints are currently PC-side groundwork: richer hint payloads (source/confidence/adapter context), multi-adapter support, deeper UI/observability, and vendor-specific enhancements are planned follow-ups.
