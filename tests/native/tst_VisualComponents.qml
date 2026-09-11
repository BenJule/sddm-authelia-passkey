// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    name: "VisualComponents"

    Native.PolishedButton {
        id: button
        text: "Test"
    }

    Native.PolishedTextField {
        id: field
        placeholderText: "Test"
    }

    Native.PolishedComboBox {
        id: combo
        model: [
            "A",
            "B"
        ]
    }

    Native.ConnectionStatus {
        id: status
        connectionState: "waiting"
    }

    ListModel {
        id: accountModel

        ListElement {
            name: "alice"
            realName: "Alice"
            icon: ""
        }

        ListElement {
            name: "benlue"
            realName: "Debian"
            icon: ""
        }

        ListElement {
            name: "bob"
            realName: "Bob"
            icon: ""
        }
    }

    Native.UserChooser {
        id: chooser

        width: 420

        userModelSource:
            accountModel
    }

    function test_control_sizes() {
        verify(button.implicitHeight >= 38)
        verify(field.implicitHeight >= 42)
        verify(combo.implicitHeight >= 40)
    }

    function test_button_variants() {
        button.primary = true
        compare(button.primary, true)

        button.primary = false
        compare(button.primary, false)

        button.destructive = true
        compare(button.destructive, true)

        button.destructive = false
    }

    function test_status_contract() {
        compare(
            status.labelForState("waiting"),
            "Wartet"
        )
    }

    function test_user_list_uses_whole_rows() {
        chooser.compactMode = false
        wait(0)

        compare(
            chooser.accountCount,
            3
        )

        compare(
            chooser.visibleRowCount,
            3
        )

        compare(
            chooser.listViewportHeight,
            158
        )

        chooser.compactMode = true
        wait(0)

        compare(
            chooser.visibleRowCount,
            2
        )

        compare(
            chooser.listViewportHeight,
            99
        )

        chooser.compactMode = false
    }
}
