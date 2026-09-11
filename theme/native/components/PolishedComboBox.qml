// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as QQC2

QQC2.ComboBox {
    id: control

    property bool useCustomAccent: false
    property color accentColor: "#3478e8"

    implicitHeight: 42

    leftPadding: 12
    rightPadding: 34

    hoverEnabled: true

    font.pixelSize: 12

    contentItem: Text {
        text: control.displayText
        font: control.font

        color:
            control.enabled
                ? "#e9f0f7"
                : "#6c7a8b"

        verticalAlignment:
            Text.AlignVCenter

        elide:
            Text.ElideRight
    }

    indicator: Text {
        x:
            control.width
            - width
            - 13

        y:
            (
                control.height
                - height
            ) / 2

        text: "⌄"
        color: "#8ca0b4"

        font.pixelSize: 16
        font.bold: true
    }

    background: Rectangle {
        radius: 10

        color:
            control.down
                ? Qt.rgba(
                    0.13,
                    0.19,
                    0.26,
                    0.98
                )
                : control.hovered
                    ? Qt.rgba(
                        0.105,
                        0.16,
                        0.22,
                        0.98
                    )
                    : Qt.rgba(
                        0.065,
                        0.10,
                        0.14,
                        0.96
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
                        : "#61a0ff"
                )
                : Qt.rgba(
                    1,
                    1,
                    1,
                    0.095
                )
    }

    delegate: QQC2.ItemDelegate {
        id: delegateItem

        required property int index

        width:
            control.width - 12

        height: 38

        highlighted:
            control.highlightedIndex
            === index

        contentItem: Text {
            text:
                control.textAt(
                    delegateItem.index
                )

            color: "#edf3fa"

            font.pixelSize: 12

            verticalAlignment:
                Text.AlignVCenter

            elide:
                Text.ElideRight
        }

        background: Rectangle {
            radius: 8

            color:
                delegateItem.highlighted
                    ? (
                        control.useCustomAccent
                            ? Qt.rgba(
                                control.accentColor.r,
                                control.accentColor.g,
                                control.accentColor.b,
                                0.38
                            )
                            : Qt.rgba(
                                0.20,
                                0.46,
                                0.88,
                                0.38
                            )
                    )
                    : "transparent"
        }
    }

    popup: QQC2.Popup {
        y:
            control.height + 5

        width:
            control.width

        padding: 6

        contentItem: ListView {
            clip: true

            implicitHeight:
                Math.min(
                    contentHeight,
                    228
                )

            model:
                control.popup.visible
                    ? control.delegateModel
                    : null

            currentIndex:
                control.highlightedIndex
        }

        background: Rectangle {
            radius: 11
            color: "#0d171f"

            border.width: 1

            border.color:
                Qt.rgba(
                    1,
                    1,
                    1,
                    0.11
                )
        }
    }
}
