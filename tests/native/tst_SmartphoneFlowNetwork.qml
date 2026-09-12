import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    id: testCase

    name: "SmartphoneFlowNetwork"

    property var flow

    Component {
        id: flowFactory

        Native.SmartphoneFlowController {
            pollIntervalMs: 50
            approvalDelayMs: 10
            requestTimeoutMs: 200
        }
    }

    SignalSpy {
        id: loginSpy
        signalName: "loginApproved"
    }

    function makeFlow(origin) {
        flow = flowFactory.createObject(
            testCase,
            {
                brokerOrigin: origin
            }
        )

        verify(flow !== null)

        loginSpy.target = flow
        loginSpy.clear()
    }

    function cleanup() {
        loginSpy.target = null

        if (flow) {
            flow.destroy()
            flow = null
        }
    }

    function test_real_mock_contract_approval() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "alice",
                "Alice",
                "",
                2
            )
        )

        tryCompare(flow, "state", "logging_in", 4000)

        compare(loginSpy.count, 1)
        compare(flow.targetUsername, "alice")
        compare(flow.targetSessionIndex, 2)
        compare(flow.identitySource, "nss")
        verify(flow.userCode.length > 0)
        verify(flow.verificationUri.length > 0)
        verify(flow.qrPath.length > 0)
        verify(flow.totalSecondsForFlow > 0)
    }

    function test_mock_expiry() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "expire",
                "Expire",
                "",
                0
            )
        )

        tryCompare(flow, "state", "expired", 3000)
        compare(loginSpy.count, 0)
    }

    function test_mock_identity_mismatch_fails_closed() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "mismatch",
                "Mismatch",
                "",
                0
            )
        )

        tryCompare(flow, "state", "error", 3000)

        compare(flow.errorKind, "identity_mismatch")
        compare(loginSpy.count, 0)
    }

    function test_start_403_is_not_authorized() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "forbidden",
                "Forbidden",
                "",
                0
            )
        )

        tryCompare(flow, "state", "error", 2000)
        compare(flow.errorKind, "not_authorized")
        compare(flow.connectionState, "ready")
        compare(loginSpy.count, 0)
    }

    function test_start_429_is_service_throttle() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "throttle",
                "Throttle",
                "",
                0
            )
        )

        tryCompare(flow, "state", "error", 2000)
        compare(flow.connectionState, "rate_limited")
        compare(flow.errorKind, "start_rate_limited")
        compare(loginSpy.count, 0)
    }

    function test_offline_broker() {
        makeFlow("http://127.0.0.1:17998")

        verify(
            flow.startFlow(
                "alice",
                "Alice",
                "",
                0
            )
        )

        tryCompare(flow, "state", "error", 3000)
        compare(flow.connectionState, "offline")
        compare(loginSpy.count, 0)
    }

    function test_mock_denied() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "denied",
                "Denied",
                "",
                0
            )
        )

        tryCompare(flow, "state", "denied", 3000)
        compare(flow.errorKind, "denied")
        compare(flow.connectionState, "ready")
        compare(loginSpy.count, 0)
    }

    function test_mock_provider_unavailable() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "unavailable",
                "Unavailable",
                "",
                0
            )
        )

        tryCompare(flow, "state", "error", 3000)
        compare(flow.errorKind, "provider_unavailable")
        compare(flow.connectionState, "error")
        compare(loginSpy.count, 0)
    }

    function test_mock_missing_status_is_malformed() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "missing-status",
                "Missing",
                "",
                0
            )
        )

        tryCompare(flow, "state", "error", 3000)
        compare(flow.errorKind, "malformed_status")
        compare(loginSpy.count, 0)
    }

    function test_malformed_poll_can_recover_without_denial() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "malformed",
                "Malformed",
                "",
                1
            )
        )

        tryCompare(flow, "state", "logging_in", 4000)
        compare(flow.targetUsername, "malformed")
        compare(loginSpy.count, 1)
    }

    function test_qrless_flow_keeps_alternate_path() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "qrless",
                "QR Less",
                "",
                0
            )
        )

        tryCompare(flow, "state", "waiting", 2000)

        tryVerify(
            function() {
                return flow.userCode.length > 0
                    && flow.verificationUri.length > 0
            },
            2000
        )

        compare(flow.qrPath, "")
        compare(loginSpy.count, 0)

        flow.cancelCurrent(false)
    }

    function test_hung_start_times_out_instead_of_blocking_forever() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "hang",
                "Hang",
                "",
                0
            )
        )

        // requestTimeoutMs is 200; the mock broker holds the connection
        // for 5000ms before ever answering. If armRequestTimeout()
        // regressed (e.g. no longer wired to xhr.send()), this would
        // stay "starting" until the mock's real response and fail the
        // tryCompare well before that.
        tryCompare(flow, "connectionState", "offline", 2000)
        compare(flow.errorKind, "offline")
        compare(loginSpy.count, 0)

        // The late response arrives ~4800ms after the timeout already
        // fired and this test's flow moved to a new generation; it must
        // never be treated as belonging to the current flow.
        wait(5200)
        compare(loginSpy.count, 0)
    }

    function test_capabilities_are_fetched_from_broker() {
        makeFlow("http://127.0.0.1:17899")

        // capabilitiesTimer has triggeredOnStart: true, so this needs no
        // flow to be started at all - purely a pre-login, informational
        // fact independent of any username/session (v2.4.0).
        tryCompare(flow, "fido2Wired", true, 2000)
        compare(flow.oidcReady, true)
    }

    function test_explicit_cancel() {
        makeFlow("http://127.0.0.1:17899")

        verify(
            flow.startFlow(
                "cancel-user",
                "Cancel",
                "",
                0
            )
        )

        tryCompare(flow, "state", "waiting", 2000)

        var oldGeneration = flow.flowGeneration

        flow.cancelCurrent(true)

        compare(flow.state, "cancelled")
        compare(
            flow.flowGeneration,
            oldGeneration + 1
        )

        wait(250)
        compare(loginSpy.count, 0)
    }
}
