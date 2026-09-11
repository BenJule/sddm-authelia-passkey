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
    property bool modalLayout: false

    readonly property bool showQrArea:
        controller
        && (
            controller.state === "starting"
            || controller.state === "waiting"
            || controller.state === "approved"
            || controller.state === "logging_in"
        )

    readonly property bool canRetry:
        controller
        && (
            (
                controller.state === "error"
                && controller.errorKind !== "not_authorized"
            )
            || controller.state === "expired"
            || controller.state === "denied"
            || controller.state === "cancelled"
        )

    readonly property string accountKindLabel:
        !controller
            ? ""
            : controller.identitySource === "local"
                ? qsTr("Lokales Konto")
                : controller.identitySource.length > 0
                    ? qsTr("Verzeichniskonto")
                    : qsTr("Konto")

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

    Accessible.role:
        root.modalLayout
            ? Accessible.Dialog
            : Accessible.Pane

    Accessible.name: qsTr("Smartphone-Login")

    Accessible.description:
        root.controller
        && root.controller.targetUsername.length > 0
            ? qsTr(
                "Smartphone-Anmeldung für %1"
            ).arg(
                root.controller.targetUsername
            )
            : qsTr(
                "Smartphone-Anmeldung"
            )

    function statusNeedsAttention(value) {
        return value === "error"
            || value === "expired"
            || value === "denied"
            || value === "approved"
    }

    onOpenChanged: {
        if (open) {
            Qt.callLater(function() {
                if (closeButton.enabled)
                    closeButton.forceActiveFocus()
            })
        }
    }

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
                id: closeButton

                compact: true

                text: qsTr("Schliessen")

                Accessible.name: qsTr("Smartphone-Login schliessen")

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
                            root.accountKindLabel

                        color: "#73869a"

                        font.pixelSize: 9

                        elide: Text.ElideRight
                    }
                }
            }
        }

        QQC2.Label {
            id: statusLabel

            Layout.fillWidth: true

            text:
                root.controller
                    ? root.controller.statusText
                    : ""

            color: "#d9e4ef"

            font.pixelSize: 11

            wrapMode: Text.WordWrap

            Accessible.role:
                root.controller
                && root.statusNeedsAttention(
                    root.controller.state
                )
                    ? Accessible.AlertMessage
                    : Accessible.StaticText

            Accessible.name: text
        }

        RowLayout {
            Layout.fillWidth: true

            visible:
                root.showQrArea

            Layout.preferredHeight:
                root.showQrArea
                    ? root.qrSide + 18
                    : 0

            spacing:
                root.compactLayout
                    ? 13
                    : 17

            Rectangle {
                id: qrCard

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

                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("QR-Code für die Smartphone-Anmeldung")

                Accessible.description:
                    qsTr(
                        "Alternativ kann der angezeigte Gerätecode "
                        + "verwendet werden."
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

                    Accessible.ignored: true
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

                    Accessible.ignored: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true

                spacing: 7

                QQC2.Label {
                    Layout.fillWidth: true

                    text: qsTr("Gerätecode")

                    color: "#73869a"

                    font.pixelSize: 9

                    Accessible.ignored: true
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
                        id: deviceCodeLabel

                        anchors.fill: parent
                        anchors.margins: 8

                        text:
                            root.controller
                            && root.controller.userCode.length > 0
                                ? root.controller.userCode
                                : qsTr("Wird geladen…")

                        Accessible.role: Accessible.StaticText
                        Accessible.name: qsTr("Gerätecode: %1").arg(text)

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
                    id: verificationUriLabel

                    Layout.fillWidth: true

                    visible:
                        root.controller
                        && root.controller.verificationUri.length > 0
                        && qrImage.status === Image.Error

                    text:
                        root.controller
                            ? root.controller.verificationUri
                            : ""

                    Accessible.role: Accessible.StaticText
                    Accessible.name: qsTr("Anmeldeadresse: %1").arg(text)

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
                    root.canRetry

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
