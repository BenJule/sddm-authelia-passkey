// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls.Basic as QQC2

QQC2.TextField {
    id: control

    implicitHeight: 46

    leftPadding: 14
    rightPadding: 14

    color: "#f2f6fb"
    placeholderTextColor: "#718397"

    selectionColor: "#3478e8"
    selectedTextColor: "#ffffff"

    font.pixelSize: 13

    selectByMouse: true

    background: Rectangle {
        radius: 11

        color:
            control.enabled
                ? Qt.rgba(0.045, 0.070, 0.096, 0.98)
                : Qt.rgba(0.045, 0.070, 0.096, 0.58)

        border.width:
            control.activeFocus
                ? 2
                : 1

        border.color:
            control.activeFocus
                ? "#61a0ff"
                : Qt.rgba(1, 1, 1, 0.105)
    }
}
