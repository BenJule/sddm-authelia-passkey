// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    name: "MechanismModel"

    Native.SmartphoneFlowController {
        id: flow
    }

    Native.MechanismModel {
        id: model
        smartphoneFlow: flow
    }

    Native.MechanismModel {
        id: lonelyModel
    }

    function init() {
        flow.oidcReady = true
        flow.fido2Wired = false
    }

    function test_all_four_mechanisms_present() {
        compare(model.mechanisms.length, 4)
        verify(model.mechanism("password") !== null)
        verify(model.mechanism("eidp") !== null)
        verify(model.mechanism("passkey") !== null)
        verify(model.mechanism("smartcard") !== null)
    }

    function test_unknown_mechanism_returns_null() {
        compare(model.mechanism("does-not-exist"), null)
    }

    function test_password_always_available_and_ready() {
        var m = model.mechanism("password")
        compare(m.kind, "actionable")
        compare(m.available, true)
        compare(m.ready, true)
        compare(m.statusHint, "")
    }

    function test_smartcard_never_available() {
        var m = model.mechanism("smartcard")
        compare(m.available, false)
        compare(m.ready, false)
        compare(m.statusHint, "")
    }

    function test_eidp_tracks_oidc_ready() {
        flow.oidcReady = true
        compare(model.mechanism("eidp").ready, true)
        compare(model.mechanism("eidp").statusHint, "")

        flow.oidcReady = false
        compare(model.mechanism("eidp").ready, false)
        verify(model.mechanism("eidp").statusHint.length > 0)
    }

    function test_passkey_is_ambient_and_tracks_fido2_wired() {
        var m = model.mechanism("passkey")
        compare(m.kind, "ambient")

        flow.fido2Wired = false
        compare(model.mechanism("passkey").available, false)
        compare(model.mechanism("passkey").ready, false)
        compare(model.mechanism("passkey").statusHint, "")

        flow.fido2Wired = true
        compare(model.mechanism("passkey").available, true)
        compare(model.mechanism("passkey").ready, true)
        verify(model.mechanism("passkey").statusHint.length > 0)
    }

    function test_model_never_crashes_without_a_flow() {
        compare(lonelyModel.mechanism("eidp").ready, false)
        compare(lonelyModel.mechanism("passkey").ready, false)
        compare(lonelyModel.mechanism("password").ready, true)
    }
}
