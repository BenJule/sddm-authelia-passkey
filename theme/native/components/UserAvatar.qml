// SPDX-License-Identifier: GPL-3.0-or-later
// Original work for sddm-authelia-passkey. Not derived from any
// Debian Breeze or KDE theme source - see theme/native/PROVENANCE.md.
import QtQuick

// A user avatar with a visually safe fallback: if `iconSource` is
// empty or fails to load, shows a deterministic solid-color square
// with the account's first letter instead of a broken image or blank
// space. The fallback colour is derived from `label` only (a simple
// string hash), never from any external/network source.
Rectangle {
    id: root

    property string iconSource: ""
    property string label: ""

    radius: 10
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.18)

    // The adjacent account labels already convey this information.
    Accessible.ignored: true

    readonly property bool hasImage: iconSource !== "" && avatarImage.status === Image.Ready

    function fallbackColor(seed) {
        var hash = 0
        for (var i = 0; i < seed.length; i++) {
            hash = (hash * 31 + seed.charCodeAt(i)) % 360
        }
        if (hash < 0) hash += 360
        return Qt.hsla(hash / 360, 0.45, 0.38, 1)
    }

    Image {
        id: avatarImage
        anchors.fill: parent
        anchors.margins: 1
        visible: root.hasImage
        source: root.iconSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        cache: false
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: root.radius - 1
        visible: !root.hasImage
        color: root.fallbackColor(root.label.length > 0 ? root.label : "?")

        Text {
            anchors.centerIn: parent
            text: root.label.length > 0 ? root.label.charAt(0).toUpperCase() : "?"
            color: "white"
            font.bold: true
            font.pixelSize: Math.max(12, parent.width * 0.45)
        }
    }
}
