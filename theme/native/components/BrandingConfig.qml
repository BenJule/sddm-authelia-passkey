// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

QtObject {
    id: root

    property var configSource: null
    property string hostName: ""

    // This is deliberately the exact v1.12 Native Theme accent.
    // With no override, v1.13 must remain visually identical.
    property color defaultAccentColor: "#3478e8"

    function hasKey(key) {
        if (
            !root.configSource
            || typeof root.configSource.keys
                !== "function"
        )
            return false

        return root.configSource
            .keys()
            .indexOf(key) >= 0
    }

    function readString(key) {
        if (
            !root.configSource
            || typeof root.configSource.stringValue
                !== "function"
        )
            return ""

        var value =
            root.configSource.stringValue(key)

        return value === undefined
            || value === null
                ? ""
                : String(value)
    }

    function readBool(
        key,
        fallback
    ) {
        if (!root.hasKey(key))
            return fallback

        if (
            typeof root.configSource.boolValue
            !== "function"
        )
            return fallback

        return root.configSource.boolValue(key)
    }

    readonly property string brandName:
        root.readString(
            "ui_brand_name"
        ).trim()

    readonly property string brandLogoPath:
        root.readString(
            "ui_brand_logo"
        ).trim()

    readonly property bool brandLogoLocal:
        brandLogoPath.length > 1
        && brandLogoPath.charAt(0) === "/"
        && brandLogoPath.indexOf("://") === -1

    readonly property string brandLogoSource:
        brandLogoLocal
            ? "file://" + brandLogoPath
            : ""

    readonly property bool showHostname:
        root.readBool(
            "ui_show_hostname",
            false
        )
        && root.hostName.trim().length > 0

    readonly property string brandDomain:
        root.readString(
            "ui_brand_domain"
        ).trim()

    readonly property bool showDomain:
        root.readBool(
            "ui_show_domain",
            false
        )
        && brandDomain.length > 0

    readonly property bool showAvatar:
        root.readBool(
            "ui_show_avatar",
            true
        )

    readonly property string accentMode:
        root.readString(
            "ui_accent"
        ).trim().toLowerCase()

    readonly property string accentCandidate:
        root.readString(
            "ui_accent_color"
        ).trim()

    readonly property bool customAccentValid:
        /^#[0-9a-fA-F]{6}$/.test(
            accentCandidate
        )

    readonly property bool useCustomAccent:
        accentMode === "custom"
        && customAccentValid

    readonly property color accentColor:
        useCustomAccent
            ? accentCandidate
            : defaultAccentColor

    readonly property string contextLabel: {
        var parts = []

        if (showHostname)
            parts.push(
                hostName.trim()
            )

        if (showDomain)
            parts.push(
                brandDomain
            )

        return parts.join(" · ")
    }
}
