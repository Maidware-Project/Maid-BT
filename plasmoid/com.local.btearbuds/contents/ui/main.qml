import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property string btState: "off"
    property bool busy: false
    readonly property int popupWidth: Math.max(Kirigami.Units.gridUnit * 22, 380)
    property string toggle: "@HOME@/.local/bin/bluetooth-toggle.sh"

    Loader {
        id: settingsWinLoader
        asynchronous: true
        active: false
        source: "btSettingsWindow.qml"
        onLoaded: item.open()
    }

    function openSettings() {
        if (!settingsWinLoader.active)
            settingsWinLoader.active = true;
        else if (settingsWinLoader.item)
            settingsWinLoader.item.open();
    }

    function stateText() {
        if (btState === "buds")
            return "Earbuds: PC";

        if (btState === "phone")
            return "Earbuds: phone";

        if (btState === "on")
            return "Bluetooth on";

        return "Bluetooth off";
    }

    function stateDetail() {
        if (btState === "buds")
            return "audio here";

        if (btState === "phone")
            return "on speakers";

        if (btState === "on")
            return "ready to connect";

        return "radio is off";
    }

    function stateIcon() {
        // symbolic glyphs recolor with the theme and match the panel style
        if (root.btState === "off")
            return "bluetooth-disabled-symbolic";

        if (root.btState === "on")
            return "bluetooth-disconnected-symbolic";

        return "bluetooth-active-symbolic";
    }

    function refresh() {
        execSource.connectSource(toggle + " porcelain");
    }

    function runAction(a) {
        if (busy)
            return ;

        busy = true;
        execSource.connectSource(toggle + " " + a);
        refreshSoon.restart();
    }

    toolTipMainText: "Maid BT"
    toolTipSubText: "click for controls"
    Component.onCompleted: refresh()

    P5Support.DataSource {
        id: execSource

        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (sourceName.indexOf("porcelain") !== -1) {
                var t = String(data["stdout"] || "").trim();
                if (t === "off" || t === "on" || t === "buds" || t === "phone")
                    root.btState = t;

            }
            execSource.disconnectSource(sourceName);
        }
    }

    Timer {
        id: poll

        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshSoon

        interval: 1100
        repeat: false
        onTriggered: {
            root.busy = false;
            root.refresh();
        }
    }

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
        id: fullRoot

        implicitWidth: root.popupWidth
        Layout.minimumWidth: root.popupWidth
        Layout.preferredWidth: root.popupWidth
        Layout.maximumWidth: root.popupWidth
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
            Layout.preferredHeight: implicitHeight

            ColumnLayout {
                id: content

                x: Kirigami.Units.largeSpacing
                y: Kirigami.Units.largeSpacing
                width: parent.width - Kirigami.Units.largeSpacing * 2
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: root.stateIcon()
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        PlasmaComponents.Label {
                            text: root.stateText()
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Rectangle {
                                width: Kirigami.Units.smallSpacing
                                height: width
                                radius: width / 2
                                color: {
                                    if (root.btState === "buds" || root.btState === "phone")
                                        return Kirigami.Theme.positiveTextColor;

                                    if (root.btState === "on")
                                        return Kirigami.Theme.neutralTextColor;

                                    return Kirigami.Theme.disabledTextColor;
                                }
                            }

                            PlasmaComponents.Label {
                                text: root.stateDetail()
                                font: Kirigami.Theme.smallFont
                                opacity: 0.75
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                        }

                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "configure"
                        display: PlasmaComponents.AbstractButton.IconOnly
                        Layout.alignment: Qt.AlignVCenter
                        Accessible.name: "Configure Maid BT"
                        PlasmaComponents.ToolTip.text: "Open Maid BT settings"
                        PlasmaComponents.ToolTip.visible: hovered
                        onClicked: {
                            root.expanded = false;
                            root.openSettings();
                        }
                    }

                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: Kirigami.Units.smallSpacing
                    columnSpacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.ItemDelegate {
                        id: pcTile

                        text: "This PC"
                        icon.name: "computer-symbolic"
                        display: PlasmaComponents.AbstractButton.TextUnderIcon
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2.9
                        highlighted: root.btState === "buds"
                        enabled: !root.busy
                        PlasmaComponents.ToolTip.text: "Connect earbuds to this PC."
                        PlasmaComponents.ToolTip.visible: hovered
                        onClicked: root.runAction("on")

                        contentItem: Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                opacity: pcTile.enabled ? 1 : 0.5
                                spacing: 2

                                Kirigami.Icon {
                                    source: pcTile.icon.name
                                    color: pcTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                }

                                PlasmaComponents.Label {
                                    text: pcTile.text
                                    font.bold: pcTile.highlighted
                                    color: pcTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                }

                            }

                        }

                    }

                    PlasmaComponents.ItemDelegate {
                        id: phoneTile

                        text: "Phone"
                        icon.name: "smartphone-symbolic"
                        display: PlasmaComponents.AbstractButton.TextUnderIcon
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2.9
                        highlighted: root.btState === "phone"
                        enabled: !root.busy
                        PlasmaComponents.ToolTip.text: "Release earbuds to the phone."
                        PlasmaComponents.ToolTip.visible: hovered
                        onClicked: root.runAction("release")

                        contentItem: Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                opacity: phoneTile.enabled ? 1 : 0.5
                                spacing: 2

                                Kirigami.Icon {
                                    source: phoneTile.icon.name
                                    color: phoneTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                }

                                PlasmaComponents.Label {
                                    text: phoneTile.text
                                    font.bold: phoneTile.highlighted
                                    color: phoneTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                }

                            }

                        }

                    }

                    PlasmaComponents.ItemDelegate {
                        id: radioTile

                        text: "Other devices"
                        icon.name: "bluetooth-symbolic"
                        display: PlasmaComponents.AbstractButton.TextUnderIcon
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2.9
                        enabled: !root.busy
                        Accessible.description: "Power Bluetooth for a mouse, controller, or other accessory without moving earbud audio"
                        PlasmaComponents.ToolTip.text: "Bluetooth on for another device."
                        PlasmaComponents.ToolTip.visible: hovered
                        onClicked: root.runAction("radio")

                        contentItem: Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                opacity: radioTile.enabled ? 1 : 0.5
                                spacing: 2

                                Kirigami.Icon {
                                    source: radioTile.icon.name
                                    color: radioTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                }

                                PlasmaComponents.Label {
                                    text: radioTile.text
                                    font.bold: radioTile.highlighted
                                    color: radioTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                }

                            }

                        }

                    }

                    PlasmaComponents.ItemDelegate {
                        id: offTile

                        text: "Off"
                        icon.name: "bluetooth-disabled-symbolic"
                        display: PlasmaComponents.AbstractButton.TextUnderIcon
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2.9
                        highlighted: root.btState === "off"
                        enabled: !root.busy
                        PlasmaComponents.ToolTip.text: "Turn Bluetooth off."
                        PlasmaComponents.ToolTip.visible: hovered
                        onClicked: root.runAction("off")

                        contentItem: Item {
                            ColumnLayout {
                                anchors.centerIn: parent
                                opacity: offTile.enabled ? 1 : 0.5
                                spacing: 2

                                Kirigami.Icon {
                                    source: offTile.icon.name
                                    color: offTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                }

                                PlasmaComponents.Label {
                                    text: offTile.text
                                    font.bold: offTile.highlighted
                                    color: offTile.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    Layout.alignment: Qt.AlignHCenter
                                }

                            }

                        }

                    }

                }

                PlasmaComponents.Label {
                    visible: root.busy
                    text: "working…"
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }

                // breathing room under the tile grid
                Item {
                    implicitHeight: Kirigami.Units.mediumSpacing
                    Layout.fillWidth: true
                }

            }

        }

    }

}
