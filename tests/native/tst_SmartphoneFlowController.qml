import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    id: testCase

    name: "SmartphoneFlowController"

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

    function init() {
        flow = flowFactory.createObject(testCase)
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

    function prepareWaiting(username, session, generation) {
        flow.flowGeneration = generation
        flow.targetUsername = username
        flow.targetSessionIndex = 3
        flow.sessionId = session
        flow.state = "waiting"
        flow.connectionState = "waiting"
        flow.loginEmitted = false
        flow.resolvedUsername = ""
    }

    function test_stale_generation_is_ignored() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "approved",
                username: "alice"
            },
            9,
            "session-a"
        )

        compare(flow.state, "waiting")
        compare(loginSpy.count, 0)
    }

    function test_stale_session_is_ignored() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "approved",
                username: "alice"
            },
            10,
            "session-old"
        )

        compare(flow.state, "waiting")
        compare(loginSpy.count, 0)
    }

    function test_exact_username_binding() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "approved",
                username: "bob"
            },
            10,
            "session-a"
        )

        compare(flow.state, "error")
        compare(flow.errorKind, "identity_mismatch")
        compare(loginSpy.count, 0)
    }

    function test_approved_login_emitted_once() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "approved",
                username: "alice"
            },
            10,
            "session-a"
        )

        tryCompare(flow, "state", "logging_in", 1000)
        compare(loginSpy.count, 1)
        compare(flow.targetSessionIndex, 3)

        flow.emitApprovedLogin()
        compare(loginSpy.count, 1)
    }

    function test_rate_limited_pending_is_not_denial() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "pending",
                username: "alice",
                rate_limited: true,
                retry_after_seconds: 23,
                expires_at: Math.floor(Date.now() / 1000) + 90
            },
            10,
            "session-a"
        )

        compare(flow.state, "waiting")
        compare(flow.connectionState, "rate_limited")
        compare(flow.retryAfterSeconds, 23)
    }

    function test_expiry_is_retryable_terminal_state() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "error",
                error: "expired"
            },
            10,
            "session-a"
        )

        compare(flow.state, "expired")
        compare(flow.errorKind, "expired")
        verify(flow.retryCooldownRemaining >= 0)
    }

    function test_provider_unavailable_is_not_expiry() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "error",
                error: "temporarily_unavailable"
            },
            10,
            "session-a"
        )

        compare(flow.state, "error")
        compare(flow.errorKind, "provider_unavailable")
        compare(flow.connectionState, "error")
        compare(
            flow.statusText.indexOf("temporarily_unavailable"),
            -1
        )
    }

    function test_terminal_provider_rate_limit_is_not_expiry() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "error",
                error: "rate_limited",
                retry_after_seconds: 23
            },
            10,
            "session-a"
        )

        compare(flow.state, "error")
        compare(flow.errorKind, "provider_rate_limited")
        compare(flow.connectionState, "rate_limited")
    }

    function test_missing_status_is_malformed_terminal_state() {
        prepareWaiting("alice", "", 10)

        flow.applyStatus(
            {
                username: "alice"
            },
            10,
            ""
        )

        compare(flow.state, "error")
        compare(flow.errorKind, "malformed_status")
        compare(flow.connectionState, "error")
        compare(loginSpy.count, 0)
    }

    function test_login_failure_invalidates_approved_flow() {
        prepareWaiting("alice", "session-a", 10)

        flow.applyStatus(
            {
                status: "approved",
                username: "alice"
            },
            10,
            "session-a"
        )

        tryCompare(flow, "state", "logging_in", 1000)
        compare(loginSpy.count, 1)

        var generation = flow.flowGeneration

        flow.loginFailed()

        compare(flow.flowGeneration, generation + 1)
        compare(flow.state, "error")
        compare(flow.errorKind, "login_failed")
        compare(flow.connectionState, "ready")
        compare(flow.sessionId, "")
        compare(flow.resolvedUsername, "")
        compare(flow.loginEmitted, false)
        compare(flow.targetUsername, "alice")
    }

    function test_cancel_invalidates_generation() {
        prepareWaiting("alice", "", 10)

        flow.cancelCurrent(true)

        compare(flow.state, "cancelled")
        compare(flow.flowGeneration, 11)

        flow.applyStatus(
            {
                status: "approved",
                username: "alice"
            },
            10,
            ""
        )

        compare(flow.state, "cancelled")
        compare(loginSpy.count, 0)
    }
}
