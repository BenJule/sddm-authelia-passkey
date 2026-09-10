#!/usr/bin/env python3

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "theme" / "native"
COMPONENTS = NATIVE / "components"

required = [
    NATIVE / "Main.qml",
    COMPONENTS / "UserChooser.qml",
    COMPONENTS / "SmartphoneFlowController.qml",
    COMPONENTS / "SmartphoneLoginPanel.qml",
    COMPONENTS / "ConnectionStatus.qml",
    COMPONENTS / "CountdownView.qml",
    COMPONENTS / "UserAvatar.qml",
    COMPONENTS / "PowerActionsRow.qml",
]

for path in required:
    if not path.is_file():
        raise SystemExit(f"missing native component: {path}")

preview = COMPONENTS / "SmartphoneLoginPreview.qml"
if preview.exists():
    raise SystemExit("v1.9 preview component still exists")

sources = {
    path: path.read_text(encoding="utf-8")
    for path in required
}

controller = sources[COMPONENTS / "SmartphoneFlowController.qml"]
main = sources[NATIVE / "Main.qml"]
chooser = sources[COMPONENTS / "UserChooser.qml"]
panel = sources[COMPONENTS / "SmartphoneLoginPanel.qml"]

for endpoint in (
    "/start?username=",
    "/identity?username=",
    "/status?session_id=",
    "/cancel?session_id=",
):
    if endpoint not in controller:
        raise SystemExit(f"missing broker endpoint use: {endpoint}")

if "http://127.0.0.1:7899" not in controller:
    raise SystemExit("default localhost broker origin missing")

all_qml = "\n".join(sources.values())

urls = re.findall(r'https?://[^"\'\s]+', all_qml)
bad_urls = [
    url for url in urls
    if not url.startswith("http://127.0.0.1:7899")
]

if bad_urls:
    raise SystemExit(
        "non-local HTTP URL found in native QML: "
        + ", ".join(sorted(set(bad_urls)))
    )

for forbidden in (
    "/api/oidc/",
    "ldap://",
    "ldaps://",
):
    if forbidden.lower() in all_qml.lower():
        raise SystemExit(
            f"direct provider/directory reference in native QML: {forbidden}"
        )

checks = {
    "user ListView": "ListView {" in chooser,
    "manual username": "beginManualEntry" in chooser,
    "password sddm login":
        "sddm.login(" in main
        and "passwordField.text" in main,
    "smartphone PAM handoff":
        'sddm.login(username, "", sessionIndex)' in main,
    "immutable target username":
        "targetUsername" in controller,
    "immutable session index":
        "targetSessionIndex" in controller,
    "generation isolation":
        "flowGeneration" in controller,
    "session isolation":
        "pollingSession !== root.sessionId" in controller,
    "exact approved username":
        "response.username !== root.targetUsername" in controller,
    "single login emission":
        "loginEmitted" in controller,
    "explicit cancel":
        "cancelCurrent" in controller,
    "retry":
        "retryFlow" in controller,
    "countdown":
        "expiresAt" in controller
        and "remainingSeconds" in controller,
    "rate limited":
        'connectionState = "rate_limited"' in controller,
    "offline":
        'connectionState = "offline"' in controller,
    "QR presentation":
        "qrPath" in panel,
    "device code":
        "userCode" in panel,
    "identity":
        "identityDisplayName" in panel,
    "directory indication":
        "Verzeichniskonto" in panel,
    "password fallback":
        "passwordRequested" in panel,
    "connection status":
        "ConnectionStatus" in panel,
    "countdown view":
        "CountdownView" in panel,
}

failed = [name for name, ok in checks.items() if not ok]

if failed:
    raise SystemExit(
        "native feature parity contract failed: "
        + ", ".join(failed)
    )

print("NATIVE_FEATURE_PARITY_STATIC=GREEN")
print("BROKER_ORIGIN=LOCALHOST_ONLY")
print("AUTH_LOGIC_IN_QML=NO")
