import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

// Maid BT Settings - the Maidware's own settings window.
//
// Plasma's stock applet settings dialog adds "Keyboard Shortcuts" and
// "About" pages for every widget and they cannot be removed from an
// applet side, so for Maid BT 1.1 the gear button (and the tray menu
// entry) opens this window instead. It houses the exact pages we ship:
// Earbuds, Behavior, Equalizer, About - nothing else.
Window {
    id: btWindow

    title: "Maid BT Settings"
    width: 860
    height: 640
    minimumWidth: 760
    minimumHeight: 560
    visible: false
    color: Kirigami.Theme.backgroundColor

    function open() {
        visible = true;
        raise();
        requestActivate();
    }

    readonly property var entries: [
        { key: "earbuds", label: "Earbuds",
          icon: "preferences-system-bluetooth",
          source: "config/configEarbuds.qml" },
        { key: "behavior", label: "Behavior",
          icon: "preferences-system",
          source: "config/configBehavior.qml" },
        { key: "eq", label: "Equalizer", icon: "audio-equalizer",
          source: "config/configEQ.qml" },
        { key: "about", label: "About", icon: "help-about", source: "" }
    ]
    property int current: 0

    onCurrentChanged: loadError = false
    property bool loadError: false

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            color: Kirigami.Theme.alternateBackgroundColor
            Layout.fillHeight: true
            Layout.preferredWidth: 150

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 2
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: btWindow.entries

                    QQC2.ItemDelegate {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        highlighted: btWindow.current === index
                        onClicked: btWindow.current = index
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: modelData.icon
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                            }
                            QQC2.Label {
                                text: modelData.label
                                font.bold: btWindow.current === index
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        Kirigami.Separator {
            Layout.fillHeight: true
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                id: pageLoader
                anchors.fill: parent
                Component.onCompleted: {
                    pageLoader.source
                        = btWindow.entries[btWindow.current].source;
                }

                Connections {
                    target: btWindow
                    function onCurrentChanged() {
                        const entry = btWindow.entries[btWindow.current];
                        if (entry.source === "") {
                            // unload the file page, then mount the inline
                            // About pane
                            pageLoader.source = "";
                            pageLoader.sourceComponent = aboutPane;
                        } else {
                            // Loader: "if source and sourceComponent are
                            // both set, the one set last is used". The old
                            // code assigned source, then assigned
                            // sourceComponent = undefined - which counts as
                            // set-last and destroyed the page it had just
                            // created, leaving every page silently blank.
                            pageLoader.source = entry.source;
                        }
                    }
                }

                Component {
                    id: aboutPane

                    Flickable {
                        id: aboutFlick
                        contentWidth: width
                        contentHeight: aboutCol.height
                                      + aboutFlick.applyPadding * 2
                        property int applyPadding: Kirigami.Units.gridUnit

                        ColumnLayout {
                            id: aboutCol
                            x: aboutFlick.applyPadding
                            y: aboutFlick.applyPadding
                            width: aboutFlick.width - aboutFlick.applyPadding * 2
                            spacing: Kirigami.Units.gridUnit

                            RowLayout {
                                Kirigami.Icon {
                                    source: "bluetooth"
                                }
                                QQC2.Label {
                                    text: "<h2>Maid BT 1.1</h2>"
                                    onLinkActivated: function(link) {
                                        Qt.openUrlExternally(link);
                                    }
                                }
                            }

                            QQC2.Label {
                                text: "A Linux-only seamless Bluetooth "
                                      + "earbuds switcher: reconnects, "
                                      + "switches audio, guards calls and "
                                      + "keeps the buds alive in the "
                                      + "tray. Part of the Maidware "
                                      + "Project."
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }

                            Kirigami.Separator { Layout.fillWidth: true }

                            QQC2.Label {
                                text: "<b>Soundcore device control</b>"
                                      + "<p>The equalizer and noise "
                                      + "controls speak the Soundcore "
                                      + "vendor protocol - the wire "
                                      + "format documented by the "
                                      + "<a href=\"https://github.com/Oppzippy/OpenSCQ30\">"
                                      + "OpenSCQ30</a> open source "
                                      + "project (GPL-3.0). Maid BT does "
                                      + "not copy their code: our "
                                      + "implementation is an independent "
                                      + "clean-room port written fresh in "
                                      + "Python and released under the "
                                      + "MIT license, so Maidware stays "
                                      + "MIT and their project deserves "
                                      + "all the credit for reverse "
                                      + "engineering the protocol."
                                      + "</p>"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                onLinkActivated: function(link) {
                                    Qt.openUrlExternally(link);
                                }
                            }

                            QQC2.Label {
                                text: "<p>License: MIT (see LICENSE). "
                                      + "Website: <a href=\"https://maidware-project.github.io/\">"
                                      + "maidware-project.github.io</a> "
                                      + "· Issues, ideas and pull "
                                      + "requests welcome.</p>"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                onLinkActivated: function(link) {
                                    Qt.openUrlExternally(link);
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: btWindow.loadError
                    anchors.centerIn: parent
                    width: 320
                    height: 120
                    radius: Kirigami.Units.smallSpacing
                    color: Kirigami.Theme.alternateBackgroundColor

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.gridUnit

                        QQC2.Label {
                            text: "This settings page failed to load."
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                        QQC2.Button {
                            text: "Open the Plasma settings dialog"
                            onClicked: {
                                Plasmoid.internalAction("configure")
                                    .trigger();
                            }
                        }
                    }
                }
            }

            Connections {
                target: pageLoader
                function onStatusChanged() {
                    btWindow.loadError = pageLoader.status === Loader.Error;
                }
            }
        }
    }
}
