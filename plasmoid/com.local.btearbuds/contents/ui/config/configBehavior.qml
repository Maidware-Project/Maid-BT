import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

// Host-agnostic root: see configEQ.qml for why this is not KCM.SimpleKCM.
Kirigami.ScrollablePage {
    id: page


    property string configTool: "@HOME@/.local/bin/maid-bt-config"
    property var values: ({})
    property bool ready: false
    property bool applying: false
    property bool pending: false
    property string statusText: ""

    signal configurationChanged

    function load() {
        if (applying)
            return;
        statusText = "Loading…";
        execSource.connectSource(configTool + " get");
    }

    function populate() {
        ready = false;
        initialDelay.value = Number(values.initial_delay_s || 5);
        maxDelay.value = Number(values.max_delay_s || 120);
        giveUp.value = Number(values.give_up_after || 10);
        cooldown.value = Number(values.op_cooldown_s || 10);
        adapterCycle.checked = values.adapter_cycle !== false;
        callsEnabled.checked = values.calls_enabled !== false;
        pauseMedia.checked = values.calls_pause_media !== false;
        muteDiscord.checked = values.calls_mute_discord !== false;
        maxCall.value = Number(values.max_call_mode_s || 300);
        warnPercent.value = Number(values.battery_warn_percent || 25);
        criticalPercent.value = Number(values.battery_critical_percent || 12);
        pollSeconds.value = Number(values.battery_poll_s || 120);
        saverEnabled.checked = values.saver_enabled === true;
        idleMinutes.value = Number(values.saver_idle_minutes || 30);
        laptopBox.currentIndex = values.laptop_mode === "on" ? 1 : (values.laptop_mode === "off" ? 2 : 0);
        fallbackGrab.checked = values.fallback_grab === true;
        routeComms.checked = values.route_comms !== false;
        btFallback.checked = values.bt_fallback === true;
        ready = true;
    }

    function payload() {
        return {
            "initial_delay_s": initialDelay.value,
            "max_delay_s": maxDelay.value,
            "give_up_after": giveUp.value,
            "op_cooldown_s": cooldown.value,
            "adapter_cycle": adapterCycle.checked,
            "calls_enabled": callsEnabled.checked,
            "calls_pause_media": pauseMedia.checked,
            "calls_mute_discord": muteDiscord.checked,
            "max_call_mode_s": maxCall.value,
            "battery_warn_percent": warnPercent.value,
            "battery_critical_percent": criticalPercent.value,
            "battery_poll_s": pollSeconds.value,
            "saver_enabled": saverEnabled.checked,
            "saver_idle_minutes": idleMinutes.value,
            "laptop_mode": laptopBox.currentIndex === 1 ? "on" : (laptopBox.currentIndex === 2 ? "off" : "auto"),
            "fallback_grab": fallbackGrab.checked,
            "route_comms": routeComms.checked,
            "bt_fallback": btFallback.checked
        };
    }

    function apply() {
        if (!ready)
            return;
        if (applying) {
            pending = true;
            return;
        }
        applying = true;
        pending = false;
        statusText = "Saving…";
        const encoded = encodeURIComponent(JSON.stringify(payload())).replace(/'/g, "%27");
        execSource.connectSource(configTool + " apply " + encoded);
    }

    function saveConfig() {
        apply();
    }

    function changed() {
        if (!ready)
            return;
        configurationChanged();
        apply();
    }

    function statusColor() {
        if (statusText === "Saved.")
            return Kirigami.Theme.positiveTextColor;
        if (statusText === "Loading…" || statusText === "Saving…")
            return Kirigami.Theme.textColor;
        return Kirigami.Theme.negativeTextColor;
    }

    Component.onCompleted: load()

    P5Support.DataSource {
        id: execSource

        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            const out = String(data["stdout"] || "").trim();
            const err = String(data["stderr"] || "").trim();
            if (sourceName.indexOf(" get") !== -1) {
                if (out.charAt(0) === "{") {
                    try {
                        page.values = JSON.parse(out);
                        page.populate();
                        page.statusText = "";
                    } catch (e) {
                        page.statusText = "Could not read the Maid BT settings.";
                    }
                } else {
                    page.statusText = err || "maid-bt-config not found - reinstall Maid BT.";
                }
            } else if (sourceName.indexOf(" apply") !== -1) {
                page.applying = false;
                if (out === "ok") {
                    page.statusText = "Saved.";
                } else {
                    page.statusText = err || out || "Could not save the Maid BT settings.";
                }
                if (page.pending)
                    page.apply();
            }
            execSource.disconnectSource(sourceName);
        }
    }

    Kirigami.FormLayout {
        // bind to the page root so the form fills the pane instead of
        // being centered as a floating column (see configEQ.qml)
        width: page.width
        QQC2.Label {
            text: "Reconnects"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        QQC2.SpinBox {
            id: initialDelay
            Kirigami.FormData.label: "First retry after (seconds):"
            from: 1
            to: 600
            editable: true
            onValueModified: page.changed()
        }

        QQC2.SpinBox {
            id: maxDelay
            Kirigami.FormData.label: "Longest wait between retries (seconds):"
            from: 1
            to: 3600
            editable: true
            onValueModified: page.changed()
        }

        QQC2.SpinBox {
            id: giveUp
            Kirigami.FormData.label: "Give up after (tries):"
            from: 1
            to: 100
            editable: true
            onValueModified: page.changed()
        }

        QQC2.SpinBox {
            id: cooldown
            Kirigami.FormData.label: "Minimum time between Bluetooth operations (seconds):"
            from: 1
            to: 300
            editable: true
            onValueModified: page.changed()
        }

        QQC2.CheckBox {
            id: adapterCycle
            text: "Cycle the Bluetooth adapter once if the link is stuck"
            onToggled: page.changed()
        }

        QQC2.Label {
            text: "Calls"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: callsEnabled
            text: "Move the earbuds to the PC for calls"
            onToggled: page.changed()
        }

        QQC2.CheckBox {
            id: pauseMedia
            text: "Pause media while a call is active"
            onToggled: page.changed()
        }

        QQC2.CheckBox {
            id: muteDiscord
            text: "Mute Discord while a call is active"
            onToggled: page.changed()
        }

        QQC2.SpinBox {
            id: maxCall
            Kirigami.FormData.label: "Maximum call mode (seconds):"
            from: 30
            to: 7200
            editable: true
            onValueModified: page.changed()
        }

        QQC2.Label {
            text: "Battery"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        QQC2.SpinBox {
            id: warnPercent
            Kirigami.FormData.label: "Warn below (%):"
            from: 1
            to: 100
            editable: true
            onValueModified: page.changed()
        }

        QQC2.SpinBox {
            id: criticalPercent
            Kirigami.FormData.label: "Critical below (%):"
            from: 1
            to: 100
            editable: true
            onValueModified: page.changed()
        }

        QQC2.SpinBox {
            id: pollSeconds
            Kirigami.FormData.label: "Check every (seconds):"
            from: 30
            to: 3600
            editable: true
            onValueModified: page.changed()
        }

        QQC2.CheckBox {
            id: saverEnabled
            text: "Disconnect idle earbuds to save battery"
            onToggled: page.changed()
        }

        QQC2.SpinBox {
            id: idleMinutes
            Kirigami.FormData.label: "Idle before saving battery (minutes):"
            from: 1
            to: 1440
            editable: true
            onValueModified: page.changed()
        }

        QQC2.Label {
            text: "This machine"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: laptopBox
            Kirigami.FormData.label: "Laptop power mode:"
            Layout.fillWidth: true
            model: [ "Automatic (detect a laptop)", "Always on", "Off" ]
            onActivated: page.changed()
        }

        QQC2.CheckBox {
            id: routeComms
            text: "Move chat microphones to the default mic"
            onToggled: page.changed()
        }

        QQC2.CheckBox {
            id: fallbackGrab
            text: "Grab a headset when it appears"
            onToggled: page.changed()
        }

        QQC2.CheckBox {
            id: btFallback
            text: "Use the Bluetooth fallback when the dongle disappears"
            onToggled: page.changed()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing

            QQC2.Button {
                text: "Reload"
                enabled: !page.applying
                onClicked: page.load()
            }

            QQC2.Label {
                text: page.statusText
                visible: text !== ""
                color: page.statusColor()
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        QQC2.Label {
            text: "The applet writes these settings for you; there is no file to edit."
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }
}
