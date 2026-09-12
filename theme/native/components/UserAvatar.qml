// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

Rectangle {
    id: root

    property string iconSource: ""
    property string label: ""

    radius: width / 2

    color: "transparent"

    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.15)

    clip: true

    // Adjacent account text already conveys this information.
    Accessible.ignored: true

    readonly property bool hasImage:
        iconSource !== ""
        && avatarImage.status === Image.Ready

    function fallbackColor(seed) {
        var hash = 0

        for (var i = 0; i < seed.length; i++) {
            hash =
                (
                    hash * 31
                    + seed.charCodeAt(i)
                ) % 360
        }

        if (hash < 0)
            hash += 360

        return Qt.hsla(
            hash / 360,
            0.50,
            0.41,
            1
        )
    }

    Image {
        id: avatarImage

        anchors.fill: parent
        anchors.margins: 1

        visible: root.hasImage

        source: root.iconSource

        // Bounds decode cost to the actual displayed size regardless of
        // how large the underlying file on disk is.
        sourceSize.width: Math.max(1, root.width)
        sourceSize.height: Math.max(1, root.height)

        fillMode: Image.PreserveAspectCrop

        asynchronous: true
        smooth: true
        cache: false
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1

        radius: width / 2

        visible: !root.hasImage

        color:
            root.fallbackColor(
                root.label.length > 0
                    ? root.label
                    : "?"
            )

        Text {
            anchors.centerIn: parent

            text:
                root.label.length > 0
                    ? root.label
                        .charAt(0)
                        .toUpperCase()
                    : "?"

            color: "#ffffff"

            font.bold: true
            font.pixelSize:
                Math.max(
                    12,
                    parent.width * 0.39
                )
        }
    }
}
