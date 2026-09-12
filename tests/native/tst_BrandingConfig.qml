// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    name: "BrandingConfig"

    QtObject {
        id: mockConfig

        property var values: ({})

        function keys() {
            return Object.keys(values)
        }

        function stringValue(key) {
            if (values[key] === undefined)
                return ""

            return String(values[key])
        }

        function boolValue(key) {
            var value = values[key]

            return value === true
                || value === "true"
                || value === "1"
        }
    }

    Native.BrandingConfig {
        id: branding

        configSource:
            mockConfig

        hostName:
            "sddm-lab"

        defaultAccentColor:
            "#3478e8"
    }

    function applyValues(values) {
        mockConfig.values = values

        branding.configSource = null
        branding.configSource = mockConfig

        wait(0)
    }

    function init() {
        applyValues({
            "ui_brand_name": "",
            "ui_brand_logo": "",
            "ui_show_hostname": false,
            "ui_show_domain": false,
            "ui_brand_domain": "",
            "ui_show_avatar": true,
            "ui_accent": "system",
            "ui_accent_color": ""
        })
    }

    function test_defaults_preserve_v112() {
        compare(
            branding.brandName,
            ""
        )

        compare(
            branding.brandLogoLocal,
            false
        )

        compare(
            branding.brandLogoSource,
            ""
        )

        compare(
            branding.contextLabel,
            ""
        )

        compare(
            branding.showAvatar,
            true
        )

        compare(
            branding.useCustomAccent,
            false
        )

        compare(
            branding.accentColor.toString(),
            "#3478e8"
        )
    }

    function test_full_custom_branding() {
        applyValues({
            "ui_brand_name":
                "Example Corp",
            "ui_brand_logo":
                "/opt/example/logo.svg",
            "ui_show_hostname":
                true,
            "ui_show_domain":
                true,
            "ui_brand_domain":
                "EXAMPLE.LOCAL",
            "ui_show_avatar":
                false,
            "ui_accent":
                "custom",
            "ui_accent_color":
                "#8b5cf6"
        })

        compare(
            branding.brandName,
            "Example Corp"
        )

        compare(
            branding.brandLogoLocal,
            true
        )

        compare(
            branding.brandLogoSource,
            "file:///opt/example/logo.svg"
        )

        compare(
            branding.contextLabel,
            "sddm-lab · EXAMPLE.LOCAL"
        )

        compare(
            branding.showAvatar,
            false
        )

        compare(
            branding.useCustomAccent,
            true
        )

        compare(
            branding.accentColor.toString(),
            "#8b5cf6"
        )
    }

    function test_remote_logo_is_rejected() {
        applyValues({
            "ui_brand_logo":
                "https://example.invalid/logo.svg"
        })

        compare(
            branding.brandLogoLocal,
            false
        )

        compare(
            branding.brandLogoSource,
            ""
        )
    }

    function test_relative_logo_is_rejected() {
        applyValues({
            "ui_brand_logo":
                "logo.svg"
        })

        compare(
            branding.brandLogoLocal,
            false
        )
    }

    function test_invalid_custom_accent_falls_back() {
        applyValues({
            "ui_accent":
                "custom",
            "ui_accent_color":
                "#1234"
        })

        compare(
            branding.useCustomAccent,
            false
        )

        compare(
            branding.accentColor.toString(),
            "#3478e8"
        )
    }

    function test_system_mode_ignores_custom_colour() {
        applyValues({
            "ui_accent":
                "system",
            "ui_accent_color":
                "#8b5cf6"
        })

        compare(
            branding.useCustomAccent,
            false
        )

        compare(
            branding.accentColor.toString(),
            "#3478e8"
        )
    }

    function test_avatar_missing_key_defaults_true() {
        applyValues({
            "ui_brand_name": ""
        })

        compare(
            branding.showAvatar,
            true
        )
    }

    function test_domain_requires_explicit_toggle() {
        applyValues({
            "ui_brand_domain":
                "EXAMPLE.LOCAL",
            "ui_show_domain":
                false
        })

        compare(
            branding.showDomain,
            false
        )

        compare(
            branding.contextLabel,
            ""
        )
    }

    function test_huge_brand_name_is_truncated() {
        var huge = new Array(500).join("X")

        applyValues({
            "ui_brand_name": huge
        })

        verify(branding.brandName.length <= branding.maxDisplayLength + 1)
        verify(branding.brandName.indexOf("…") >= 0)
    }

    function test_huge_brand_domain_is_truncated() {
        var huge = new Array(500).join("Y")

        applyValues({
            "ui_brand_domain": huge,
            "ui_show_domain": true
        })

        verify(branding.brandDomain.length <= branding.maxDisplayLength + 1)
        verify(branding.brandDomain.indexOf("…") >= 0)
    }

    function test_short_brand_name_is_not_truncated() {
        applyValues({
            "ui_brand_name": "Example Corp"
        })

        compare(
            branding.brandName,
            "Example Corp"
        )
    }
}
