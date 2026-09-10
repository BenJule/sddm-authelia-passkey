// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

Rectangle {
    id: root

    property var controller
    property bool open: false

    signal closeRequested()
    signal cancelRequested()
    signal retryRequested()
    signal passwordRequested()

    visible: open
    focus: open

    radius: 16
    color: Qt.rgba(0.07, 0.09, 0.12, 0.98)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.16)

    Keys.onEscapePressed: {
        if (root.controller
                && root.controller.state !== "approved"
                && root.controller.state !== "logging_in") {
            root.closeRequested()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 11

        RowLayout {
            Layout.fillWidth: true

            QQC2.Label {
                Layout.fillWidth: true
                text: qsTr("Smartphone-Login")
                color: "white"
                font.pixelSize: 18
                font.bold: true
            }

            QQC2.ToolButton {
                text: qsTr("Schliessen")
                enabled:
                    !root.controller
                    || (
                        root.controller.state !== "approved"
                        && root.controller.state !== "logging_in"
                    )
                onClicked: root.closeRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            UserAvatar {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                iconSource:
                    root.controller
                        ? root.controller.identityIconSource
                        : ""
                label:
                    root.controller
                        ? (
                            root.controller.identityDisplayName.length > 0
                                ? root.controller.identityDisplayName
                                : root.controller.targetUsername
                        )
                        : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                QQC2.Label {
                    Layout.fillWidth: true
                    text:
                        root.controller
                            ? (
                                root.controller.identityDisplayName.length > 0
                                    ? root.controller.identityDisplayName
                                    : root.controller.targetUsername
                            )
                            : ""
                    color: "white"
                    font.bold: true
                    elide: Text.ElideRight
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text:
                        root.controller
                            ? root.controller.targetUsername
                            : ""
                    color: "white"
                    opacity: 0.60
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                QQC2.Label {
                    visible:
                        root.controller
                        && root.controller.identitySource.length > 0
                    text:
                        root.controller
                        && root.controller.identitySource === "nss"
                            ? qsTr("Verzeichniskonto")
                            : qsTr("Lokales Konto")
                    color: "white"
                    opacity: 0.70
                    font.pixelSize: 10
                }
            }

            ConnectionStatus {
                connectionState:
                    root.controller
                        ? root.controller.connectionState
                        : "ready"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            QQC2.BusyIndicator {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                running:
                    root.controller
                    && (
                        root.controller.state === "starting"
                        || root.controller.state === "waiting"
                        || root.controller.state === "approved"
                        || root.controller.state === "logging_in"
                    )
                visible: running
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text:
                    root.controller
                        ? root.controller.statusText
                        : ""
                color: "white"
                opacity: 0.90
                font.pixelSize: 12
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            spacing: 18

            Rectangle {
                Layout.preferredWidth: 210
                Layout.preferredHeight: 210
                radius: 10
                color: "white"

                Image {
                    id: qrImage

                    anchors.fill: parent
                    anchors.margins: 8

                    source:
                        root.controller
                        && root.controller.qrPath.length > 0
                        && root.controller.qrPath.charAt(0) === "/"
                            ? "file://" + root.controller.qrPath
                            : ""

                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    mipmap: false
                    cache: false
                }

                QQC2.Label {
                    anchors.centerIn: parent
                    width: parent.width - 28
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible:
                        !root.controller
                        || root.controller.qrPath.length === 0
                        || qrImage.status === Image.Error
                    text: qsTr("QR-Code wird vorbereitet…")
                    color: "#263238"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                QQC2.Label {
                    Layout.fillWidth: true
                    text: qsTr(
                        "Scannen Sie den QR-Code mit Ihrem Smartphone "
                        + "und bestätigen Sie die Anmeldung."
                    )
                    wrapMode: Text.WordWrap
                    color: "white"
                    font.pixelSize: 12
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: qsTr("Gerätecode")
                    color: "white"
                    opacity: 0.65
                    font.pixelSize: 10
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text:
                        root.controller
                        && root.controller.userCode.length > 0
                            ? root.controller.userCode
                            : qsTr("Wird geladen…")
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18
                    wrapMode: Text.WrapAnywhere
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible:
                        root.controller
                        && root.controller.verificationUri.length > 0
                    text:
                        root.controller
                            ? root.controller.verificationUri
                            : ""
                    color: "white"
                    opacity: 0.66
                    font.pixelSize: 10
                    wrapMode: Text.WrapAnywhere
                }

                CountdownView {
                    Layout.fillWidth: true
                    visible:
                        root.controller
                        && root.controller.totalSecondsForFlow > 0
                    remainingSeconds:
                        root.controller
                            ? root.controller.remainingSeconds
                            : 0
                    totalSeconds:
                        root.controller
                            ? root.controller.totalSecondsForFlow
                            : 0
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr(
                "Sie können jederzeit zur Anmeldung mit Passwort zurückkehren."
            )
            color: "white"
            opacity: 0.68
            font.pixelSize: 11
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            QQC2.Button {
                visible:
                    root.controller
                    && (
                        root.controller.state === "starting"
                        || root.controller.state === "waiting"
                    )
                text: qsTr("Abbrechen")
                onClicked: root.cancelRequested()
            }

            QQC2.Button {
                visible:
                    root.controller
                    && (
                        root.controller.state === "error"
                        || root.controller.state === "expired"
                        || root.controller.state === "denied"
                        || root.controller.state === "cancelled"
                    )

                enabled:
                    root.controller
                    && root.controller.retryCooldownRemaining === 0
                    && root.controller.targetUsername.length > 0

                text:
                    root.controller
                    && root.controller.retryCooldownRemaining > 0
                        ? qsTr(
                            "Neuen Code in "
                            + root.controller.retryCooldownRemaining
                            + " s"
                        )
                        : qsTr("Neuen Code anfordern")

                onClicked: root.retryRequested()
            }

            Item {
                Layout.fillWidth: true
            }

            QQC2.Button {
                text: qsTr("Mit Passwort anmelden")
                enabled:
                    !root.controller
                    || (
                        root.controller.state !== "approved"
                        && root.controller.state !== "logging_in"
                    )
                onClicked: root.passwordRequested()
            }
        }
    }
}
