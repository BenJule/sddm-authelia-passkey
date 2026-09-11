// SPDX-License-Identifier: GPL-3.0-or-later
//
// Original Native Theme code for sddm-authelia-passkey.
//
// This component owns presentation-side device-flow state only.
// Authentication decisions remain entirely outside QML. The only network
// peer this component may contact is the local project broker.
import QtQuick

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property string brokerOrigin: "http://127.0.0.1:7899"
    property int pollIntervalMs: 2000
    property int approvalDelayMs: 350

    property string state: "idle"
    property string connectionState: "ready"
    property string errorKind: ""
    property string statusText: ""

    property string sessionId: ""
    property string targetUsername: ""
    property int targetSessionIndex: 0
    property string resolvedUsername: ""

    property string identityDisplayName: ""
    property string identitySource: ""
    property string identityIconSource: ""

    property string qrPath: ""
    property string verificationUri: ""
    property string userCode: ""

    property real expiresAt: 0
    property int remainingSeconds: 0
    property int totalSecondsForFlow: 0

    property int retryAfterSeconds: 0
    property real retryAvailableAt: 0
    property int retryCooldownRemaining: 0

    property int flowGeneration: 0
    property bool requestInFlight: false
    property bool loginEmitted: false

    readonly property bool live:
        state === "starting"
        || state === "waiting"
        || state === "approved"
        || state === "logging_in"

    signal loginApproved(string username, int sessionIndex)

    Timer {
        id: pollTimer
        interval: Math.max(50, root.pollIntervalMs)
        repeat: true
        onTriggered: root.pollStatus()
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: root.updateCountdown()
    }

    Timer {
        id: retryTimer
        interval: 250
        repeat: true
        onTriggered: root.updateRetryCooldown()
    }

    Timer {
        id: approvedTimer
        interval: Math.max(1, root.approvalDelayMs)
        repeat: false
        onTriggered: root.emitApprovedLogin()
    }

    function safeParse(text) {
        try {
            return JSON.parse(text)
        } catch (e) {
            return null
        }
    }

    function stopFlowTimers() {
        pollTimer.stop()
        countdownTimer.stop()
        approvedTimer.stop()
    }

    function clearDisplayData() {
        root.sessionId = ""
        root.resolvedUsername = ""
        root.qrPath = ""
        root.verificationUri = ""
        root.userCode = ""
        root.expiresAt = 0
        root.remainingSeconds = 0
        root.totalSecondsForFlow = 0
        root.retryAfterSeconds = 0
        root.loginEmitted = false
    }

    function armRetryCooldown(seconds) {
        root.retryAvailableAt = Date.now() / 1000 + Math.max(0, seconds)
        root.updateRetryCooldown()
        if (root.retryCooldownRemaining > 0)
            retryTimer.start()
    }

    function updateRetryCooldown() {
        if (root.retryAvailableAt <= 0) {
            root.retryCooldownRemaining = 0
            retryTimer.stop()
            return
        }

        var left = root.retryAvailableAt - Date.now() / 1000
        root.retryCooldownRemaining = Math.max(0, Math.ceil(left))

        if (root.retryCooldownRemaining <= 0)
            retryTimer.stop()
    }

    function updateCountdown() {
        if (root.expiresAt <= 0) {
            root.remainingSeconds = 0
            return
        }

        var left = root.expiresAt - Date.now() / 1000
        root.remainingSeconds = Math.max(0, Math.ceil(left))

        // Display only. The broker remains the expiry authority.
        if (root.remainingSeconds <= 0)
            countdownTimer.stop()
    }

    function cancelSession(session) {
        if (!session || session.length === 0)
            return

        var xhr = new XMLHttpRequest()
        xhr.open(
            "POST",
            root.brokerOrigin
                + "/cancel?session_id="
                + encodeURIComponent(session)
        )
        xhr.send()
    }

    function lookupIdentity(username, generation) {
        var xhr = new XMLHttpRequest()

        xhr.open(
            "GET",
            root.brokerOrigin
                + "/identity?username="
                + encodeURIComponent(username)
        )

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (generation !== root.flowGeneration
                    || username !== root.targetUsername)
                return

            if (xhr.status !== 200)
                return

            var response = root.safeParse(xhr.responseText)
            if (!response)
                return

            if (response.username !== root.targetUsername)
                return

            if (response.display_name)
                root.identityDisplayName = response.display_name

            if (response.account_source)
                root.identitySource = response.account_source
        }

        xhr.send()
    }

    function setStartError(kind, connection, text, cooldown) {
        root.stopFlowTimers()
        root.state = "error"
        root.errorKind = kind
        root.connectionState = connection
        root.statusText = text
        root.requestInFlight = false

        if (cooldown > 0)
            root.armRetryCooldown(cooldown)
    }

    function startFlow(username, displayName, iconSource, sessionIndex) {
        var cleanUsername = username ? username.trim() : ""

        if (root.live)
            return false

        if (root.retryCooldownRemaining > 0
                && cleanUsername === root.targetUsername)
            return false

        if (cleanUsername.length === 0) {
            root.state = "error"
            root.errorKind = "no_account"
            root.connectionState = "ready"
            root.statusText = qsTr(
                "Bitte zuerst ein Konto auswählen oder eingeben."
            )
            return false
        }

        root.stopFlowTimers()
        retryTimer.stop()

        root.flowGeneration += 1
        var generation = root.flowGeneration

        root.clearDisplayData()

        root.targetUsername = cleanUsername
        root.targetSessionIndex = Math.max(0, sessionIndex)
        root.identityDisplayName =
            displayName && displayName.length > 0
                ? displayName
                : cleanUsername
        root.identityIconSource = iconSource || ""
        root.identitySource = ""

        root.errorKind = ""
        root.statusText = qsTr("Anmeldung wird vorbereitet…")
        root.connectionState = "connecting"
        root.state = "starting"
        root.requestInFlight = true

        root.lookupIdentity(cleanUsername, generation)

        var xhr = new XMLHttpRequest()

        xhr.open(
            "POST",
            root.brokerOrigin
                + "/start?username="
                + encodeURIComponent(cleanUsername)
        )

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            var response = root.safeParse(xhr.responseText)

            // A late response from an invalidated start must never become the
            // current flow. If it created a broker session, cancel it.
            if (generation !== root.flowGeneration
                    || cleanUsername !== root.targetUsername) {
                if (response && response.session_id)
                    root.cancelSession(response.session_id)
                return
            }

            root.requestInFlight = false

            if (xhr.status === 0) {
                root.setStartError(
                    "offline",
                    "offline",
                    qsTr("Der Anmeldedienst ist derzeit nicht erreichbar."),
                    4
                )
                return
            }

            if (xhr.status === 403) {
                root.setStartError(
                    "not_authorized",
                    "ready",
                    qsTr(
                        "Dieses Konto ist für Smartphone-Login "
                        + "nicht verfügbar. Bitte Passwort verwenden."
                    ),
                    3
                )
                return
            }

            if (xhr.status === 429) {
                root.setStartError(
                    "start_rate_limited",
                    "rate_limited",
                    qsTr(
                        "Smartphone-Anmeldung kann gerade nicht neu "
                        + "gestartet werden. Bitte kurz warten oder "
                        + "Passwort verwenden."
                    ),
                    10
                )
                return
            }

            if (xhr.status < 200 || xhr.status >= 300) {
                root.setStartError(
                    "start_error",
                    "error",
                    qsTr("Smartphone-Login konnte nicht gestartet werden."),
                    4
                )
                return
            }

            if (!response || !response.session_id) {
                root.setStartError(
                    "invalid_start_response",
                    "error",
                    qsTr("Smartphone-Login konnte nicht gestartet werden."),
                    4
                )
                return
            }

            root.sessionId = response.session_id
            root.state = "waiting"
            root.connectionState = "waiting"
            root.statusText = qsTr(
                "Scannen Sie den QR-Code mit Ihrem Smartphone "
                + "und bestätigen Sie die Anmeldung."
            )

            pollTimer.start()
            root.pollStatus()
        }

        xhr.send()
        return true
    }

    function pollStatus() {
        if (root.state !== "waiting"
                || root.sessionId.length === 0)
            return

        var generation = root.flowGeneration
        var pollingSession = root.sessionId

        var xhr = new XMLHttpRequest()

        xhr.open(
            "GET",
            root.brokerOrigin
                + "/status?session_id="
                + encodeURIComponent(pollingSession)
        )

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (generation !== root.flowGeneration
                    || pollingSession !== root.sessionId
                    || root.state !== "waiting")
                return

            if (xhr.status === 0) {
                root.connectionState = "offline"
                root.statusText = qsTr(
                    "Verbindung zum Anmeldedienst unterbrochen. "
                    + "Der aktuelle Code bleibt bestehen."
                )
                return
            }

            if (xhr.status === 404) {
                pollTimer.stop()
                root.state = "error"
                root.errorKind = "session_lost"
                root.connectionState = "error"
                root.statusText = qsTr(
                    "Der Anmeldevorgang ist nicht mehr verfügbar. "
                    + "Fordern Sie einen neuen Code an."
                )
                root.armRetryCooldown(2)
                return
            }

            if (xhr.status < 200 || xhr.status >= 300) {
                root.errorKind = "status_unavailable"
                root.connectionState = "error"
                root.statusText = qsTr(
                    "Der Anmeldestatus ist vorübergehend nicht "
                    + "verfügbar. Der aktuelle Code bleibt bestehen."
                )
                return
            }

            var response = root.safeParse(xhr.responseText)

            if (!response) {
                root.errorKind = "malformed_status"
                root.connectionState = "error"
                root.statusText = qsTr(
                    "Der Anmeldestatus konnte vorübergehend nicht "
                    + "verarbeitet werden. Der aktuelle Code bleibt "
                    + "bestehen."
                )
                return
            }

            root.applyStatus(response, generation, pollingSession)
        }

        xhr.send()
    }

    function updateFlowPresentation(response) {
        if (response.qr_path)
            root.qrPath = response.qr_path

        if (response.verification_uri_complete)
            root.verificationUri = response.verification_uri_complete

        if (response.user_code)
            root.userCode = response.user_code

        if (response.expires_at) {
            var newExpiry = Number(response.expires_at)

            if (newExpiry > 0) {
                root.expiresAt = newExpiry

                if (root.totalSecondsForFlow <= 0) {
                    root.totalSecondsForFlow = Math.max(
                        1,
                        Math.ceil(newExpiry - Date.now() / 1000)
                    )
                }

                root.updateCountdown()

                if (root.remainingSeconds > 0)
                    countdownTimer.start()
            }
        }
    }

    function setExpired(reason) {
        root.stopFlowTimers()
        root.state = "expired"
        root.errorKind = reason
        root.connectionState = "ready"
        root.statusText = qsTr("QR-Code abgelaufen.")
        root.armRetryCooldown(2)
    }

    function applyStatus(response, generation, pollingSession) {
        if (generation !== root.flowGeneration
                || pollingSession !== root.sessionId
                || root.state !== "waiting")
            return

        root.updateFlowPresentation(response)

        if (typeof response.status !== "string"
                || response.status.length === 0) {
            pollTimer.stop()
            root.cancelSession(pollingSession)
            root.state = "error"
            root.errorKind = "malformed_status"
            root.connectionState = "error"
            root.statusText = qsTr(
                "Der Anmeldestatus konnte nicht verarbeitet werden. "
                + "Bitte einen neuen Code anfordern oder Passwort "
                + "verwenden."
            )
            root.armRetryCooldown(4)
            return
        }

        var responseStatus = response.status

        if (responseStatus === "pending") {
            root.state = "waiting"

            if (response.rate_limited === true) {
                root.errorKind = "provider_rate_limited"
                root.connectionState = "rate_limited"
                root.retryAfterSeconds =
                    Math.max(0, Number(response.retry_after_seconds || 0))

                root.statusText = qsTr(
                    "Der Anmeldedienst wartet derzeit mit weiteren "
                    + "Statusabfragen. Bitte kurz warten."
                )
            } else {
                root.errorKind = ""
                root.connectionState = "waiting"
                root.retryAfterSeconds = 0
                root.statusText = qsTr(
                    "Scannen Sie den QR-Code mit Ihrem Smartphone "
                    + "und bestätigen Sie die Anmeldung."
                )
            }

            return
        }

        pollTimer.stop()

        if (responseStatus === "approved") {
            if (!response.username
                    || response.username !== root.targetUsername) {
                root.state = "error"
                root.errorKind = "identity_mismatch"
                root.connectionState = "ready"
                root.statusText = qsTr(
                    "Die bestätigte Identität passt nicht zum "
                    + "ausgewählten Konto."
                )
                return
            }

            root.resolvedUsername = response.username
            root.state = "approved"
            root.errorKind = ""
            root.connectionState = "ready"
            root.statusText = qsTr(
                "Bestätigt. Anmeldung wird gestartet…"
            )

            approvedTimer.restart()
            return
        }

        if (responseStatus === "denied") {
            root.state = "denied"
            root.errorKind = "denied"
            root.connectionState = "ready"
            root.statusText = qsTr(
                "Die Anmeldung wurde nicht bestätigt."
            )
            root.armRetryCooldown(3)
            return
        }

        if (responseStatus === "expired") {
            root.setExpired("expired")
            return
        }

        if (responseStatus === "error") {
            var reason = response.error || ""

            if (reason === "expired") {
                root.setExpired("expired")
                return
            }

            if (reason === "rate_limited") {
                root.state = "error"
                root.errorKind = "provider_rate_limited"
                root.connectionState = "rate_limited"
                root.statusText = qsTr(
                    "Der Anmeldedienst ist derzeit ausgelastet. "
                    + "Bitte einen neuen Code anfordern oder Passwort "
                    + "verwenden."
                )
                root.armRetryCooldown(4)
                return
            }

            if (reason === "temporarily_unavailable"
                    || reason === "device authorization request failed"
                    || reason === "userinfo verification failed") {
                root.state = "error"
                root.errorKind = "provider_unavailable"
                root.connectionState = "error"
                root.statusText = qsTr(
                    "Der Anmeldedienst ist vorübergehend nicht "
                    + "verfügbar. Bitte Passwort verwenden oder später "
                    + "einen neuen Code anfordern."
                )
                root.armRetryCooldown(4)
                return
            }

            root.state = "error"
            root.errorKind = "broker_error"
            root.connectionState = "error"
            root.statusText = qsTr(
                "Die Smartphone-Anmeldung konnte nicht abgeschlossen "
                + "werden. Bitte Passwort verwenden oder einen neuen "
                + "Code anfordern."
            )
            root.armRetryCooldown(4)
            return
        }

        root.cancelSession(pollingSession)
        root.state = "error"
        root.errorKind = "unknown_status"
        root.connectionState = "error"
        root.statusText = qsTr(
            "Der Anmeldestatus konnte nicht verarbeitet werden. "
            + "Bitte einen neuen Code anfordern oder Passwort verwenden."
        )
        root.armRetryCooldown(4)
    }

    function emitApprovedLogin() {
        if (root.state !== "approved"
                || root.loginEmitted
                || root.resolvedUsername.length === 0
                || root.resolvedUsername !== root.targetUsername)
            return

        root.loginEmitted = true
        root.state = "logging_in"
        root.statusText = qsTr("Anmeldung läuft…")

        root.loginApproved(
            root.resolvedUsername,
            root.targetSessionIndex
        )
    }

    function cancelCurrent(showCancelled) {
        var oldSession = root.sessionId

        root.flowGeneration += 1
        root.stopFlowTimers()
        retryTimer.stop()

        root.requestInFlight = false
        root.clearDisplayData()

        if (oldSession.length > 0)
            root.cancelSession(oldSession)

        root.connectionState = "ready"
        root.errorKind = ""

        if (showCancelled === false) {
            root.state = "idle"
            root.statusText = ""
        } else {
            root.state = "cancelled"
            root.statusText = qsTr("Anmeldung abgebrochen.")
        }
    }

    function retarget(newUsername) {
        var clean = newUsername ? newUsername.trim() : ""

        if (root.targetUsername.length === 0
                || clean === root.targetUsername)
            return false

        if (root.live) {
            root.cancelCurrent(false)
        } else {
            root.flowGeneration += 1
            root.stopFlowTimers()
            retryTimer.stop()
            root.clearDisplayData()

            root.targetUsername = ""
            root.targetSessionIndex = 0
            root.identityDisplayName = ""
            root.identitySource = ""
            root.identityIconSource = ""

            root.errorKind = ""
            root.connectionState = "ready"
            root.state = "idle"
            root.statusText = ""
        }

        return true
    }

    function retryFlow() {
        if (root.retryCooldownRemaining > 0)
            return false

        if (root.targetUsername.length === 0)
            return false

        var username = root.targetUsername
        var displayName = root.identityDisplayName
        var iconSource = root.identityIconSource
        var sessionIndex = root.targetSessionIndex
        var oldSession = root.sessionId

        if (oldSession.length > 0)
            root.cancelSession(oldSession)

        root.state = "idle"
        root.errorKind = ""
        root.connectionState = "ready"

        return root.startFlow(
            username,
            displayName,
            iconSource,
            sessionIndex
        )
    }

    function loginFailed() {
        if (root.state !== "logging_in"
                && root.state !== "approved")
            return

        // The SDDM/PAM attempt has already consumed or rejected the
        // one-shot approval path. Invalidate every presentation-side
        // callback from that flow before offering recovery.
        root.flowGeneration += 1
        root.stopFlowTimers()
        retryTimer.stop()

        root.requestInFlight = false
        root.clearDisplayData()

        root.state = "error"
        root.errorKind = "login_failed"
        root.connectionState = "ready"
        root.statusText = qsTr(
            "Die Anmeldung konnte nicht abgeschlossen werden. "
            + "Bitte Passwort verwenden oder bewusst einen neuen Code "
            + "anfordern."
        )

        root.armRetryCooldown(2)
    }

    function loginSucceeded() {
        root.stopFlowTimers()
        retryTimer.stop()
        root.connectionState = "ready"
    }
}
