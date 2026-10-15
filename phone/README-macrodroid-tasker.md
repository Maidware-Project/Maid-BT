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
| testing | `/health` | returns `ok` |

send the token as an `X-Token` header. `?token=` still works but rides
in the URL, so prefer the header.

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

## notes

token rides plain HTTP on your own LAN - fine at home, never expose
8899 past your router. phone stuff is off by default at install; core
switching never touches the network.
