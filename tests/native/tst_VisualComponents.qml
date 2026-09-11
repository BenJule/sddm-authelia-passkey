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
}
