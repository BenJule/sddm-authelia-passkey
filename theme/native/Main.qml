// SPDX-License-Identifier: GPL-3.0-or-later
//
// SDDM Authelia Passkey Native v1.10.0
//
// Original Qt6 SDDM theme implementation. Authentication remains the
// responsibility of SDDM/PAM. The Smartphone flow communicates only with
// the local project broker through SmartphoneFlowController.
import QtQuick
import QtQuick.Controls.Basic as QQC2
import QtQuick.Layouts
import "components"

Item {
    id: root

    width: 1920
    height: 1080
    focus: true

    property var now: new Date()
    property bool loginFailedVisible: false
    property bool smartphonePanelOpen: false

    readonly property bool loginTransitioning:
        smartphoneFlow.state === "approved"
        || smartphoneFlow.state === "logging_in"

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    SmartphoneFlowController {
        id: smartphoneFlow

        onLoginApproved: function(username, sessionIndex) {
            sddm.login(username, "", sessionIndex)
        }
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            if (smartphoneFlow.state === "logging_in"
                    || smartphoneFlow.state === "approved") {
                smartphoneFlow.loginFailed()
                root.smartphonePanelOpen = true
                return
            }

            root.loginFailedVisible = true
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }

        function onLoginSucceeded() {
            root.loginFailedVisible = false
            smartphoneFlow.loginSucceeded()
        }
    }

    function attemptPasswordLogin() {
        if (userChooser.selectedUsername.length === 0)
            return

        if (smartphoneFlow.live)
            smartphoneFlow.cancelCurrent(false)

        root.loginFailedVisible = false

        sddm.login(
            userChooser.selectedUsername,
            passwordField.text,
            sessionCombo.currentIndex
        )
    }

    function openSmartphoneLogin() {
        if (userChooser.selectedUsername.length === 0) {
            userChooser.beginManualEntry()
            return
        }

        root.loginFailedVisible = false
        root.smartphonePanelOpen = true

        if (!smartphoneFlow.live) {
            smartphoneFlow.startFlow(
                userChooser.selectedUsername,
                userChooser.selectedDisplayName,
                userChooser.selectedIcon,
                sessionCombo.currentIndex
            )
        }
    }

    Keys.onEscapePressed: {
        if (root.smartphonePanelOpen
                && !root.loginTransitioning) {
            if (smartphoneFlow.live)
                smartphoneFlow.cancelCurrent(false)

            root.smartphonePanelOpen = false
            passwordField.forceActiveFocus()
        }
    }

    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                position: 0
                color: "#182632"
            }

            GradientStop {
                position: 1
                color: "#0b121a"
            }
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent

        width: Math.min(560, root.width - 48)
        height: Math.min(
            cardColumn.implicitHeight + 48,
            root.height - 40
        )

        radius: 18
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        enabled:
            !root.smartphonePanelOpen
            && !root.loginTransitioning

        opacity: enabled ? 1 : 0.48

        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }

        ColumnLayout {
            id: cardColumn

            anchors.fill: parent
            anchors.margins: 24
            spacing: 10

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatTime(root.now, "hh:mm:ss")
                color: "white"
                font.pixelSize: 32
                font.weight: Font.Light
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(
                    root.now,
                    "dddd, d MMMM yyyy"
                )
                color: "white"
                opacity: 0.70
                font.pixelSize: 13
            }

            UserChooser {
                id: userChooser

                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight

                userModelSource: userModel
                initialIndex:
                    userModel.lastIndex >= 0
                        ? userModel.lastIndex
                        : 0

                onAccountChanged: {
                    if (smartphoneFlow.retarget(selectedUsername))
                        root.smartphonePanelOpen = false

                    passwordField.text = ""
                    root.loginFailedVisible = false

                    if (!manualMode)
                        passwordField.forceActiveFocus()
                }
            }

            QQC2.TextField {
                id: passwordField

                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: qsTr("Passwort")
                enabled: userChooser.selectedUsername.length > 0
                onAccepted: root.attemptPasswordLogin()
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.loginFailedVisible
                text: qsTr("Anmeldung fehlgeschlagen.")
                color: "#ff8585"
                font.pixelSize: 12
            }

            QQC2.Button {
                Layout.fillWidth: true
                text: qsTr("Anmelden")
                enabled: userChooser.selectedUsername.length > 0
                onClicked: root.attemptPasswordLogin()
            }

            QQC2.Button {
                Layout.fillWidth: true
                text: qsTr("Smartphone-Login")
                enabled: userChooser.selectedUsername.length > 0
                onClicked: root.openSmartphoneLogin()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                QQC2.Label {
                    text: qsTr("Sitzung:")
                    color: "white"
                    opacity: 0.72
                    font.pixelSize: 11
                }

                QQC2.ComboBox {
                    id: sessionCombo

                    Layout.fillWidth: true
                    model: sessionModel
                    textRole: "name"
                    currentIndex:
                        sessionModel.lastIndex >= 0
                            ? sessionModel.lastIndex
                            : 0
                }
            }

            RowLayout {
                Layout.fillWidth: true

                visible:
                    typeof keyboard !== "undefined"
                    && keyboard.layouts !== undefined
                    && keyboard.layouts.count > 1

                spacing: 8

                QQC2.Label {
                    text: qsTr("Tastatur:")
                    color: "white"
                    opacity: 0.72
                    font.pixelSize: 11
                }

                QQC2.ComboBox {
                    Layout.fillWidth: true

                    model:
                        typeof keyboard !== "undefined"
                            ? keyboard.layouts
                            : null

                    textRole: "longName"

                    currentIndex:
                        typeof keyboard !== "undefined"
                            ? keyboard.currentLayout
                            : 0

                    onActivated: function(index) {
                        if (typeof keyboard !== "undefined")
                            keyboard.currentLayout = index
                    }
                }
            }

            PowerActionsRow {
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 50
        visible: root.smartphonePanelOpen
        color: Qt.rgba(0, 0, 0, 0.48)

        MouseArea {
            anchors.fill: parent
            // Deliberately consume background interaction without closing an
            // in-progress authentication flow accidentally.
        }
    }

    SmartphoneLoginPanel {
        id: smartphonePanel

        z: 60
        anchors.centerIn: parent

        width: Math.min(620, root.width - 48)
        height: Math.min(620, root.height - 48)

        controller: smartphoneFlow
        open: root.smartphonePanelOpen

        onCloseRequested: {
            if (smartphoneFlow.live)
                smartphoneFlow.cancelCurrent(false)

            root.smartphonePanelOpen = false
            passwordField.forceActiveFocus()
        }

        onCancelRequested: {
            smartphoneFlow.cancelCurrent(true)
        }

        onRetryRequested: {
            smartphoneFlow.retryFlow()
        }

        onPasswordRequested: {
            if (smartphoneFlow.live)
                smartphoneFlow.cancelCurrent(false)

            root.smartphonePanelOpen = false
            passwordField.forceActiveFocus()
        }
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}
