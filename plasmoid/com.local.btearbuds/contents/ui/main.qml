import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property string btState: "off"
    property string toggle: "/home/visa/.local/bin/bluetooth-toggle.sh"

    toolTipMainText: "BT Earbuds"
    toolTipSubText: stateText()

    function stateText() {
        if (btState === "buds") {
            return "Earbuds on PC";
        }
        if (btState === "on") {
            return "Bluetooth on, buds away";
        }
        return "Bluetooth off";
    }
    function stateIcon() {
        // symbolic icons follow the panel color scheme (white on dark panels)
        return btState === "off" ? "preferences-system-bluetooth-inactive-symbolic" : "preferences-system-bluetooth-activated-symbolic";
    }
    function refresh() {
        execSource.connectSource(toggle + " porcelain");
    }
    function runAction(a) {
        execSource.connectSource(toggle + " " + a);
        refreshSoon.restart();
    }

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (sourceName.indexOf("porcelain") !== -1) {
                var t = String(data["stdout"] || "").trim();
                if (t === "off" || t === "on" || t === "buds") {
                    root.btState = t;
                }
            }
            execSource.disconnectSource(sourceName);
        }
    }

    Timer {
        id: poll
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        id: refreshSoon
        interval: 2000
        repeat: false
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()

    compactRepresentation: MouseArea {
        id: compactMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: root.stateIcon()
        }
    }

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents.Label {
            text: root.stateText()
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Button {
                text: "PC"
                onClicked: root.runAction("on")
            }
            PlasmaComponents.Button {
                text: "Phone"
                onClicked: root.runAction("release")
            }
            PlasmaComponents.Button {
                text: "Off"
                onClicked: root.runAction("off")
            }
        }
    }
}
