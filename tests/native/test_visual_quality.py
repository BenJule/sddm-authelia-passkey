#!/usr/bin/env python3

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "theme" / "native"
COMP = NATIVE / "components"

required = [
    COMP / "PolishedButton.qml",
    COMP / "PolishedTextField.qml",
    COMP / "PolishedComboBox.qml",
    COMP / "ResponsiveMetrics.qml",
    COMP / "UserChooser.qml",
    COMP / "SmartphoneLoginPanel.qml",
    COMP / "PowerActionsRow.qml",
    COMP / "ConnectionStatus.qml",
]

for path in required:
    if not path.is_file():
        raise SystemExit(
            f"missing visual component: {path}"
        )

main = (NATIVE / "Main.qml").read_text()
chooser = (COMP / "UserChooser.qml").read_text()
panel = (COMP / "SmartphoneLoginPanel.qml").read_text()
power = (COMP / "PowerActionsRow.qml").read_text()

checks = {
    "v1.14 marker":
        "Native v1.14.0" in main,

    "German date":
        'Qt.locale("de_DE")' in main,

    "polished password":
        "PolishedTextField" in main,

    "polished combo":
        "PolishedComboBox" in main,

    "smartphone primary":
        "Mit Smartphone anmelden" in main,

    "username primary":
        "accountDelegate.accountName" in chooser,

    "styled smartphone":
        "PolishedButton" in panel,

    "styled power":
        "PolishedButton" in power,

    "responsive sidebar":
        "responsiveMetrics.overlayLayout" in main,

    "whole account rows":
        "listViewportHeight" in chooser
        and "visibleRowCount" in chooser,

    "neutral smartphone account metadata":
        "accountKindLabel" in panel,

    "unauthorized account is not retryable":
        'controller.errorKind !== "not_authorized"' in panel,

    "QR section hides in terminal errors":
        "showQrArea" in panel,
}

failed = [
    name
    for name, value in checks.items()
    if not value
]

if failed:
    raise SystemExit(
        "visual contract failed: "
        + ", ".join(failed)
    )

for path, text in (
    ("Main.qml", main),
    ("UserChooser.qml", chooser),
    ("SmartphoneLoginPanel.qml", panel),
    ("PowerActionsRow.qml", power),
):
    if "QQC2.Button {" in text:
        raise SystemExit(
            f"{path}: raw QQC2.Button remains"
        )

print("NATIVE_VISUAL_QUALITY_STATIC=GREEN")
print("RAW_QT_BUTTON_SURFACES=NONE")
print("USERNAME_PRIMARY=YES")
print("GERMAN_DATE=YES")
print("RESPONSIVE_LAYOUT=PRESERVED")
