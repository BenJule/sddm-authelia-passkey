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

    property bool showAvatar: true
    property bool useCustomAccent: false
    property color accentColor: "#3478e8"

    // v2.14.0: QR/device-code and "confirmed" are two distinct, never-
    // simultaneous sub-views of the same grouped confirmation area -
    // showing the still-scannable QR code at the same time as
    // "Bestätigt"/"Anmeldung läuft…" text contradicted itself, so
    // these are now mutually exclusive rather than one combined flag.
    readonly property bool showQrArea:
        controller
        && (
            controller.state === "starting"
            || controller.state === "waiting"
        )

    readonly property bool showConfirmedArea:
        controller
        && (
            controller.state === "approved"
            || controller.state === "logging_in"
        )

    // v2.14.0: "approved" is a real, safe cancel window -
    // SmartphoneFlowController's approvedTimer has not yet called
    // emitApprovedLogin()/sddm.login(), so cancelCurrent() there
    // genuinely stops the handoff (stops the timer, never fires it).
    // "logging_in" means sddm.login() has ALREADY been called -
    // cancelCurrent() cannot recall that, so offering "Schliessen" as
    // if it could cancel the login there would be a false affordance,
    // not a real one. Never claim a cancel that cannot happen.
    readonly property bool closeIsSafeToOffer:
        !controller
        || controller.state !== "logging_in"

    readonly property bool canRetry:
        controller
        && (
            (
                controller.state === "error"
                && controller.errorKind !== "not_authorized"
                && controller.errorKind !== "no_account"
            )
            || controller.state === "expired"
            || controller.state === "denied"
            || controller.state === "cancelled"
        )

    readonly property bool retryIsStartFailure:
        controller
        && (
            controller.errorKind === "offline"
            || controller.errorKind === "start_rate_limited"
            || controller.errorKind === "start_error"
            || controller.errorKind === "invalid_start_response"
        )

    readonly property bool qrUnavailable:
        controller
        && controller.state === "waiting"
        && (
            (
                controller.qrPath.length === 0
                && (
                    controller.userCode.length > 0
                    || controller.verificationUri.length > 0
                )
            )
            || qrImage.status === Image.Error
        )

    readonly property string qrFallbackText:
        !controller
            ? ""
            : controller.verificationUri.length > 0
                ? qsTr(
                    "QR-Code ist nicht verfügbar. Verwenden Sie den "
                    + "Gerätecode oder die angezeigte Anmeldeadresse."
                )
                : qsTr(
                    "QR-Code ist nicht verfügbar. Verwenden Sie den "
                    + "Gerätecode."
                )

    readonly property string effectiveStatusText:
        !controller
            ? ""
            : root.qrUnavailable
                ? root.qrFallbackText
                : controller.statusText

    readonly property string retryButtonText:
        !controller
            ? ""
            : controller.retryCooldownRemaining > 0
                ? root.retryIsStartFailure
                    ? qsTr(
                        "Erneut versuchen in %1 s"
                    ).arg(
                        controller.retryCooldownRemaining
                    )
                    : qsTr(
                        "Neuer Code in %1 s"
                    ).arg(
                        controller.retryCooldownRemaining
                    )
                : root.retryIsStartFailure
                    ? qsTr("Erneut versuchen")
                    : qsTr("Neuen Code anfordern")

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

    // v2.14.0: sized from real content, like the login card on the
    // left (docs/generic-mechanism-model.md) - never force-stretched
    // to the caller's full available height, which used to leave a
    // large, unintentional-looking blank area below the content
    // whenever the QR/confirmation area was hidden. Callers (Main.qml/
    // the visual harness) clamp this against their own available
    // space: height: Math.min(panel.implicitHeight, <available>).
    readonly property real contentMargins:
        root.compactLayout ? 15 : 21

    implicitHeight:
        contentColumn.implicitHeight
            + 2 * root.contentMargins

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

    Connections {
        target: root.controller

        function onStateChanged() {
            if (!root.open || !root.controller)
                return

            var terminal =
                root.controller.state === "error"
                || root.controller.state === "expired"
                || root.controller.state === "denied"
                || root.controller.state === "cancelled"

            if (!terminal)
                return

            Qt.callLater(function() {
                if (retryButton.visible && retryButton.enabled) {
                    retryButton.forceActiveFocus()
                } else if (passwordButton.enabled) {
                    passwordButton.forceActiveFocus()
                } else if (closeButton.enabled) {
                    closeButton.forceActiveFocus()
                }
            })
        }
    }

    Keys.onEscapePressed: {
        // v2.14.0: same real safe-cancel-window semantics as
        // closeButton/closeIsSafeToOffer above - Escape is otherwise
        // just a keyboard shortcut for the same closeRequested() the
        // button triggers, and must never claim to cancel a login
        // that has already been handed off to sddm.login().
        if (root.closeIsSafeToOffer) {
            root.closeRequested()
        }
    }

    ColumnLayout {
        id: contentColumn

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        anchors.margins:
            root.contentMargins

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

                QQC2.Label {
                    Layout.fillWidth: true

                    visible:
                        !!(
                            root.controller
                            && root.controller.fido2Wired
                        )

                    text:
                        qsTr(
                            "Hardware-Sicherheitsschlüssel verfügbar"
                        )

                    color: "#5fb88a"

                    font.pixelSize: 9

                    Accessible.ignored: true
                }
            }

            ConnectionStatus {
                // v2.14.0: de-emphasize the boring default - only
                // surface this badge in the header when it conveys
                // something the status area below doesn't already
                // (waiting/rate_limited/offline/error/connecting).
                // "ready" needs no badge cluttering the header.
                visible:
                    root.controller
                    && root.controller.connectionState !== "ready"

                connectionState:
                    root.controller
                        ? root.controller.connectionState
                        : "ready"
            }

            PolishedButton {
                useCustomAccent:
                    root.useCustomAccent

                accentColor:
                    root.accentColor

                id: closeButton

                compact: true

                text: qsTr("Schliessen")

                Accessible.name: qsTr("Smartphone-Login schliessen")

                // v2.14.0: may look secondary (not primary-styled),
                // and stays enabled through "approved" (a real, safe
                // cancel window - see closeIsSafeToOffer above), but
                // is disabled during "logging_in": sddm.login() has
                // already been called by then and cannot be recalled,
                // so offering to "cancel" it would be a false claim.
                enabled:
                    root.closeIsSafeToOffer

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
                    visible:
                        root.showAvatar

                    Layout.preferredWidth:
                        root.showAvatar
                            ? (
                                root.compactLayout
                                    ? 34
                                    : 38
                            )
                            : 0

                    Layout.preferredHeight:
                        root.showAvatar
                            ? (
                                root.compactLayout
                                    ? 34
                                    : 38
                            )
                            : 0

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
                root.effectiveStatusText

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

        // v2.14.0: QR code, device code and countdown grouped into one
        // visually connected confirmation area (a single bordered
        // container, matching the account-row Rectangle's visual
        // language) rather than floating loosely in the column. Sized
        // from its own content - invisible children contribute zero
        // layout size, so this container shrinks to nothing when
        // neither sub-view applies (e.g. denied/expired/error), which
        // is what actually removes the large blank area below.
        Rectangle {
            id: confirmationGroup

            Layout.fillWidth: true

            visible:
                root.showQrArea
                || root.showConfirmedArea

            implicitHeight:
                groupColumn.implicitHeight
                    + 2 * groupColumn.anchors.margins

            radius: 12

            color: Qt.rgba(0.07, 0.105, 0.145, 0.55)

            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.065)

            ColumnLayout {
                id: groupColumn

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10

                spacing: 10

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
                            root.useCustomAccent
                                ? Qt.rgba(
                                    root.accentColor.r,
                                    root.accentColor.g,
                                    root.accentColor.b,
                                    0.26
                                )
                                : Qt.rgba(
                                    0.31,
                                    0.57,
                                    0.96,
                                    0.26
                                )

                        Accessible.role: Accessible.Graphic
                        Accessible.name: qsTr("QR-Code für die Smartphone-Anmeldung")

                        Accessible.description:
                            root.qrUnavailable
                                ? root.qrFallbackText
                                : qsTr(
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

                            // Bounds decode cost to the actual displayed size
                            // regardless of how large the underlying file is.
                            sourceSize.width: Math.max(1, width)
                            sourceSize.height: Math.max(1, height)

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
                                root.qrUnavailable
                                    ? root.qrFallbackText
                                    : qsTr(
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
                                root.useCustomAccent
                                    ? Qt.rgba(
                                        root.accentColor.r,
                                        root.accentColor.g,
                                        root.accentColor.b,
                                        0.24
                                    )
                                    : Qt.rgba(
                                        0.35,
                                        0.62,
                                        1,
                                        0.24
                                    )

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
                                && root.qrUnavailable

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

                            useCustomAccent:
                                root.useCustomAccent

                            accentColor:
                                root.accentColor

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
                    }
                }

                // v2.14.0: the "confirmed" sub-view - approval already
                // happened, so no QR/device code is shown any more
                // (both would be stale and, worse, visually imply the
                // user still needs to scan/enter something). The
                // statusLabel above already carries the real,
                // state-specific text ("Bestätigt. Anmeldung wird
                // gestartet…" / "Anmeldung läuft…") - this is
                // deliberately just a compact visual anchor for it.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    visible: root.showConfirmedArea

                    spacing: 4

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6

                        width: 52
                        height: 52
                        radius: 26

                        color: Qt.rgba(0.373, 0.722, 0.596, 0.16)

                        border.width: 2
                        border.color: "#5fb88a"

                        Accessible.ignored: true

                        // A hand-drawn vector checkmark, not a Unicode
                        // glyph - the deterministic visual regression
                        // pipeline's restricted Noto Sans subset does
                        // not include a checkmark character, and this
                        // avoids depending on font glyph coverage at
                        // all (purely decorative anyway - the real
                        // status text above already carries the
                        // actual meaning; Accessible.ignored).
                        Canvas {
                            anchors.centerIn: parent

                            width: 24
                            height: 20

                            Accessible.ignored: true

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.strokeStyle = "#5fb88a"
                                ctx.lineWidth = 3
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath()
                                ctx.moveTo(2, 10)
                                ctx.lineTo(9, 17)
                                ctx.lineTo(22, 2)
                                ctx.stroke()
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 2
            Layout.bottomMargin: 2

            color: Qt.rgba(1, 1, 1, 0.055)
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
                useCustomAccent:
                    root.useCustomAccent

                accentColor:
                    root.accentColor

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
                id: retryButton

                useCustomAccent:
                    root.useCustomAccent

                accentColor:
                    root.accentColor

                compact: true
                primary: true

                visible:
                    root.canRetry

                enabled:
                    root.controller
                    && root.controller.retryCooldownRemaining === 0
                    && root.controller.targetUsername.length > 0

                text:
                    root.retryButtonText

                onClicked:
                    root.retryRequested()
            }

            Item {
                Layout.fillWidth: true
            }

            PolishedButton {
                id: passwordButton

                useCustomAccent:
                    root.useCustomAccent

                accentColor:
                    root.accentColor

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
