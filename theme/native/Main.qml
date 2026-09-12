// SPDX-License-Identifier: GPL-3.0-or-later
//
// SDDM Authelia Passkey Native v1.16.0
//
// Presentation is original project work.
// Authentication remains exclusively with SDDM/PAM.
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

    BrandingConfig {
        id: branding

        configSource:
            typeof config !== "undefined"
                ? config
                : null

        hostName:
            typeof sddm !== "undefined"
            && sddm.hostName !== undefined
                ? sddm.hostName
                : ""
    }

    ResponsiveMetrics {
        id: responsiveMetrics

        viewportWidth: root.width
        viewportHeight: root.height
    }

    readonly property bool loginTransitioning:
        smartphoneFlow.state === "approved"
        || smartphoneFlow.state === "logging_in"

    Timer {
        interval: 1000

        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered:
            root.now = new Date()
    }

    SmartphoneFlowController {
        id: smartphoneFlow

        onLoginApproved:
            function(
                username,
                sessionIndex
            ) {
                sddm.login(
                    username,
                    "",
                    sessionIndex
                )
            }
    }

    // v2.11.0: the first real increment of a stable, documented
    // mechanism-selection interface (docs/generic-mechanism-model.md) -
    // a single source of truth for every mechanism's availability/
    // readiness, read below instead of each UI element wiring its own
    // ad-hoc property. Never gates an authentication decision itself.
    MechanismModel {
        id: mechanismModel

        smartphoneFlow: smartphoneFlow
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            if (
                smartphoneFlow.state === "logging_in"
                || smartphoneFlow.state === "approved"
            ) {
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
        if (
            userChooser.selectedUsername.length === 0
        )
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
        if (
            userChooser.selectedUsername.length === 0
        ) {
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
        if (
            root.smartphonePanelOpen
            && !root.loginTransitioning
        ) {
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
                color: "#142634"
            }

            GradientStop {
                position: 0.48
                color: "#0c1822"
            }

            GradientStop {
                position: 1
                color: "#071018"
            }
        }
    }

    Rectangle {
        width:
            Math.max(
                540,
                root.width * 0.44
            )

        height: width

        radius: width / 2

        x:
            root.width
            - width * 0.61

        y:
            -height * 0.57

        color:
            Qt.rgba(
                0.13,
                0.38,
                0.72,
                0.070
            )
    }

    Rectangle {
        width:
            Math.max(
                430,
                root.width * 0.34
            )

        height: width

        radius: width / 2

        x:
            -width * 0.58

        y:
            root.height
            - height * 0.40

        color:
            Qt.rgba(
                0.10,
                0.48,
                0.54,
                0.045
            )
    }

    Image {
        id: brandLogo

        anchors.left: parent.left
        anchors.top: parent.top

        anchors.leftMargin:
            responsiveMetrics.safeMargin

        anchors.topMargin:
            responsiveMetrics.safeMargin

        width:
            branding.brandLogoLocal
                ? 30
                : 0

        height: width

        visible:
            branding.brandLogoLocal

        source:
            branding.brandLogoSource

        // Bounds decode cost to the actual displayed size regardless of
        // how large the underlying file on disk is.
        sourceSize.width: Math.max(1, width)
        sourceSize.height: Math.max(1, height)

        fillMode:
            Image.PreserveAspectFit

        asynchronous: true
        smooth: true
        cache: false

        Accessible.role:
            Accessible.Graphic

        Accessible.name:
            branding.brandName.length > 0
                ? branding.brandName
                : qsTr("Brandlogo")
    }

    QQC2.Label {
        id: brandTitle

        anchors.left: parent.left
        anchors.top: parent.top

        anchors.leftMargin:
            responsiveMetrics.safeMargin
            + (
                brandLogo.visible
                    ? brandLogo.width + 9
                    : 0
            )

        anchors.topMargin:
            responsiveMetrics.safeMargin

        text:
            branding.brandName.length > 0
                ? branding.brandName
                : qsTr(
                    "SDDM · Authelia Passkey"
                )

        color: "#617589"

        font.pixelSize:
            branding.brandName.length > 0
                ? 12
                : 9

        font.weight:
            branding.brandName.length > 0
                ? Font.DemiBold
                : Font.Medium
    }

    QQC2.Label {
        anchors.left:
            brandTitle.left

        anchors.top:
            brandTitle.bottom

        anchors.topMargin: 2

        visible:
            branding.contextLabel.length > 0

        text:
            branding.contextLabel

        color: "#51677c"

        font.pixelSize: 8
        font.weight: Font.Medium
    }

    Rectangle {
        id: card

        x: {
            if (
                root.smartphonePanelOpen
                && !responsiveMetrics.overlayLayout
            ) {
                var available =
                    smartphonePanel.x
                    - responsiveMetrics.safeMargin

                return Math.max(
                    responsiveMetrics.safeMargin,
                    (
                        available
                        - width
                    ) / 2
                )
            }

            return (
                root.width
                - width
            ) / 2
        }

        y:
            (
                root.height
                - height
            ) / 2

        width:
            responsiveMetrics.loginCardWidth

        height:
            Math.min(
                cardColumn.implicitHeight
                    + 2
                        * responsiveMetrics.cardContentMargin,
                responsiveMetrics.loginCardMaxHeight
            )

        radius: 22

        color:
            Qt.rgba(
                0.035,
                0.058,
                0.082,
                0.945
            )

        border.width: 1

        border.color:
            Qt.rgba(
                1,
                1,
                1,
                0.095
            )

        Accessible.role: Accessible.Pane
        Accessible.name: qsTr("Anmeldung")

        enabled:
            !(
                root.smartphonePanelOpen
                && responsiveMetrics.overlayLayout
            )
            && !root.loginTransitioning

        opacity:
            enabled
                ? 1
                : 0.45

        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }

        ColumnLayout {
            id: cardColumn

            anchors.fill: parent

            anchors.margins:
                responsiveMetrics.cardContentMargin

            spacing:
                responsiveMetrics.compactHeight
                    ? 7
                    : 10

            RowLayout {
                Layout.fillWidth: true

                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true

                    spacing: 1

                    QQC2.Label {
                        Layout.fillWidth: true

                        text: qsTr("Willkommen")

                        color: "#f4f8fc"

                        font.pixelSize:
                            responsiveMetrics.compactHeight
                                ? 21
                                : 26

                        font.bold: true
                    }

                    QQC2.Label {
                        Layout.fillWidth: true

                        text:
                            qsTr(
                                "Sicher anmelden"
                            )

                        color: "#718499"

                        font.pixelSize: 10
                    }
                }

                ColumnLayout {
                    spacing: 0

                    QQC2.Label {
                        Layout.alignment: Qt.AlignRight

                        text:
                            Qt.formatTime(
                                root.now,
                                "hh:mm"
                            )

                        color: "#eef4fa"

                        font.pixelSize:
                            responsiveMetrics.compactHeight
                                ? 20
                                : 24

                        font.weight: Font.Light
                    }

                    QQC2.Label {
                        Layout.alignment: Qt.AlignRight

                        text:
                            root.now.toLocaleDateString(
                                Qt.locale("de_DE"),
                                "dddd, d. MMMM yyyy"
                            )

                        color: "#667b90"

                        font.pixelSize: 8
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1

                color: Qt.rgba(1, 1, 1, 0.065)
            }

            UserChooser {
                id: userChooser

                Layout.fillWidth: true

                Layout.preferredHeight:
                    implicitHeight

                compactMode:
                    responsiveMetrics.compactHeight

                showAvatar:
                    branding.showAvatar

                useCustomAccent:
                    branding.useCustomAccent

                accentColor:
                    branding.accentColor

                userModelSource:
                    userModel

                initialIndex:
                    userModel.lastIndex >= 0
                        ? userModel.lastIndex
                        : 0

                onAccountChanged: {
                    if (
                        smartphoneFlow.retarget(
                            selectedUsername
                        )
                    ) {
                        root.smartphonePanelOpen =
                            false
                    }

                    passwordField.text = ""

                    root.loginFailedVisible =
                        false

                    if (!manualMode)
                        passwordField.forceActiveFocus()
                }
            }

            QQC2.Label {
                Layout.fillWidth: true

                text: qsTr("Passwort")

                color: "#7d8fa2"

                font.pixelSize: 10
                font.weight: Font.Medium
            }

            PolishedTextField {
                id: passwordField

                Layout.fillWidth: true

                useCustomAccent:
                    branding.useCustomAccent

                accentColor:
                    branding.accentColor

                echoMode: TextInput.Password

                placeholderText:
                    qsTr(
                        "Passwort eingeben"
                    )

                Accessible.name: qsTr("Passwort")

                Accessible.description:
                    userChooser.selectedUsername.length > 0
                        ? qsTr(
                            "Passwort für %1"
                        ).arg(
                            userChooser.selectedUsername
                        )
                        : qsTr(
                            "Passwort für das ausgewählte Benutzerkonto"
                        )

                Accessible.passwordEdit: true

                enabled:
                    userChooser.selectedUsername.length > 0

                onAccepted:
                    root.attemptPasswordLogin()
            }

            QQC2.Label {
                id: loginFailureLabel

                Layout.fillWidth: true

                visible:
                    root.loginFailedVisible

                horizontalAlignment:
                    Text.AlignHCenter

                wrapMode: Text.WordWrap

                text:
                    qsTr(
                        "Anmeldung fehlgeschlagen. Bitte Eingabe prüfen."
                    )

                color: "#ff8585"

                font.pixelSize: 10

                Accessible.role: Accessible.AlertMessage
                Accessible.name: text
            }

            PolishedButton {
                id: loginButton

                Layout.fillWidth: true

                useCustomAccent:
                    branding.useCustomAccent

                accentColor:
                    branding.accentColor

                text:
                    qsTr(
                        "Mit Passwort anmelden"
                    )

                Accessible.defaultButton: true

                enabled:
                    userChooser.selectedUsername.length > 0

                onClicked:
                    root.attemptPasswordLogin()
            }

            PolishedButton {
                id: smartphoneLoginButton

                Layout.fillWidth: true

                useCustomAccent:
                    branding.useCustomAccent

                accentColor:
                    branding.accentColor

                primary: true

                text:
                    qsTr(
                        "Mit Smartphone anmelden"
                    )

                // v2.9.0: a first, real increment of capability-driven
                // mechanism offering (docs/mechanism-selection.md) -
                // oidcReady never gates a login decision (the broker
                // remains solely authoritative for that), it only
                // controls whether this button offers to start a flow
                // that is already known to be unable to reach the
                // identity provider right now. A stale-by-up-to-20s
                // capability answer cannot itself deny or grant a
                // login, since starting an /start attempt would still
                // go through the exact same real authorization path
                // either way.
                enabled:
                    userChooser.selectedUsername.length > 0
                    && mechanismModel.mechanism("eidp").ready

                Accessible.description:
                    mechanismModel.mechanism("eidp").ready
                        ? ""
                        : qsTr(
                            "Derzeit nicht erreichbar"
                        )

                onClicked:
                    root.openSmartphoneLogin()
            }

            QQC2.Label {
                Layout.fillWidth: true

                visible:
                    !mechanismModel.mechanism("eidp").ready

                horizontalAlignment:
                    Text.AlignHCenter

                wrapMode: Text.WordWrap

                text:
                    mechanismModel.mechanism("eidp").statusHint

                color: "#a2aebb"

                font.pixelSize: 9

                Accessible.ignored: true
            }

            QQC2.Label {
                Layout.fillWidth: true

                visible:
                    mechanismModel.mechanism("passkey").ready

                horizontalAlignment:
                    Text.AlignHCenter

                wrapMode: Text.WordWrap

                text:
                    mechanismModel.mechanism("passkey").statusHint

                color: "#5fb88a"

                font.pixelSize: 9

                Accessible.ignored: true
            }

            RowLayout {
                Layout.fillWidth: true

                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true

                    spacing: 3

                    QQC2.Label {
                        text: qsTr("Sitzung")

                        color: "#687c91"

                        font.pixelSize: 8

                        Accessible.ignored: true
                    }

                    PolishedComboBox {
                        id: sessionCombo

                        Layout.fillWidth: true

                        useCustomAccent:
                            branding.useCustomAccent

                        accentColor:
                            branding.accentColor

                        Accessible.name: qsTr("Sitzung")

                        model: sessionModel
                        textRole: "name"

                        currentIndex:
                            sessionModel.lastIndex >= 0
                                ? sessionModel.lastIndex
                                : 0
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true

                    visible:
                        typeof keyboard !== "undefined"
                        && keyboard.layouts !== undefined
                        && keyboard.layouts.count > 1

                    spacing: 3

                    QQC2.Label {
                        text: qsTr("Tastatur")

                        color: "#687c91"

                        font.pixelSize: 8

                        Accessible.ignored: true
                    }

                    PolishedComboBox {
                        id: keyboardCombo

                        Layout.fillWidth: true

                        useCustomAccent:
                            branding.useCustomAccent

                        accentColor:
                            branding.accentColor

                        Accessible.name: qsTr("Tastaturlayout")

                        model:
                            typeof keyboard !== "undefined"
                                ? keyboard.layouts
                                : null

                        textRole: "longName"

                        currentIndex:
                            typeof keyboard !== "undefined"
                                ? keyboard.currentLayout
                                : 0

                        onActivated:
                            function(index) {
                                if (
                                    typeof keyboard !== "undefined"
                                ) {
                                    keyboard.currentLayout =
                                        index
                                }
                            }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1

                color: Qt.rgba(1, 1, 1, 0.05)
            }

            PowerActionsRow {
                Layout.alignment:
                    Qt.AlignHCenter

                useCustomAccent:
                    branding.useCustomAccent

                accentColor:
                    branding.accentColor
            }
        }
    }

    Rectangle {
        anchors.fill: parent

        z: 50

        visible:
            root.smartphonePanelOpen
            && responsiveMetrics.overlayLayout

        color: Qt.rgba(0, 0, 0, 0.58)

        MouseArea {
            anchors.fill: parent
        }
    }

    SmartphoneLoginPanel {
        id: smartphonePanel

        z: 60

        x:
            responsiveMetrics.overlayLayout
                ? (
                    root.width
                    - width
                ) / 2
                : root.width
                    - responsiveMetrics.safeMargin
                    - width

        y:
            responsiveMetrics.overlayLayout
                ? (
                    root.height
                    - height
                ) / 2
                : responsiveMetrics.safeMargin

        width:
            responsiveMetrics.smartphoneCardWidth

        height:
            responsiveMetrics.smartphoneCardHeight

        compactLayout:
            responsiveMetrics.compactHeight
            || width < 520

        qrSide:
            responsiveMetrics.qrSide

        modalLayout: responsiveMetrics.overlayLayout

        showAvatar:
            branding.showAvatar

        useCustomAccent:
            branding.useCustomAccent

        accentColor:
            branding.accentColor

        controller:
            smartphoneFlow

        open:
            root.smartphonePanelOpen

        onCloseRequested: {
            if (smartphoneFlow.live)
                smartphoneFlow.cancelCurrent(false)

            root.smartphonePanelOpen = false

            passwordField.forceActiveFocus()
        }

        onCancelRequested:
            smartphoneFlow.cancelCurrent(true)

        onRetryRequested:
            smartphoneFlow.retryFlow()

        onPasswordRequested: {
            if (smartphoneFlow.live)
                smartphoneFlow.cancelCurrent(false)

            root.smartphonePanelOpen = false

            passwordField.forceActiveFocus()
        }
    }

    Component.onCompleted:
        passwordField.forceActiveFocus()
}
