// SPDX-License-Identifier: GPL-3.0-or-later
//
// A first real step of v3.0.0's generic mechanism-selection framework
// (see docs/mechanism-selection.md and docs/generic-mechanism-model.md):
// a single, stable, documented data model listing every authentication
// mechanism this project knows about - PASSWORD, PASSKEY, EIDP,
// SMARTCARD - with real, capability-derived availability/readiness
// state, rather than each mechanism's UI being wired to its own ad-hoc
// property.
//
// This model NEVER makes or gates an authentication decision - it only
// describes what the UI may safely *offer*. The broker/PAM stack
// remains the sole authentication authority regardless of anything
// exposed here (the same invariant docs/capability-negotiation.md
// established for the raw /capabilities signals this model is built
// from).
//
// "kind" distinguishes two fundamentally different interaction shapes:
//   - "actionable": the user explicitly starts this mechanism (a
//     button/click), e.g. password or the smartphone/EIdP flow.
//   - "ambient": the mechanism has no start action at all and simply
//     runs silently in the background ahead of the other PAM modules -
//     currently only PASSKEY (pam_u2f.so), which is tried before both
//     other paths in PAM (see docs/fido2.md). An "ambient" mechanism is
//     never rendered as a button; at most as an informational hint.
//
// "available" is a static-ish capability fact (could this mechanism
// ever work on this system at all); "ready" is the live, currently-
// true readiness (could it work right now). For PASSWORD these are
// always true; for EIDP/PASSKEY they come from the real /capabilities
// signals (oidcReady/fido2Wired, polled every 20s); for SMARTCARD both
// are always false - this project implements no smartcard/PKCS#11
// support whatsoever (see docs/capability-negotiation.md).
import QtQuick

QtObject {
    id: root

    // The existing SmartphoneFlowController instance this model reads
    // its real capability signals from - never duplicates or caches
    // them independently.
    property var smartphoneFlow

    readonly property bool eidpReady:
        !!(smartphoneFlow && smartphoneFlow.oidcReady)

    readonly property bool passkeyReady:
        !!(smartphoneFlow && smartphoneFlow.fido2Wired)

    readonly property var mechanisms: [
        {
            id: "password",
            displayName: qsTr("Passwort"),
            kind: "actionable",
            available: true,
            ready: true,
            statusHint: ""
        },
        {
            id: "eidp",
            displayName: qsTr("Smartphone"),
            kind: "actionable",
            available: true,
            ready: root.eidpReady,
            statusHint:
                root.eidpReady
                    ? ""
                    : qsTr("Smartphone-Anmeldung derzeit nicht erreichbar")
        },
        {
            id: "passkey",
            displayName: qsTr("Hardware-Sicherheitsschlüssel"),
            kind: "ambient",
            available: root.passkeyReady,
            ready: root.passkeyReady,
            statusHint:
                root.passkeyReady
                    ? qsTr("Hardware-Sicherheitsschlüssel verfügbar - einfach berühren")
                    : ""
        },
        {
            id: "smartcard",
            displayName: qsTr("Smartcard"),
            kind: "actionable",
            available: false,
            ready: false,
            statusHint: ""
        }
    ]

    // Looks up one mechanism by id. Returns null for an unknown id
    // rather than throwing, so a caller can safely check the result
    // before use.
    function mechanism(mechanismId) {
        for (var i = 0; i < mechanisms.length; i++) {
            if (mechanisms[i].id === mechanismId)
                return mechanisms[i]
        }
        return null
    }
}
