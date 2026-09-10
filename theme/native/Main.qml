// SPDX-License-Identifier: GPL-3.0-or-later
//
// SDDM Authelia Passkey Native - v1.9.0 Foundation
//
// Original, from-scratch Qt6 SDDM greeter theme for this project. Not
// derived from Debian Breeze, KDE Breeze, or any other third-party
// theme source - see theme/native/PROVENANCE.md for the explicit
// provenance statement. Uses only documented SDDM greeter context
// APIs (sddm/userModel/sessionModel/keyboard) and standard Qt Quick
// Controls/Layouts modules - no Plasma/Kirigami dependency, no vendored
// artwork, no remote resources.
//
// This release is a FOUNDATION, not feature parity with the
// compatibility (Debian Breeze patch) theme - see
// docs/native-theme.md and theme/native/README.md. In particular the
// Smartphone-Login action here is an intentional placeholder affordance
// (components/SmartphoneLoginPreview.qml): it never talks to the
// broker and never claims a login occurred. The full QR/device-code
// flow lands in v1.10.0.

import QtQuick
import QtQuick.Controls.Basic as QQC2
import QtQuick.Layouts
import "components"

Item {
    id: root

    width: 1920
    height: 1080

    focus: true

    // -- Selected user (v1.9.0 shows the SDDM-selected/last user only;
    // a full switchable user list is v1.10.0 scope, see
    // NATIVE-THEME-ROADMAP.md) --------------------------------------
    readonly property int selectedUserIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property string selectedUserName: userModel.lastUser || ""
    property string selectedUserRealName: ""
    property string selectedUserIcon: ""

    // Pure data extraction: materializes one invisible delegate per
    // userModel entry purely to read the selected index's role values
    // by name (the standard, documented way to read arbitrary
    // QAbstractListModel role data from QML), never rendered as a
    // list - v1.9.0 deliberately shows only the single selected user.
    Repeater {
        model: userModel
        delegate: Item {
            visible: false
            Component.onCompleted: {
                if (index === root.selectedUserIndex) {
                    if (model.name) root.selectedUserName = model.name
                    root.selectedUserRealName = (model.realName && model.realName.length > 0) ? model.realName : root.selectedUserName
                    root.selectedUserIcon = model.icon || ""
                }
            }
        }
    }

    // -- Clock ---------------------------------------------------------
    property var now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // -- Login failure feedback -----------------------------------------
    property bool loginFailedVisible: false

    Connections {
        target: sddm
        function onLoginFailed() {
            root.loginFailedVisible = true
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            root.loginFailedVisible = false
        }
    }

    function attemptLogin() {
        if (root.selectedUserName.length === 0) return
        root.loginFailedVisible = false
        sddm.login(root.selectedUserName, passwordField.text, sessionCombo.currentIndex)
    }

    // -- Smartphone-Login foundation affordance --------------------------
    property bool smartphonePreviewOpen: false

    // Escape must never have an unsafe side effect: the only thing it
    // does is close the (purely informational) smartphone preview if
    // it happens to be open. It never submits the password field,
    // never triggers a power action, and does nothing at all when
    // nothing is open.
    Keys.onEscapePressed: {
        if (root.smartphonePreviewOpen) {
            root.smartphonePreviewOpen = false
        }
    }

    // -- Background ------------------------------------------------------
    // A calm, original two-tone gradient - no wallpaper image
    // dependency, no vendored artwork.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1b2733" }
            GradientStop { position: 1.0; color: "#0e1620" }
        }
    }

    // -- Centered login surface ------------------------------------------
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(420, parent.width - 64)
        height: cardColumn.implicitHeight + 64
        radius: 16
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 32
            spacing: 14

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatTime(root.now, "hh:mm:ss")
                color: "white"
                font.pixelSize: 34
                font.weight: Font.Light
            }
            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.now, "dddd, d MMMM yyyy")
                color: "white"
                opacity: 0.75
                font.pixelSize: 14
            }

            Item { Layout.preferredHeight: 6 }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                UserAvatar {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    iconSource: root.selectedUserIcon
                    label: root.selectedUserRealName.length > 0 ? root.selectedUserRealName : root.selectedUserName
                }

                ColumnLayout {
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selectedUserRealName.length > 0 ? root.selectedUserRealName : root.selectedUserName
                        color: "white"
                        font.bold: true
                        font.pixelSize: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selectedUserName
                        color: "white"
                        opacity: 0.6
                        font.pixelSize: 12
                    }
                }
            }

            QQC2.TextField {
                id: passwordField
                Layout.fillWidth: true
                Layout.topMargin: 10
                echoMode: TextInput.Password
                placeholderText: qsTr("Passwort")
                onAccepted: root.attemptLogin()
            }

            Text {
                id: loginErrorText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.loginFailedVisible
                text: qsTr("Anmeldung fehlgeschlagen.")
                color: "#ff8080"
                font.pixelSize: 13
            }

            QQC2.Button {
                Layout.fillWidth: true
                text: qsTr("Anmelden")
                enabled: root.selectedUserName.length > 0
                onClicked: root.attemptLogin()
            }

            QQC2.Button {
                Layout.fillWidth: true
                text: qsTr("Smartphone-Login")
                onClicked: root.smartphonePreviewOpen = true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                Text {
                    text: qsTr("Sitzung:")
                    color: "white"
                    opacity: 0.75
                    font.pixelSize: 12
                }
                QQC2.ComboBox {
                    id: sessionCombo
                    Layout.fillWidth: true
                    model: sessionModel
                    textRole: "name"
                    currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: typeof keyboard !== "undefined" &&
                    keyboard.layouts !== undefined &&
                    keyboard.layouts.count > 1
                spacing: 10

                Text {
                    text: qsTr("Tastatur:")
                    color: "white"
                    opacity: 0.75
                    font.pixelSize: 12
                }
                QQC2.ComboBox {
                    id: keyboardCombo
                    Layout.fillWidth: true
                    model: (typeof keyboard !== "undefined") ? keyboard.layouts : null
                    textRole: "longName"
                    currentIndex: (typeof keyboard !== "undefined") ? keyboard.currentLayout : 0
                    onActivated: (idx) => {
                        if (typeof keyboard !== "undefined") keyboard.currentLayout = idx
                    }
                }
            }

            Item { Layout.preferredHeight: 6 }

            PowerActionsRow {
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // -- Smartphone-Login foundation preview overlay ----------------------
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.smartphonePreviewOpen ? 0.45 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    SmartphoneLoginPreview {
        anchors.centerIn: parent
        width: Math.min(460, root.width - 64)
        height: Math.min(260, root.height - 64)
        open: root.smartphonePreviewOpen
        onCloseRequested: root.smartphonePreviewOpen = false
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}
