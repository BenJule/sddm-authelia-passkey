#!/usr/bin/env python3
from pathlib import Path


def read(path):
    return Path(path).read_text()


def require(path, *tokens):
    text = read(path)

    for token in tokens:
        if token not in text:
            raise RuntimeError(
                f"{path}: missing accessibility contract token: {token}"
            )

    print(f"ACCESSIBILITY_CONTRACT={path}=PASS")


require(
    "theme/native/Main.qml",
    "Accessible.role: Accessible.Pane",
    "Accessible.passwordEdit: true",
    "Accessible.defaultButton: true",
    "Accessible.role: Accessible.AlertMessage",
    'Accessible.name: qsTr("Sitzung")',
    'Accessible.name: qsTr("Tastaturlayout")',
    "modalLayout: responsiveMetrics.overlayLayout",
)

require(
    "theme/native/components/UserAvatar.qml",
    "Accessible.ignored: true",
)

require(
    "theme/native/components/ConnectionStatus.qml",
    "Accessible.role: Accessible.StatusBar",
    'qsTr("Verbindungsstatus: %1")',
)

require(
    "theme/native/components/CountdownView.qml",
    "Accessible.role: Accessible.ProgressBar",
    'Accessible.name: qsTr("Verbleibende Zeit")',
    "Accessible.description:",
)

require(
    "theme/native/components/PowerActionsRow.qml",
    "Accessible.role: Accessible.ToolBar",
    'Accessible.name: qsTr("Systemaktionen")',
)

require(
    "theme/native/components/UserChooser.qml",
    "Accessible.role: Accessible.Pane",
    "Accessible.role: Accessible.List",
    "Accessible.role: Accessible.ListItem",
    "Accessible.name: accountName",
    "Accessible.selected: highlighted",
    "Accessible.focusable: true",
    "Accessible.onPressAction:",
    'Accessible.name: qsTr("Benutzername")',
    "userList.currentItem.forceActiveFocus()",
)

require(
    "theme/native/components/SmartphoneLoginPanel.qml",
    "Accessible.Dialog",
    "Accessible.Pane",
    'Accessible.name: qsTr("Smartphone-Login")',
    "Accessible.role: Accessible.Graphic",
    'qsTr("QR-Code für die Smartphone-Anmeldung")',
    "Accessible.AlertMessage",
    'qsTr("Gerätecode: %1")',
    "closeButton.forceActiveFocus()",
)

native_files = [
    Path("theme/native/Main.qml"),
    *Path("theme/native/components").glob("*.qml"),
]

accessible_count = sum(
    p.read_text().count("Accessible.")
    for p in native_files
)

print(f"NATIVE_ACCESSIBLE_PROPERTY_COUNT={accessible_count}")

if accessible_count < 25:
    raise RuntimeError(
        "Native accessibility surface unexpectedly small"
    )

print("NATIVE_ACCESSIBILITY_CONTRACT=PASS")
