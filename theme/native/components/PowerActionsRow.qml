// SPDX-License-Identifier: GPL-3.0-or-later
// Original work for sddm-authelia-passkey. Not derived from any
// Debian Breeze or KDE theme source - see theme/native/PROVENANCE.md.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

// Suspend/restart/shutdown, gated strictly by the SDDM context's own
// sddm.canSuspend/canReboot/canPowerOff - never assumed available,
// never a custom capability guess.
RowLayout {
    id: root

    spacing: 12

    Accessible.role: Accessible.ToolBar
    Accessible.name: qsTr("Systemaktionen")

    QQC2.Button {
        text: qsTr("Ruhezustand")
        visible: typeof sddm !== "undefined" && sddm.canSuspend === true
        onClicked: sddm.suspend()
    }
    QQC2.Button {
        text: qsTr("Neu starten")
        visible: typeof sddm !== "undefined" && sddm.canReboot === true
        onClicked: sddm.reboot()
    }
    QQC2.Button {
        text: qsTr("Herunterfahren")
        visible: typeof sddm !== "undefined" && sddm.canPowerOff === true
        onClicked: sddm.powerOff()
    }
}
