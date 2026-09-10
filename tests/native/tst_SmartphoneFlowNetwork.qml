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
