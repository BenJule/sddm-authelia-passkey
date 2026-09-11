// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

Rectangle {
    id: root

    property var controller
    property bool open: false
    property bool compactLayout: false
    property real qrSide: 200

    signal closeRequested()
    signal cancelRequested()
    signal retryRequested()
    signal passwordRequested()

    visible: open
    focus: open

    radius: 20

    color: Qt.rgba(0.035, 0.055, 0.078, 0.985)

    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.10)

    Keys.onEscapePressed: {
        if (
            root.controller
            && root.controller.state !== "approved"
            && root.controller.state !== "logging_in"
        ) {
            root.closeRequested()
        }
    }

    ColumnLayout {
        anchors.fill: parent

        anchors.margins:
            root.compactLayout
                ? 15
                : 21

        spacing:
            root.compactLayout
                ? 8
                : 11

        RowLayout {
            Layout.fillWidth: true

            spacing: 9

            ColumnLayout {
                Layout.fillWidth: true

                spacing: 2

                QQC2.Label {
                    Layout.fillWidth: true

                    text:
                        qsTr(
                            "Smartphone-Login"
                        )

                    color: "#f5f8fc"

                    font.pixelSize:
                        root.compactLayout
                            ? 17
                            : 20

                    font.bold: true
                }

                QQC2.Label {
                    Layout.fillWidth: true

                    text:
                        qsTr(
                            "Anmeldung sicher bestätigen"
                        )

                    color: "#75879a"

                    font.pixelSize: 9
                }
            }

            ConnectionStatus {
                connectionState:
                    root.controller
                        ? root.controller.connectionState
                        : "ready"
            }

            PolishedButton {
                compact: true

                text: qsTr("Schliessen")

                enabled:
                    !root.controller
                    || (
                        root.controller.state !== "approved"
                        && root.controller.state !== "logging_in"
                    )

                onClicked:
                    root.closeRequested()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight:
                root.compactLayout
                    ? 50
                    : 56

            radius: 12

            color: Qt.rgba(0.07, 0.105, 0.145, 0.80)

            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.065)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8

                spacing: 9

                UserAvatar {
                    Layout.preferredWidth:
                        root.compactLayout
                            ? 34
                            : 38

                    Layout.preferredHeight:
                        root.compactLayout
                            ? 34
                            : 38

                    iconSource:
                        root.controller
                            ? root.controller.identityIconSource
                            : ""

                    label:
                        root.controller
                            ? root.controller.targetUsername
                            : ""
                }

                ColumnLayout {
                    Layout.fillWidth: true

                    spacing: 0

                    QQC2.Label {
                        Layout.fillWidth: true

                        text:
                            root.controller
                                ? root.controller.targetUsername
                                : ""

                        color: "#f3f7fb"

                        font.pixelSize: 12
                        font.bold: true

                        elide: Text.ElideRight
                    }

                    QQC2.Label {
                        Layout.fillWidth: true

                        text:
                            root.controller
                            && root.controller.identityDisplayName.length > 0
                            && root.controller.identityDisplayName
                                !== root.controller.targetUsername
                                ? root.controller.identityDisplayName
                                : (
                                    root.controller
                                    && root.controller.identitySource === "nss"
                                        ? qsTr("Verzeichniskonto")
                                        : qsTr("Lokales Konto")
                                )

                        color: "#73869a"

                        font.pixelSize: 9

                        elide: Text.ElideRight
                    }
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true

            text:
                root.controller
                    ? root.controller.statusText
                    : ""

            color: "#d9e4ef"

            font.pixelSize: 11

            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true

            Layout.preferredHeight:
                root.qrSide + 18

            spacing:
                root.compactLayout
                    ? 13
                    : 17

            Rectangle {
                Layout.preferredWidth:
                    root.qrSide + 18

                Layout.preferredHeight:
                    root.qrSide + 18

                radius: 15

                color: "#ffffff"

                border.width: 3
                border.color:
                    Qt.rgba(
                        0.31,
                        0.57,
                        0.96,
                        0.26
                    )

                Image {
                    id: qrImage

                    anchors.fill: parent
                    anchors.margins: 9

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

                    width:
                        parent.width - 28

                    horizontalAlignment:
                        Text.AlignHCenter

                    wrapMode:
                        Text.WordWrap

                    visible:
                        !root.controller
                        || root.controller.qrPath.length === 0
                        || qrImage.status === Image.Error

                    text:
                        qsTr(
                            "QR-Code wird vorbereitet…"
                        )

                    color: "#263238"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true

                spacing: 7

                QQC2.Label {
                    Layout.fillWidth: true

                    text:
                        qsTr(
                            "QR-Code scannen und die Anmeldung auf dem Smartphone bestätigen."
                        )

                    color: "#e3ebf4"

                    font.pixelSize: 11

                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    Layout.fillWidth: true

                    text: qsTr("Gerätecode")

                    color: "#73869a"

                    font.pixelSize: 9
                }

                Rectangle {
                    Layout.fillWidth: true

                    Layout.preferredHeight:
                        root.compactLayout
                            ? 38
                            : 42

                    radius: 9

                    color: Qt.rgba(0.105, 0.17, 0.24, 0.90)

                    border.width: 1
                    border.color:
                        Qt.rgba(0.35, 0.62, 1, 0.24)

                    QQC2.Label {
                        anchors.fill: parent
                        anchors.margins: 8

                        text:
                            root.controller
                            && root.controller.userCode.length > 0
                                ? root.controller.userCode
                                : qsTr("Wird geladen…")

                        color: "#f4f8fc"

                        verticalAlignment:
                            Text.AlignVCenter

                        font.bold: true

                        font.pixelSize:
                            root.compactLayout
                                ? 15
                                : 17

                        font.letterSpacing: 1.2

                        elide: Text.ElideRight
                    }
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

                    color: "#697d92"

                    font.pixelSize: 8

                    wrapMode: Text.WrapAnywhere

                    maximumLineCount: 2
                    elide: Text.ElideRight
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

        Item {
            Layout.fillHeight: true
        }

        QQC2.Label {
            Layout.fillWidth: true

            text:
                qsTr(
                    "Die Passwort-Anmeldung bleibt jederzeit verfügbar."
                )

            color: "#718398"

            font.pixelSize: 9

            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true

            spacing: 8

            PolishedButton {
                compact: true

                visible:
                    root.controller
                    && (
                        root.controller.state === "starting"
                        || root.controller.state === "waiting"
                    )

                text: qsTr("Abbrechen")

                onClicked:
                    root.cancelRequested()
            }

            PolishedButton {
                compact: true
                primary: true

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
                            "Neuer Code in "
                            + root.controller.retryCooldownRemaining
                            + " s"
                        )
                        : qsTr("Neuen Code anfordern")

                onClicked:
                    root.retryRequested()
            }

            Item {
                Layout.fillWidth: true
            }

            PolishedButton {
                compact: true

                text:
                    qsTr(
                        "Mit Passwort fortfahren"
                    )

                enabled:
                    !root.controller
                    || (
                        root.controller.state !== "approved"
                        && root.controller.state !== "logging_in"
                    )

                onClicked:
                    root.passwordRequested()
            }
        }
    }
}
