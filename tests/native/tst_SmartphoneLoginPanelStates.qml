// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    name: "SmartphoneLoginPanelStates"

    // A minimal stand-in exposing only what SmartphoneLoginPanel's
    // showQrArea/showConfirmedArea actually read.
    QtObject {
        id: fakeController

        property string state: "starting"
        property string errorKind: ""
        property string connectionState: "ready"
        property string statusText: ""
        property string targetUsername: "visual-user"
        property string identitySource: "local"
        property string identityIconSource: ""
        property string qrPath: ""
        property string verificationUri: ""
        property string userCode: ""
        property int remainingSeconds: 0
        property int totalSecondsForFlow: 0
        property int retryCooldownRemaining: 0
        property bool fido2Wired: false
    }

    Native.SmartphoneLoginPanel {
        id: panel
        controller: fakeController
    }

    // v2.14.0: the QR/device-code view and the "confirmed" view are
    // two distinct sub-views of the same grouped area and must never
    // both be true at once - showing the still-scannable QR code
    // alongside "Bestätigt"/"Anmeldung läuft…" text would contradict
    // itself. This is exhaustive over every real controller state.
    function test_qr_and_confirmed_are_mutually_exclusive_for_every_state() {
        var states = [
            "starting", "waiting", "approved", "logging_in",
            "denied", "expired", "error", "cancelled", "idle"
        ]

        for (var i = 0; i < states.length; i++) {
            fakeController.state = states[i]

            verify(
                !(panel.showQrArea && panel.showConfirmedArea),
                "state=" + states[i]
                    + " showed QR and confirmed simultaneously"
            )
        }
    }

    function test_qr_area_only_for_starting_and_waiting() {
        fakeController.state = "starting"
        compare(panel.showQrArea, true)

        fakeController.state = "waiting"
        compare(panel.showQrArea, true)

        fakeController.state = "approved"
        compare(panel.showQrArea, false)

        fakeController.state = "logging_in"
        compare(panel.showQrArea, false)
    }

    function test_confirmed_area_only_for_approved_and_logging_in() {
        fakeController.state = "approved"
        compare(panel.showConfirmedArea, true)

        fakeController.state = "logging_in"
        compare(panel.showConfirmedArea, true)

        fakeController.state = "waiting"
        compare(panel.showConfirmedArea, false)

        fakeController.state = "denied"
        compare(panel.showConfirmedArea, false)
    }

    function test_neither_area_shown_for_terminal_states() {
        var terminal = ["denied", "expired", "error", "cancelled"]

        for (var i = 0; i < terminal.length; i++) {
            fakeController.state = terminal[i]

            compare(panel.showQrArea, false)
            compare(panel.showConfirmedArea, false)
        }
    }

    // v2.14.0 security/UX correction: "approved" is still a real, safe
    // cancel window (SmartphoneFlowController.cancelCurrent() there
    // genuinely stops the pending login handoff - see
    // tst_SmartphoneFlowController.qml's
    // test_cancel_during_approved_prevents_login_handoff). Only
    // "logging_in" - once sddm.login() has already been called and
    // cannot be recalled - must not offer a close/cancel action that
    // would be a false claim.
    function test_close_is_safe_to_offer_except_during_logging_in() {
        var states = [
            "starting", "waiting", "approved",
            "denied", "expired", "error", "cancelled", "idle"
        ]

        for (var i = 0; i < states.length; i++) {
            fakeController.state = states[i]

            verify(
                panel.closeIsSafeToOffer,
                "state=" + states[i]
                    + " incorrectly blocked close/cancel"
            )
        }

        fakeController.state = "logging_in"

        compare(panel.closeIsSafeToOffer, false)
    }
}
