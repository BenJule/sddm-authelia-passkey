#!/usr/bin/env python3

from pathlib import Path

root = Path(__file__).resolve().parents[2]

controller = (
    root
    / "theme/native/components/SmartphoneFlowController.qml"
).read_text(encoding="utf-8")

panel = (
    root
    / "theme/native/components/SmartphoneLoginPanel.qml"
).read_text(encoding="utf-8")

main = (
    root
    / "theme/native/Main.qml"
).read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


for token in (
    'errorKind = "provider_unavailable"',
    'errorKind = "provider_rate_limited"',
    'errorKind = "malformed_status"',
    'errorKind = "login_failed"',
    'root.flowGeneration += 1',
    'root.cancelSession(pollingSession)',
):
    require(
        token in controller,
        f"missing controller recovery contract: {token}",
    )

require(
    'reason === "temporarily_unavailable") {\n'
    '                root.setExpired' not in controller,
    "temporarily_unavailable must not be presented as expiry",
)

require(
    'reason === "rate_limited") {\n'
    '                root.setExpired' not in controller,
    "terminal rate limit must not be presented as expiry",
)

for token in (
    "readonly property bool qrUnavailable:",
    "readonly property bool retryIsStartFailure:",
    "readonly property string retryButtonText:",
    "Die Passwort-Anmeldung bleibt jederzeit verfügbar.",
):
    require(
        token in panel,
        f"missing presentation recovery contract: {token}",
    )

require(
    "function onLoginFailed()" in main
    and "smartphoneFlow.loginFailed()" in main,
    "SDDM loginFailed must feed the Smartphone recovery controller",
)

for forbidden in (
    "temporarily_unavailable",
    "device authorization request failed",
    "userinfo verification failed",
):
    require(
        forbidden not in panel,
        f"technical provider detail leaked into panel: {forbidden}",
    )

print("NATIVE_FAILURE_RECOVERY_CONTRACT=GREEN")
