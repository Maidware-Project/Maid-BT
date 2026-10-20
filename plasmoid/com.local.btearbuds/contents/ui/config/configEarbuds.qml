import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    // install.sh rewrites @HOME@; a system install leaves a bare
    // command name that resolves through PATH.
    property string configTool: "@HOME@/.local/bin/maid-bt-config"
    property string watcherTool: "@HOME@/.local/bin/maid-watcher"
    property var values: ({})
    property var deviceModel: []
    property var sinkItems: []
    property var sinkModel: []
    property bool customSink: false
    property string audioServer: ""
    property string defaultSink: ""
    property string scanStatus: ""
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
        refreshAudio();
    }

    function refreshAudio() {
        execSource.connectSource("pactl info");
        execSource.connectSource("pactl list sinks");
    }

    function refreshDevices() {
        scanStatus = "Scanning paired devices…";
        execSource.connectSource(watcherTool + " scan");
    }

    function buildSinkModel() {
        const current = sinkField.text.trim();
        const items = [];

        // Keep the configured sink reachable even when the device is
        // unplugged right now; otherwise editing would silently lose it.
        let known = false;
        for (let i = 0; i < sinkItems.length; ++i) {
            if (sinkItems[i].value === current) {
                known = true;
                break;
            }
        }
        if (current !== "" && !known)
            items.push({ label: "Current: " + current, value: current });

        const sorted = sinkItems.slice();
        sorted.sort((a, b) => {
            if (a.value === defaultSink)
                return -1;
            if (b.value === defaultSink)
                return 1;
            return a.label.localeCompare(b.label);
        });
        for (let i = 0; i < sorted.length; ++i) {
            const prefix = sorted[i].value === defaultSink ? "Default: " : "";
            items.push({ label: prefix + sorted[i].label, value: sorted[i].value });
        }
        items.push({ label: "Custom…", value: "__custom__" });

        let index = -1;
        for (let i = 0; i < items.length; ++i) {
            if (items[i].value === current) {
                index = i;
                break;
            }
        }
        if (index < 0)
            index = items.length - 1;
        sinkModel = items;
        sinkBox.currentIndex = index;
        customSink = current === "";
    }

    function populate() {
        ready = false;
        macField.text = values.mac || "";
        nameField.text = values.name || "";
        shortField.text = values.short || "";
        sinkField.text = values.fallback_sink || "";
        autoReconnect.checked = values.auto_reconnect !== false;
        profileBox.currentIndex = values.prefer_profile === "default" ? 1 : 0;
        appCycle.checked = values.app_cycle !== false;
        qualityLock.checked = values.quality_lock === true;
        multipoint.checked = values.multipoint === true;
        buildSinkModel();
        ready = true;
    }

    function payload() {
        return {
            "mac": macField.text.trim(),
            "name": nameField.text.trim(),
            "short": shortField.text.trim(),
            "fallback_sink": sinkField.text.trim(),
            "auto_reconnect": autoReconnect.checked,
            "prefer_profile": profileBox.currentIndex === 1 ? "default" : "a2dp",
            "app_cycle": appCycle.checked,
            "quality_lock": qualityLock.checked,
            "multipoint": multipoint.checked
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

    // KCM's Apply/OK should persist too; every control already saves as
    // it changes, so this is just a final flush.
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

    Component.onCompleted: {
        load();
        refreshDevices();
    }

    P5Support.DataSource {
        id: execSource

        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            const out = String(data["stdout"] || "").trim();
            const err = String(data["stderr"] || "").trim();

            if (sourceName === "pactl info") {
                const match = out.match(/^Server Name:\s*(.*)$/m);
                if (match)
                    page.audioServer = match[1].indexOf("PipeWire") >= 0 ? "PipeWire" : "PulseAudio";
                const def = out.match(/^Default Sink:\s*(.*)$/m);
                if (def)
                    page.defaultSink = def[1].trim();
                page.buildSinkModel();
            } else if (sourceName === "pactl list sinks") {
                const items = [];
                let name = "";
                let description = "";
                const flush = () => {
                    if (name === "")
                        return;
                    items.push({ label: description || name, value: name });
                    name = "";
                    description = "";
                };
                out.split("\n").forEach(line => {
                    if (/^\s*Sink #/.test(line)) {
                        flush();
                        return;
                    }
                    let match = line.match(/^\s*Name:\s*(.+)$/);
                    if (match)
                        name = match[1].trim();
                    match = line.match(/^\s*Description:\s*(.+)$/);
                    if (match)
                        description = match[1].trim();
                });
                flush();
                page.sinkItems = items;
                page.buildSinkModel();
            } else if (sourceName === page.watcherTool + " scan") {
                const devices = [];
                out.split("\n").forEach(line => {
                    const match = line.match(/^\s*([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\s+(.+)$/);
                    if (match)
                        devices.push({ name: match[2] + " (" + match[1] + ")", mac: match[1], label: match[2] });
                });
                page.deviceModel = devices;
                page.scanStatus = devices.length ? "" : (err || "No paired devices found. Pair them in Bluetooth settings first.");
            } else if (sourceName.indexOf(" get") !== -1) {
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
        QQC2.Label {
            text: "Your earbuds"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        RowLayout {
            Layout.fillWidth: true
            Kirigami.FormData.label: "Paired device:"

            QQC2.ComboBox {
                id: deviceBox
                Layout.fillWidth: true
                model: page.deviceModel
                textRole: "name"
                enabled: page.deviceModel.length > 0
                onActivated: {
                    const dev = page.deviceModel[currentIndex];
                    if (!dev)
                        return;
                    macField.text = dev.mac;
                    if (nameField.text.trim() === "" || nameField.text === "My Earbuds")
                        nameField.text = dev.label;
                    if (shortField.text.trim() === "")
                        shortField.text = dev.label;
                    page.changed();
                }
            }

            QQC2.Button {
                text: "Scan"
                icon.name: "view-refresh"
                onClicked: page.refreshDevices()
            }
        }

        QQC2.Label {
            text: page.scanStatus
            visible: text !== ""
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        QQC2.TextField {
            id: macField
            Kirigami.FormData.label: "MAC address:"
            Layout.fillWidth: true
            placeholderText: "AA:BB:CC:DD:EE:FF"
            onTextEdited: page.changed()
        }

        QQC2.TextField {
            id: nameField
            Kirigami.FormData.label: "Name:"
            Layout.fillWidth: true
            placeholderText: "My Earbuds"
            onTextEdited: page.changed()
        }

        QQC2.TextField {
            id: shortField
            Kirigami.FormData.label: "Short name:"
            Layout.fillWidth: true
            placeholderText: "Buds"
            onTextEdited: page.changed()
        }

        RowLayout {
            Layout.fillWidth: true
            Kirigami.FormData.label: "Fallback speakers:"

            QQC2.ComboBox {
                id: sinkBox
                Layout.fillWidth: true
                model: page.sinkModel
                textRole: "label"
                valueRole: "value"
                onActivated: {
                    const item = page.sinkModel[currentIndex];
                    if (!item)
                        return;
                    if (item.value === "__custom__") {
                        page.customSink = true;
                        sinkField.forceActiveFocus();
                    } else {
                        page.customSink = false;
                        sinkField.text = item.value;
                        page.changed();
                    }
                }

                // Show the friendly name first; the raw pactl name stays
                // underneath for people who know what they are looking for.
                delegate: QQC2.ItemDelegate {
                    id: sinkDelegate
                    width: sinkBox.width
                    highlighted: sinkBox.highlightedIndex === index
                    contentItem: ColumnLayout {
                        spacing: 0
                        QQC2.Label {
                            text: modelData.label
                            font.bold: sinkBox.currentIndex === index
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: modelData.value
                            visible: modelData.value !== modelData.label && modelData.value !== "__custom__"
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            QQC2.Button {
                text: "Refresh"
                icon.name: "view-refresh"
                onClicked: page.refreshAudio()
            }
        }

        QQC2.TextField {
            id: sinkField
            visible: page.customSink
            Layout.fillWidth: true
            placeholderText: "alsa_output.…"
            onTextEdited: page.changed()
        }

        QQC2.Label {
            text: page.audioServer === ""
                  ? "Looking for the audio server…"
                  : "Outputs come from " + page.audioServer + " via pactl (PipeWire and PulseAudio both work)."
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        QQC2.CheckBox {
            id: autoReconnect
            text: "Reconnect automatically when the earbuds drop"
            onToggled: page.changed()
        }

        QQC2.ComboBox {
            id: profileBox
            Kirigami.FormData.label: "Preferred audio profile:"
            Layout.fillWidth: true
            model: [ "High quality (A2DP)", "Let the system decide" ]
            onActivated: page.changed()
        }

        QQC2.Label {
            text: "Switching behavior"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: appCycle
            text: "Pause and resume media apps during a switch"
            onToggled: page.changed()
        }

        QQC2.CheckBox {
            id: qualityLock
            text: "Pin LDAC after every switch (needs an LDAC headset/earbuds)"
            onToggled: page.changed()
        }

        QQC2.CheckBox {
            id: multipoint
            text: "Multipoint: let the phone and PC share the earbuds"
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
