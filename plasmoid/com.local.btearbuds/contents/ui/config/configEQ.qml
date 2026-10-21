import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

// Equalizer + device controls for soundcore gear (Liberty 5 family).
// Values write through to the buds' own memory - the same memory the
// Soundcore app keeps - so settings stick when the buds are undocked.
// Control availability is driven by the model database (device-control
// quirk), not by name strings.
// Host-agnostic root: Kirigami.ScrollablePage works both inside the
// stock Plasma config dialog (PageRow) and inside Maid BT's own
// standalone settings window. KCM.SimpleKCM renders blank in that
// plain-Window context, which is why hosts were broken in 1.0.2.
Kirigami.ScrollablePage {
    id: page

    // install.sh rewrites @HOME@; a system install leaves a bare
    // command name that resolves through PATH.
    property string configTool: "@HOME@/.local/bin/maid-bt-config"
    property string modelTool: "@HOME@/.local/bin/maid-watcher"
    property string soundTool: "@HOME@/.local/bin/maid-soundcore"

    property var values: ({})
    property bool supported: false
    property bool busy: false
    property string statusText: ""
    property string detailText: ""
    property var deviceState: null
    property var eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    readonly property var bandNames: ["31", "62", "125", "250", "500",
                                      "1k", "2k", "4k", "8k", "16k"]
    readonly property var ancModes: [
        { key: "normal", label: "Off" },
        { key: "transparency", label: "Transparent" },
        { key: "vocal", label: "Vocal" },
        { key: "noise", label: "Noise cancel" }
    ]

    function load() {
        statusText = "Reading…";
        detailText = "";
        execSource.connectSource(configTool + " get");
    }

    function checkSupport() {
        supported = false;
        // full alias first (it is the DB key), short name as fallback
        const n = String(values.name || values.short || "").trim();
        if (n === "") {
            statusText = "Pick your earbuds on the Earbuds page first.";
            return;
        }
        // argv style: maid-watcher model <name> (main() joins words)
        execSource.connectSource(modelTool + " model " + n);
    }

    function refreshDevice() {
        busy = true;
        statusText = "Talking to the buds…";
        detailText = "";
        execSource.connectSource(soundTool + " info --json");
    }

    function applyAnc(mode) {
        busy = true;
        statusText = "Applying " + mode + "…";
        execSource.connectSource(soundTool + " anc " + mode);
    }

    function applyEqPreset(p) {
        busy = true;
        statusText = "Applying " + p + " EQ…";
        execSource.connectSource(soundTool + " eq " + p);
    }

    function applyEqCustom() {
        busy = true;
        statusText = "Applying custom EQ…";
        const dB = [];
        for (let i = 0; i < 10; ++i)
            dB.push(String(Math.round(eqBands[i])));
        execSource.connectSource(soundTool + " eq custom " + dB.join(" "));
    }

    function parseState(out, err) {
        let st;
        try {
            st = JSON.parse(out);
        } catch (e) {
            statusText = "Could not read the buds' state.";
            detailText = err !== "" || out !== ""
                ? (err || out)
                : "No response from the buds. Press Refresh to retry.";
            busy = false;
            return;
        }
        deviceState = st;
        for (let i = 0; i < 10; ++i) {
            const v = st.eq && st.eq[i];
            eqBands[i] = (v === null || v === undefined) ? 0 : v;
        }
        busy = false;
        statusText = "";
        detailText = "Firmware " + (st.firmware || "?")
            + "  ·  L " + st.battery.left + "% / R " + st.battery.right
            + "% / case " + st.battery.case + "%"
            + (st.dual_connection ? "  ·  dual connection on" : "");
    }

    onSupportedChanged: {
        if (supported)
            refreshDevice();
    }

    Component.onCompleted: load()

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            const out = String(data["stdout"] || "").trim();
            const err = String(data["stderr"] || "").trim();
            const src = sourceName;

            if (src === page.configTool + " get") {
                if (out.charAt(0) === "{") {
                    try {
                        page.values = JSON.parse(out);
                        page.checkSupport();
                    } catch (e) {
                        page.statusText = "Could not read the Maid BT settings.";
                    }
                } else {
                    page.statusText = "maid-bt-config not found - reinstall Maid BT.";
                }
            } else if (src.indexOf(" model ") !== -1) {
                // line: "<name> -> <brand> <model>  quirks: a, b, c"
                page.supported = out.indexOf("device-control") >= 0;
                if (!page.supported) {
                    page.busy = false;
                    page.statusText = out.indexOf("not in the model database") !== -1
                        ? "This model is not in Maid BT's database yet - tell Maidware the name so it can be added."
                        : "Could not reach the model database.";
                }
            } else if (src === page.soundTool + " info --json") {
                page.busy = false;
                page.parseState(out, err);
            } else if (src.indexOf(" anc ") !== -1
                       || src.indexOf(" eq ") !== -1) {
                if (err !== "" || out === "") {
                    page.statusText = err || out
                        || "Could not change the buds' settings.";
                    page.busy = false;
                } else {
                    page.refreshDevice(); // verify + refresh numbers
                }
            }
            execSource.disconnectSource(src);
        }
    }

    Kirigami.FormLayout {
        // bind to the page root, not the contentItem: ScrollablePage
        // centers narrower children, which pushed the whole form into a
        // floating column instead of filling the pane
        width: page.width
        wideMode: false

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                text: page.supported
                      ? "These controls are written into the earbuds and stay there."
                      : "Not a supported device"
                font.bold: true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            QQC2.Button {
                icon.name: "view-refresh"
                visible: page.supported
                text: "Refresh"
                onClicked: page.refreshDevice()
            }
        }

        QQC2.Label {
            visible: page.statusText !== ""
            text: page.statusText
            color: page.busy ? Kirigami.Theme.textColor
                             : Kirigami.Theme.negativeTextColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        QQC2.Label {
            visible: page.detailText !== ""
            text: page.detailText
            font: Kirigami.Theme.smallFont
            opacity: 0.8
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        QQC2.Label {
            visible: !page.supported
            text: "Supported: Soundcore buds/headphones with vendor device "
                  + "control (model database: device-control). The wire "
                  + "protocol knowledge comes from the open source "
                  + "OpenSCQ30 project; Maid BT speaks it natively."
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            visible: page.supported
        }

        QQC2.Label {
            visible: page.supported
            text: "Noise controls"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        QQC2.ButtonGroup {
            id: modeGroup
        }

        RowLayout {
            visible: page.supported
            Kirigami.FormData.label: "Mode:"

            Repeater {
                model: page.ancModes
                QQC2.Button {
                    required property var modelData
                    checkable: true
                    autoExclusive: false
                    QQC2.ButtonGroup.group: modeGroup
                    enabled: !page.busy
                    text: modelData.label
                    checked: page.deviceState
                             && page.deviceState.anc
                             && page.deviceState.anc.ambient === modelData.key
                    onClicked: page.applyAnc(modelData.key)
                }
            }
        }

        RowLayout {
            visible: page.supported && page.deviceState
                     && page.deviceState.anc
                     && page.deviceState.anc.ambient === "noise"
            Kirigami.FormData.label: "Strength:"
            QQC2.Slider {
                id: strengthSlider
                from: 0
                to: 5
                stepSize: 1
                value: page.deviceState && page.deviceState.anc
                       ? page.deviceState.anc.nc_manual_strength : 5
                Layout.fillWidth: true
                // QQC2.Slider has no onReleased signal; fire once on press
                // end (applies the settled position, not dragging spam).
                onPressedChanged: if (!pressed)
                    page.applyAnc("noise manual " + Math.round(value))
            }
            QQC2.Label {
                text: strengthSlider.value + "/5"
                Layout.preferredWidth: 40
            }
        }

        Kirigami.Separator {
            visible: page.supported
        }

        QQC2.Label {
            visible: page.supported
            text: "Equalizer (stays in the buds)"
            font.bold: true
            Kirigami.FormData.isSection: true
        }

        RowLayout {
            visible: page.supported
            spacing: 4
            Repeater {
                model: page.bandNames
                Item {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    QQC2.Slider {
                        id: bandSlider
                        anchors.horizontalCenter: parent.horizontalCenter
                        orientation: Qt.Vertical
                        height: 100
                        from: -12
                        to: 12
                        stepSize: 1
                        value: page.eqBands[index] ?? 0
                        enabled: !page.busy
                        onMoved: {
                            const next = page.eqBands.slice();
                            next[index] = Math.round(value);
                            page.eqBands = next;
                        }
                    }
                    QQC2.Label {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(bandSlider.value) > 0
                              ? "+" + Math.round(bandSlider.value)
                              : String(Math.round(bandSlider.value))
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.Label {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }
                }
            }
        }

        QQC2.Button {
            visible: page.supported
            text: "Apply custom EQ"
            icon.name: "dialog-ok"
            enabled: !page.busy
            onClicked: page.applyEqCustom()
        }

        RowLayout {
            visible: page.supported
            spacing: 6
            Repeater {
                model: ["flat", "bass-boost", "vocal", "treble-boost"]
                QQC2.Button {
                    required property string modelData
                    enabled: !page.busy
                    text: modelData
                    onClicked: page.applyEqPreset(modelData)
                }
            }
        }

        QQC2.Label {
            visible: page.supported
            text: "EQ curve values live in the earbuds' own memory. "
                  + "Custom curves here do NOT switch between the buds' "
                  + "hearaware presets automatically - fine tune again in "
                  + "the Soundcore app only if you need its extra presets."
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }
}
