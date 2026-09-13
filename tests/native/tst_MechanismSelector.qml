// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    name: "MechanismSelector"

    // A minimal stand-in for SmartphoneFlowController exposing only
    // what MechanismModel/MechanismSelector actually read - the two
    // capability signals plus the live/cancelCurrent surface, with
    // cancelCurrent spy-able so tests can assert it was (or wasn't)
    // called, exactly once, with the expected argument.
    QtObject {
        id: fakeFlow

        property bool oidcReady: true
        property bool fido2Wired: false
        property bool live: false

        property int cancelCallCount: 0
        property var lastCancelArg: undefined

        function cancelCurrent(showCancelled) {
            cancelCallCount += 1
            lastCancelArg = showCancelled
            live = false
        }
    }

    Native.MechanismModel {
        id: model
        smartphoneFlow: fakeFlow
    }

    Native.MechanismSelector {
        id: selector
        mechanismModel: model
        smartphoneFlow: fakeFlow
    }

    function init() {
        fakeFlow.oidcReady = true
        fakeFlow.fido2Wired = false
        fakeFlow.live = false
        fakeFlow.cancelCallCount = 0
        fakeFlow.lastCancelArg = undefined
        selector.selectedMechanism = "password"
    }

    function test_initial_state_is_password() {
        compare(selector.selectedMechanism, "password")
    }

    function test_selects_eidp_when_ready() {
        selector.selectMechanism("eidp")
        compare(selector.selectedMechanism, "eidp")
    }

    function test_refuses_to_select_eidp_when_not_ready() {
        fakeFlow.oidcReady = false
        selector.selectMechanism("eidp")
        compare(selector.selectedMechanism, "password")
    }

    function test_refuses_unknown_mechanism_id() {
        selector.selectMechanism("does-not-exist")
        compare(selector.selectedMechanism, "password")
    }

    function test_reselecting_current_mechanism_is_a_noop() {
        selector.selectMechanism("password")
        compare(selector.selectedMechanism, "password")
        compare(fakeFlow.cancelCallCount, 0)
    }

    // v2.13.0 spec point 9: switching eidp -> password must cancel a
    // running smartphone flow using the controller's own existing
    // semantics (live/cancelCurrent(false) - never a second/parallel
    // cancellation mechanism).
    function test_switching_away_from_live_eidp_cancels_the_flow() {
        selector.selectMechanism("eidp")
        fakeFlow.live = true

        selector.selectMechanism("password")

        compare(selector.selectedMechanism, "password")
        compare(fakeFlow.cancelCallCount, 1)
        compare(fakeFlow.lastCancelArg, false)
    }

    function test_switching_away_from_idle_eidp_does_not_cancel_anything() {
        selector.selectMechanism("eidp")
        fakeFlow.live = false

        selector.selectMechanism("password")

        compare(selector.selectedMechanism, "password")
        compare(fakeFlow.cancelCallCount, 0)
    }

    // v2.13.0 spec point 3: eidp becoming unavailable while actively
    // selected must safely fail closed back to password.
    function test_reconsider_falls_back_when_selected_mechanism_becomes_unready() {
        selector.selectMechanism("eidp")
        fakeFlow.oidcReady = false

        selector.reconsiderCurrentMechanism()

        compare(selector.selectedMechanism, "password")
    }

    function test_reconsider_cancels_a_live_flow_on_fallback() {
        selector.selectMechanism("eidp")
        fakeFlow.live = true
        fakeFlow.oidcReady = false

        selector.reconsiderCurrentMechanism()

        compare(selector.selectedMechanism, "password")
        compare(fakeFlow.cancelCallCount, 1)
        compare(fakeFlow.lastCancelArg, false)
    }

    function test_reconsider_is_a_noop_while_still_ready() {
        selector.selectMechanism("eidp")

        selector.reconsiderCurrentMechanism()

        compare(selector.selectedMechanism, "eidp")
        compare(fakeFlow.cancelCallCount, 0)
    }

    function test_return_to_password_is_a_noop_when_already_password() {
        selector.returnToPassword()
        compare(selector.selectedMechanism, "password")
        compare(fakeFlow.cancelCallCount, 0)
    }

    function test_return_to_password_cancels_a_live_flow() {
        selector.selectMechanism("eidp")
        fakeFlow.live = true

        selector.returnToPassword()

        compare(selector.selectedMechanism, "password")
        compare(fakeFlow.cancelCallCount, 1)
        compare(fakeFlow.lastCancelArg, false)
    }

    // v2.14.0: eidp recovering from unready must never pull the user
    // back to it automatically - only a real, explicit selectMechanism()
    // call (a user action) may select eidp again. Losing eidp already
    // falls back to password (tested above); this guards the opposite
    // direction never auto-switches.
    function test_eidp_recovery_does_not_auto_switch_back() {
        selector.selectMechanism("eidp")
        fakeFlow.oidcReady = false
        selector.reconsiderCurrentMechanism()
        compare(selector.selectedMechanism, "password")

        fakeFlow.oidcReady = true
        selector.reconsiderCurrentMechanism()

        compare(selector.selectedMechanism, "password")
    }
}
