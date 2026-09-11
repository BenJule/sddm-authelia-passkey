// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property bool useCustomAccent: false
    property color accentColor: "#3478e8"

    spacing: 7

    Accessible.role: Accessible.ToolBar
    Accessible.name: qsTr("Systemaktionen")

    PolishedButton {
        compact: true

        useCustomAccent:
            root.useCustomAccent

        accentColor:
            root.accentColor

        text: qsTr("Ruhezustand")

        visible:
            typeof sddm !== "undefined"
            && sddm.canSuspend === true

        onClicked:
            sddm.suspend()
    }

    PolishedButton {
        compact: true

        useCustomAccent:
            root.useCustomAccent

        accentColor:
            root.accentColor

        text: qsTr("Neu starten")

        visible:
            typeof sddm !== "undefined"
            && sddm.canReboot === true

        onClicked:
            sddm.reboot()
    }

    PolishedButton {
        compact: true
        destructive: true

        useCustomAccent:
            root.useCustomAccent

        accentColor:
            root.accentColor

        text: qsTr("Ausschalten")

        visible:
            typeof sddm !== "undefined"
            && sddm.canPowerOff === true

        onClicked:
            sddm.powerOff()
    }
}
