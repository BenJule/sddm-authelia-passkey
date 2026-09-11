// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    spacing: 7

    PolishedButton {
        compact: true

        text: qsTr("Ruhezustand")

        visible:
            typeof sddm !== "undefined"
            && sddm.canSuspend === true

        onClicked:
            sddm.suspend()
    }

    PolishedButton {
        compact: true

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

        text: qsTr("Ausschalten")

        visible:
            typeof sddm !== "undefined"
            && sddm.canPowerOff === true

        onClicked:
            sddm.powerOff()
    }
}
