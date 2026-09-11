// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls.Basic as QQC2

QQC2.Button {
    id: control

    property bool primary: false
    property bool destructive: false
    property bool compact: false

    property bool useCustomAccent: false
    property color accentColor: "#3478e8"

    hoverEnabled: true

    implicitHeight:
        compact ? 38 : 46

    implicitWidth:
        Math.max(
            compact ? 94 : 116,
            contentItem.implicitWidth
                + leftPadding
                + rightPadding
        )

    leftPadding:
        compact ? 14 : 18

    rightPadding:
        compact ? 14 : 18

    font.pixelSize:
        compact ? 11 : 13

    font.weight:
        primary
            ? Font.DemiBold
            : Font.Medium

    contentItem: Text {
        text: control.text
        font: control.font

        color:
            !control.enabled
                ? "#657487"
                : control.primary
                    ? "#ffffff"
                    : control.destructive
                        ? "#ffb7b7"
                        : "#e5edf6"

        horizontalAlignment:
            Text.AlignHCenter

        verticalAlignment:
            Text.AlignVCenter

        elide:
            Text.ElideRight
    }

    background: Rectangle {
        radius:
            control.compact
                ? 9
                : 11

        color:
            !control.enabled
                ? Qt.rgba(
                    0.07,
                    0.10,
                    0.14,
                    0.55
                )
                : control.primary
                    ? (
                        control.down
                            ? (
                                control.useCustomAccent
                                    ? Qt.darker(
                                        control.accentColor,
                                        1.18
                                    )
                                    : "#2865cf"
                            )
                            : control.hovered
                                ? (
                                    control.useCustomAccent
                                        ? Qt.lighter(
                                            control.accentColor,
                                            1.08
                                        )
                                        : "#4386f4"
                                )
                                : (
                                    control.useCustomAccent
                                        ? control.accentColor
                                        : "#3478e8"
                                )
                    )
                    : control.destructive
                        ? (
                            control.hovered
                                ? Qt.rgba(
                                    0.46,
                                    0.14,
                                    0.17,
                                    0.78
                                )
                                : Qt.rgba(
                                    0.32,
                                    0.10,
                                    0.13,
                                    0.72
                                )
                        )
                        : (
                            control.down
                                ? Qt.rgba(
                                    0.18,
                                    0.25,
                                    0.33,
                                    0.96
                                )
                                : control.hovered
                                    ? Qt.rgba(
                                        0.14,
                                        0.20,
                                        0.27,
                                        0.96
                                    )
                                    : Qt.rgba(
                                        0.09,
                                        0.135,
                                        0.18,
                                        0.94
                                    )
                        )

        border.width:
            control.activeFocus
                ? 2
                : 1

        border.color:
            control.activeFocus
                ? (
                    control.useCustomAccent
                        ? control.accentColor
                        : "#66a6ff"
                )
                : control.primary
                    ? (
                        control.useCustomAccent
                            ? Qt.lighter(
                                control.accentColor,
                                1.18
                            )
                            : "#5895f0"
                    )
                    : control.destructive
                        ? Qt.rgba(
                            1,
                            0.42,
                            0.44,
                            0.36
                        )
                        : Qt.rgba(
                            1,
                            1,
                            1,
                            0.10
                        )

        Behavior on color {
            ColorAnimation {
                duration: 90
            }
        }
    }
}
