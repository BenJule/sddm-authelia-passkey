// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as QQC2
import QtQuick.Layouts
import "../../../../theme/native/components"

Item {
    id: root
    width: Screen.width
    height: Screen.height

    property string stateName:
        typeof config !== "undefined"
            ? config.stringValue("visual_state")
            : "idle"

    property bool panelOpen:
        !["idle", "password", "invalid_branding_asset",
          "long_branding", "no_avatar", "smartphone_unreachable",
          "fido2_available", "mechanism_selector_password",
          "mechanism_selector_eidp",
          "mechanism_selector_eidp_unavailable"].includes(stateName)

    // v2.13.0: which mechanism's own content area is shown - mirrors
    // Main.qml's MechanismSelector-driven selectedMechanism. Normally
    // derived from panelOpen (a live smartphone flow implies eidp was
    // selected to reach it), except mechanism_selector_eidp, which
    // exists specifically to show eidp selected/active *before* the
    // panel has been opened.
    property string selectedMechanism:
        stateName === "mechanism_selector_eidp"
            ? "eidp"
            : panelOpen
                ? "eidp"
                : "password"

    ListModel {
        id: users
        ListElement { name: "visual-user"; realName: "Visual User"; icon: "" }
        ListElement { name: "visual-admin"; realName: "Visual Admin"; icon: "" }
    }

    QtObject {
        id: controller

        property string state:
            stateName === "starting" ? "starting"
            : ["waiting", "alternate_code", "directory_account"].includes(stateName) ? "waiting"
            : stateName === "approved" ? "approved"
            : stateName === "logging_in" ? "logging_in"
            : stateName === "denied" ? "denied"
            : stateName === "expired" ? "expired"
            : ["rate_limited", "offline"].includes(stateName) ? "error"
            : "idle"

        property string connectionState:
            stateName === "offline" ? "offline"
            : stateName === "rate_limited" ? "rate_limited"
            : ["starting", "waiting", "alternate_code", "directory_account"].includes(stateName)
                ? "waiting"
                : "ready"

        property string errorKind:
            stateName === "offline" ? "offline"
            : stateName === "rate_limited" ? "provider_rate_limited"
            : stateName === "denied" ? "denied"
            : stateName === "expired" ? "expired"
            : ""

        property string statusText:
            stateName === "offline"
                ? "Der Anmeldedienst ist derzeit nicht erreichbar."
            : stateName === "rate_limited"
                ? "Der Anmeldedienst ist derzeit ausgelastet."
            : stateName === "denied"
                ? "Die Smartphone-Anmeldung wurde nicht bestätigt."
            : stateName === "expired"
                ? "Der Anmeldecode ist abgelaufen."
            : stateName === "approved"
                ? "Bestätigung erhalten."
            : stateName === "logging_in"
                ? "Anmeldung wird abgeschlossen…"
            : stateName === "starting"
                ? "Anmeldung wird vorbereitet…"
            : "Scannen Sie den QR-Code und bestätigen Sie die Anmeldung."

        property string targetUsername:
            stateName === "directory_account"
                ? "visual-directory-user"
                : "visual-user"

        property int targetSessionIndex: 0
        property string resolvedUsername: ""
        property string identityDisplayName: "Visual User"

        property string identitySource:
            stateName === "directory_account"
                ? "directory"
                : "local"

        property string identityIconSource: ""
        property string qrPath: ""
        property string verificationUri:
            stateName === "alternate_code"
                ? "https://example.invalid/device"
                : ""

        property string userCode:
            panelOpen ? "VISUAL-1234" : ""

        property int remainingSeconds: 241
        property int totalSecondsForFlow: 300

        property int retryAfterSeconds: 0
        property int retryCooldownRemaining:
            stateName === "rate_limited" ? 7 : 0

        // v2.9.0 capability-driven mechanism offering (see
        // docs/mechanism-selection.md) - mirrored here only for the two
        // dedicated states below; every other state keeps the same
        // oidcReady=true/fido2Wired=false defaults it always rendered
        // with, so none of the 16 pre-existing baselines change.
        property bool oidcReady:
            stateName !== "smartphone_unreachable"
            && stateName !== "mechanism_selector_eidp_unavailable"
        property bool fido2Wired:
            stateName === "fido2_available"
    }

    MechanismModel {
        id: mechanismModel
        smartphoneFlow: controller
    }

    Rectangle {
        anchors.fill: parent
        color: "#071018"

        gradient: Gradient {
            GradientStop { position: 0; color: "#142634" }
            GradientStop { position: 1; color: "#071018" }
        }
    }

    Image {
        id: invalidBrandLogo

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 30
        anchors.topMargin: 30

        width: 30
        height: 30

        visible:
            root.stateName === "invalid_branding_asset"

        source:
            visible
                ? "file:///tmp/v115-missing-brand-logo.png"
                : ""
    }

    QQC2.Label {
        anchors.left:
            invalidBrandLogo.visible
                ? invalidBrandLogo.right
                : parent.left

        anchors.leftMargin:
            invalidBrandLogo.visible
                ? 9
                : 30

        anchors.top: parent.top
        anchors.topMargin: 30

        width: 520
        elide: Text.ElideRight

        text:
            stateName === "long_branding"
                ? "Example Enterprise Identity & Access Visual Regression Laboratory"
                : "SDDM Authelia Passkey"

        color: "#617589"
        font.pixelSize: 12
        font.bold: true
    }

    Rectangle {
        id: card
        width: 480
        height: 540
        radius: 22

        x: panelOpen ? 45 : (root.width - width) / 2
        anchors.verticalCenter: parent.verticalCenter

        color: "#101820"
        border.color: "#293440"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                QQC2.Label {
                    Layout.fillWidth: true
                    text: "Willkommen"
                    color: "#f4f8fc"
                    font.pixelSize: 26
                    font.bold: true
                }

                QQC2.Label {
                    text: "12:34"
                    color: "#eef4fa"
                    font.pixelSize: 22
                }
            }

            QQC2.Label {
                text: "Freitag, 11. September 2026"
                color: "#667b90"
                font.pixelSize: 9
            }

            UserChooser {
                Layout.fillWidth: true
                userModelSource: users
                initialIndex: 0
                showAvatar: stateName !== "no_avatar"
            }

            QQC2.Label {
                text: "Anmeldemethode"
                color: "#7d8fa2"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: mechanismModel.selectableMechanisms

                    delegate: PolishedButton {
                        required property var modelData

                        Layout.fillWidth: true
                        compact: true
                        text: modelData.displayName
                        primary: root.selectedMechanism === modelData.id
                        enabled: modelData.ready
                    }
                }
            }

            QQC2.Label {
                visible: root.selectedMechanism === "password"
                text: "Passwort"
                color: "#7d8fa2"
            }

            PolishedTextField {
                Layout.fillWidth: true
                visible: root.selectedMechanism === "password"
                placeholderText: "Passwort eingeben"
                echoMode: TextInput.Password
                enabled: mechanismModel.mechanism("password").ready
            }

            QQC2.Label {
                visible:
                    stateName === "password"
                    && root.selectedMechanism === "password"
                text: "Anmeldung fehlgeschlagen. Bitte Eingabe prüfen."
                color: "#ff8585"
            }

            PolishedButton {
                Layout.fillWidth: true
                visible: root.selectedMechanism === "password"
                text: "Mit Passwort anmelden"
                enabled: mechanismModel.mechanism("password").ready
            }

            PolishedButton {
                Layout.fillWidth: true
                primary: true
                visible: root.selectedMechanism === "eidp"
                text: "Mit Smartphone anmelden"
                enabled: mechanismModel.mechanism("eidp").ready
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible:
                    root.selectedMechanism === "eidp"
                    && !mechanismModel.mechanism("eidp").ready
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: mechanismModel.mechanism("eidp").statusHint
                color: "#a2aebb"
                font.pixelSize: 9
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: mechanismModel.mechanism("passkey").ready
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: mechanismModel.mechanism("passkey").statusHint
                color: "#5fb88a"
                font.pixelSize: 9
            }

            QQC2.Label {
                text: "Sitzung"
                color: "#7d8fa2"
            }

            PolishedComboBox {
                Layout.fillWidth: true
                model: ["Plasma (Wayland)", "Plasma (X11)"]
            }
        }
    }

    SmartphoneLoginPanel {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 34

        width: 430

        open: panelOpen
        controller: controller

        compactLayout: true
        qrSide: 145
        modalLayout: false

        showAvatar:
            stateName !== "no_avatar"
    }
}
