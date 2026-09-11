import QtQuick
import QtTest
import "../../theme/native/components" as Native

TestCase {
    id: testCase

    name: "FailureRecoveryPresentation"

    property var controller
    property var panel

    Component {
        id: controllerFactory

        QtObject {
            property string state: "idle"
            property string connectionState: "ready"
            property string errorKind: ""
            property string statusText: ""

            property string targetUsername: "alice"
            property string identitySource: "local"
            property string identityIconSource: ""

            property string qrPath: ""
            property string verificationUri: ""
            property string userCode: ""

            property int totalSecondsForFlow: 0
            property int remainingSeconds: 0
            property int retryCooldownRemaining: 0
        }
    }

    Component {
        id: panelFactory

        Native.SmartphoneLoginPanel {
            width: 620
            height: 680
            open: true
        }
    }

    function init() {
        controller =
            controllerFactory.createObject(testCase)

        verify(controller !== null)

        panel =
            panelFactory.createObject(
                testCase,
                {
                    controller: controller
                }
            )

        verify(panel !== null)
    }

    function cleanup() {
        if (panel) {
            panel.destroy()
            panel = null
        }

        if (controller) {
            controller.destroy()
            controller = null
        }
    }

    function test_missing_qr_uses_alternate_path_copy() {
        controller.state = "waiting"
        controller.statusText =
            "Scannen Sie den QR-Code mit Ihrem Smartphone."
        controller.qrPath = ""
        controller.userCode = "ABCD-EFGH"
        controller.verificationUri =
            "https://example.invalid/device"

        tryCompare(
            panel,
            "qrUnavailable",
            true,
            1000
        )

        verify(
            panel.effectiveStatusText.indexOf(
                "QR-Code ist nicht verfügbar"
            ) >= 0
        )

        verify(
            panel.effectiveStatusText.indexOf(
                "Gerätecode"
            ) >= 0
        )
    }

    function test_start_throttle_is_labelled_as_client_retry() {
        controller.state = "error"
        controller.errorKind = "start_rate_limited"
        controller.retryCooldownRemaining = 7

        compare(panel.canRetry, true)
        compare(panel.retryIsStartFailure, true)
        compare(
            panel.retryButtonText,
            "Erneut versuchen in 7 s"
        )
    }

    function test_expired_flow_requests_new_code() {
        controller.state = "expired"
        controller.errorKind = "expired"
        controller.retryCooldownRemaining = 2

        compare(panel.canRetry, true)
        compare(panel.retryIsStartFailure, false)
        compare(
            panel.retryButtonText,
            "Neuer Code in 2 s"
        )
    }

    function test_not_authorized_does_not_offer_retry() {
        controller.state = "error"
        controller.errorKind = "not_authorized"

        compare(panel.canRetry, false)
    }

    function test_login_failure_is_recoverable() {
        controller.state = "error"
        controller.errorKind = "login_failed"
        controller.retryCooldownRemaining = 0

        compare(panel.canRetry, true)
        compare(
            panel.retryButtonText,
            "Neuen Code anfordern"
        )
    }
}
