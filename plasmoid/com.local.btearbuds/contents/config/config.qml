import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Earbuds")
        icon: "preferences-system-bluetooth"
        source: "config/configEarbuds.qml"
    }

    ConfigCategory {
        name: i18n("Behavior")
        icon: "preferences-system"
        source: "config/configBehavior.qml"
    }

    ConfigCategory {
        name: i18n("Equalizer")
        icon: "audio-equalizer"
        source: "config/configEQ.qml"
    }
}
