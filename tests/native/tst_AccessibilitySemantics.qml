// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    name: "AccessibilitySemantics"

    Native.UserAvatar {
        id: avatar
        width: 48
        height: 48
        label: "Alice"
    }

    Native.ConnectionStatus {
        id: connectionStatus
        connectionState: "offline"
    }

    Native.UserChooser {
        id: chooser
        width: 400
        userModelSource: null
    }

    Native.SmartphoneLoginPanel {
        id: smartphonePanel
        width: 620
        height: 620
        controller: null
        open: false
        modalLayout: false
    }

    Native.PowerActionsRow {
        id: powerActions
    }

    function test_decorative_avatar_is_ignored() {
        compare(avatar.Accessible.ignored, true)
    }

    function test_connection_status_semantics() {
        compare(
            connectionStatus.Accessible.role,
            Accessible.StatusBar
        )

        verify(
            connectionStatus.Accessible.name
                .indexOf("Offline") >= 0
        )
    }

    function test_user_chooser_semantics() {
        compare(
            chooser.Accessible.role,
            Accessible.Pane
        )

        verify(chooser.Accessible.name.length > 0)
    }

    function test_panel_role_follows_layout() {
        smartphonePanel.modalLayout = false

        compare(
            smartphonePanel.Accessible.role,
            Accessible.Pane
        )

        smartphonePanel.modalLayout = true

        compare(
            smartphonePanel.Accessible.role,
            Accessible.Dialog
        )

        smartphonePanel.modalLayout = false
    }

    function test_power_actions_are_grouped() {
        compare(
            powerActions.Accessible.role,
            Accessible.ToolBar
        )

        verify(powerActions.Accessible.name.length > 0)
    }
}
