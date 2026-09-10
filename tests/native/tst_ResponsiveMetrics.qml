// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    name: "ResponsiveMetrics"

    Native.ResponsiveMetrics {
        id: metrics
    }

    function setViewport(w, h) {
        metrics.viewportWidth = w
        metrics.viewportHeight = h
        wait(0)
    }

    function test_1024x600_uses_overlay() {
        setViewport(1024, 600)

        compare(metrics.overlayLayout, true)
        compare(metrics.compactHeight, true)

        verify(
            metrics.loginCardWidth
                <= metrics.viewportWidth
                    - 2 * metrics.safeMargin
        )

        verify(
            metrics.smartphoneCardHeight
                <= metrics.viewportHeight
                    - 2 * metrics.safeMargin
        )

        verify(metrics.qrSide <= 180)
    }

    function test_1280x720_uses_sidebar() {
        setViewport(1280, 720)

        compare(metrics.overlayLayout, false)
        compare(metrics.compactHeight, false)
        compare(metrics.sidebarWidth, 480)

        verify(
            metrics.mainAreaMinWidth
                + metrics.sidebarWidth
                + 3 * metrics.safeMargin
                <= metrics.viewportWidth
        )
    }

    function test_1366x768_uses_sidebar() {
        setViewport(1366, 768)

        compare(metrics.overlayLayout, false)
        compare(metrics.compactHeight, false)

        verify(metrics.smartphoneCardWidth >= 480)
        verify(metrics.smartphoneCardWidth <= 560)
    }

    function test_1920x1080_uses_sidebar() {
        setViewport(1920, 1080)

        compare(metrics.overlayLayout, false)
        compare(metrics.compactHeight, false)

        verify(metrics.safeMargin >= 16)
        verify(metrics.safeMargin <= 48)
    }

    function test_ultrawide_sidebar_is_capped() {
        setViewport(2560, 1080)

        compare(metrics.overlayLayout, false)
        compare(metrics.sidebarWidth, 560)
        verify(metrics.smartphoneCardWidth <= 560)
        verify(metrics.qrSide <= 210)
    }

    function test_breakpoint_is_derived_from_available_space() {
        setViewport(1100, 720)
        compare(metrics.overlayLayout, true)

        setViewport(1280, 720)
        compare(metrics.overlayLayout, false)
    }
}
