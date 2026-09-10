// SPDX-License-Identifier: GPL-3.0-or-later
//
// Pure presentation geometry for the Native Theme.
// Authentication and Smartphone-flow state remain elsewhere.
import QtQuick

QtObject {
    id: root

    property real viewportWidth: 1920
    property real viewportHeight: 1080

    readonly property real shortestEdge:
        Math.min(viewportWidth, viewportHeight)

    readonly property real safeMargin:
        Math.max(
            16,
            Math.min(48, shortestEdge * 0.04)
        )

    // A wide screen may expose the Smartphone panel as a sidebar only
    // while at least a 560-logical-pixel login area still remains.
    readonly property real mainAreaMinWidth: 560

    readonly property real sidebarWidth:
        Math.max(
            480,
            Math.min(560, viewportWidth * 0.30)
        )

    readonly property bool overlayLayout:
        viewportWidth
            < (
                sidebarWidth
                + mainAreaMinWidth
                + 3 * safeMargin
            )

    readonly property bool compactHeight:
        viewportHeight < 700

    readonly property real cardContentMargin:
        compactHeight ? 16 : 24

    readonly property real panelContentMargin:
        compactHeight ? 14 : 22

    readonly property real loginCardMaxWidth:
        compactHeight ? 520 : 560

    readonly property real loginCardWidth:
        Math.max(
            0,
            Math.min(
                loginCardMaxWidth,
                viewportWidth - 2 * safeMargin
            )
        )

    readonly property real loginCardMaxHeight:
        Math.max(
            0,
            viewportHeight - 2 * safeMargin
        )

    readonly property real smartphoneCardWidth:
        Math.max(
            0,
            overlayLayout
                ? Math.min(
                    620,
                    viewportWidth - 2 * safeMargin
                )
                : sidebarWidth
        )

    readonly property real smartphoneCardHeight:
        Math.max(
            0,
            overlayLayout
                ? Math.min(
                    620,
                    viewportHeight - 2 * safeMargin
                )
                : viewportHeight - 2 * safeMargin
        )

    readonly property real qrSide:
        compactHeight
            ? Math.max(
                140,
                Math.min(
                    180,
                    smartphoneCardWidth * 0.34,
                    smartphoneCardHeight * 0.34
                )
            )
            : Math.max(
                180,
                Math.min(
                    210,
                    smartphoneCardWidth * 0.40
                )
            )
}
