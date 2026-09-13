// SPDX-License-Identifier: GPL-3.0-or-later
//
// SDDM Authelia Passkey Native v1.16.0
//
// Presentation is original project work.
// Authentication remains exclusively with SDDM/PAM.
pragma ComponentBehavior: Bound
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

    // v2.13.0: the first visible generic mechanism-selection UI
    // (docs/generic-mechanism-model.md) - which mechanism's own
    // controls (password field/button vs. the smartphone flow) are
    // currently shown. Presentation state only: it decides what the
    // UI *offers* to show next, never an authentication decision -
    // the exact same real password/sddm.login()/broker paths run
    // regardless of this value. The actual switching/fallback state
    // machine lives in the separately unit-tested MechanismSelector.
    MechanismSelector {
        id: mechanismSelector

        mechanismModel: mechanismModel
        smartphoneFlow: smartphoneFlow
    }

    // eidp is the only selectable mechanism whose readiness can
    // change while selected (password is always ready; smartcard/
    // passkey are never selectable at all - see MechanismModel.qml).
    // If it drops while the user has it selected, MechanismSelector
    // fails closed back to password - never left silently on a
    // mechanism that can no longer start.
    Connections {
        target: mechanismModel

        function onEidpReadyChanged() {
            var before = mechanismSelector.selectedMechanism

            mechanismSelector.reconsiderCurrentMechanism()

            if (mechanismSelector.selectedMechanism !== before) {
                root.smartphonePanelOpen = false

                // v2.14.0: leave a sensible, visible focus target
                // behind rather than a stale/invisible one - this
                // fallback only ever lands on password (see
                // MechanismSelector.reconsiderCurrentMechanism()).
                passwordField.forceActiveFocus()
            }
        }
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

    // v2.13.0: the selector only ever decides which existing,
    // already-authorized content area is shown - it never makes or
    // gates an authentication decision itself. The actual selection/
    // cancel-on-leave state machine lives in the separately
    // unit-tested MechanismSelector; this wrapper only adds the two
    // pieces of Main.qml-local UI state MechanismSelector correctly
    // knows nothing about (the smartphone side panel, the password
    // failure label).
    function selectMechanism(mechanismId) {
        var before = mechanismSelector.selectedMechanism

        mechanismSelector.selectMechanism(mechanismId)

        if (mechanismSelector.selectedMechanism === before)
            return

        if (mechanismId !== "eidp")
            root.smartphonePanelOpen = false

        root.loginFailedVisible = false
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
            // returnToPassword() itself cancels the live flow above
            // (selectedMechanism is guaranteed "eidp" here - the panel
            // only ever opens via the eidp-only-visible start button).
            mechanismSelector.returnToPassword()

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

                        // v2.13.0: a real account change already
                        // cancels/resets the smartphone flow above
                        // (retarget() itself does that) - return the
                        // selector to password too, rather than
                        // leaving it pointed at a flow that no longer
                        // exists for the new account.
                        mechanismSelector.returnToPassword()
                    }

                    passwordField.text = ""

                    root.loginFailedVisible =
                        false

                    if (
                        !manualMode
                        && mechanismSelector.selectedMechanism
                            === "password"
                    )
                        passwordField.forceActiveFocus()
                }
            }

            QQC2.Label {
                Layout.fillWidth: true

                text: qsTr("Anmeldemethode")

                color: "#7d8fa2"

                font.pixelSize: 10
                font.weight: Font.Medium
            }

            GridLayout {
                id: mechanismSelectorGrid

                Layout.fillWidth: true

                // v2.14.0: reuses ResponsiveMetrics' own established
                // breakpoint model (docs/generic-mechanism-model.md)
                // rather than a second, unrelated pixel threshold -
                // one column (stacked) once the login card is too
                // narrow for two side-by-side buttons to stay legible.
                columns:
                    responsiveMetrics.selectorStacked ? 1 : 2

                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    id: mechanismSelectorRepeater

                    model:
                        mechanismModel.selectableMechanisms

                    delegate: PolishedButton {
                        id: mechanismTab

                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.column:
                            responsiveMetrics.selectorStacked
                                ? 0
                                : index
                        Layout.row:
                            responsiveMetrics.selectorStacked
                                ? index
                                : 0

                        compact: true

                        useCustomAccent:
                            branding.useCustomAccent

                        accentColor:
                            branding.accentColor

                        text: modelData.displayName

                        // Selected state is never conveyed by color
                        // alone: "primary" also changes font weight
                        // and border, and the accessible description
                        // states it explicitly for screen readers.
                        primary:
                            mechanismSelector.selectedMechanism === modelData.id

                        enabled: modelData.ready

                        Accessible.role:
                            Accessible.RadioButton

                        Accessible.name:
                            modelData.displayName

                        Accessible.description:
                            mechanismSelector.selectedMechanism === modelData.id
                                ? qsTr("Ausgewählt")
                                : modelData.statusHint

                        onClicked:
                            root.selectMechanism(modelData.id)

                        // v2.14.0: Left/Right moves focus to and
                        // selects the neighboring selectable mechanism
                        // (matching native radio-group semantics, and
                        // consistent with this button's own
                        // Accessible.role: RadioButton above) - a
                        // disabled/not-ready neighbor is skipped
                        // entirely rather than focused. Tab/Shift+Tab
                        // and Enter/Space need no extra code: they are
                        // QQC2.Button's own standard behavior.
                        Keys.onLeftPressed: {
                            var prev =
                                mechanismSelectorRepeater.itemAt(
                                    index - 1
                                )

                            if (prev && prev.enabled) {
                                prev.forceActiveFocus()
                                root.selectMechanism(
                                    mechanismModel
                                        .selectableMechanisms[index - 1]
                                        .id
                                )
                            }
                        }

                        Keys.onRightPressed: {
                            var next =
                                mechanismSelectorRepeater.itemAt(
                                    index + 1
                                )

                            if (next && next.enabled) {
                                next.forceActiveFocus()
                                root.selectMechanism(
                                    mechanismModel
                                        .selectableMechanisms[index + 1]
                                        .id
                                )
                            }
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true

                visible:
                    mechanismSelector.selectedMechanism === "password"

                text: qsTr("Passwort")

                color: "#7d8fa2"

                font.pixelSize: 10
                font.weight: Font.Medium
            }

            PolishedTextField {
                id: passwordField

                Layout.fillWidth: true

                visible:
                    mechanismSelector.selectedMechanism === "password"

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

                // v2.12.0: wired through the same shared Mechanism
                // model as the smartphone/EIdP button (see
                // docs/generic-mechanism-model.md). password.ready is
                // always true today - this establishes the single
                // source of truth without changing any rendered state.
                enabled:
                    userChooser.selectedUsername.length > 0
                        && mechanismModel.mechanism("password").ready

                onAccepted:
                    root.attemptPasswordLogin()
            }

            QQC2.Label {
                id: loginFailureLabel

                Layout.fillWidth: true

                visible:
                    root.loginFailedVisible
                    && mechanismSelector.selectedMechanism === "password"

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

                visible:
                    mechanismSelector.selectedMechanism === "password"

                // v2.12.0: same rationale as passwordField above.
                enabled:
                    userChooser.selectedUsername.length > 0
                        && mechanismModel.mechanism("password").ready

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

                visible:
                    mechanismSelector.selectedMechanism === "eidp"

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
                    mechanismSelector.selectedMechanism === "eidp"
                    && !mechanismModel.mechanism("eidp").ready

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

        // v2.14.0: sized from its own real content (see
        // SmartphoneLoginPanel.qml), capped by the available space -
        // no longer force-stretched to fill it, which used to leave a
        // large blank area below whenever the QR/confirmation group
        // was hidden (e.g. denied/expired/error states).
        height:
            Math.min(
                smartphonePanel.implicitHeight,
                responsiveMetrics.smartphoneCardHeight
            )

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

        // returnToPassword() itself cancels the live flow -
        // selectedMechanism is guaranteed "eidp" here (this panel
        // only ever opens via the eidp-only-visible start button).
        onCloseRequested: {
            mechanismSelector.returnToPassword()

            root.smartphonePanelOpen = false

            passwordField.forceActiveFocus()
        }

        onCancelRequested:
            smartphoneFlow.cancelCurrent(true)

        onRetryRequested:
            smartphoneFlow.retryFlow()

        onPasswordRequested: {
            mechanismSelector.returnToPassword()

            root.smartphonePanelOpen = false

            passwordField.forceActiveFocus()
        }
    }

    Component.onCompleted:
        passwordField.forceActiveFocus()
}
