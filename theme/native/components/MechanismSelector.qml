// SPDX-License-Identifier: GPL-3.0-or-later
//
// v2.13.0: the first visible step of the generic mechanism-selection
// UI (docs/generic-mechanism-model.md) needs a small, real state
// machine deciding which mechanism's own controls are currently shown
// and safely switching between them. Extracted into its own component
// - like SmartphoneFlowController - so this security-adjacent
// switching logic (in particular: never leaving a stale live
// smartphone flow running after switching away from it) is
// independently unit testable, rather than living inline in Main.qml
// where it could not be.
//
// This component NEVER makes or gates an authentication decision - it
// only tracks which already-existing, already-authorized presentation
// area is currently shown. It reuses SmartphoneFlowController's own
// cancel/supersede semantics (live/cancelCurrent) rather than
// inventing a second cancellation path.
import QtQuick

QtObject {
    id: root

    property var mechanismModel
    property var smartphoneFlow

    property string selectedMechanism: "password"

    // User-driven selection (e.g. a selector tab click). Refuses to
    // select a mechanism that isn't ready right now - mirrors the
    // disabled state the selector UI itself renders - and cancels any
    // live smartphone flow being switched away from.
    function selectMechanism(mechanismId) {
        if (mechanismId === root.selectedMechanism)
            return

        var target =
            root.mechanismModel
                ? root.mechanismModel.mechanism(mechanismId)
                : null

        if (!target || !target.ready)
            return

        root._leaveCurrentMechanism()

        root.selectedMechanism = mechanismId
    }

    // The single safe path back to password - used both by the
    // automatic fallback below and by explicit "leave the smartphone
    // area" actions (Escape, closing the panel, a real account
    // change). A no-op if password is already selected.
    function returnToPassword() {
        if (root.selectedMechanism === "password")
            return

        root._leaveCurrentMechanism()

        root.selectedMechanism = "password"
    }

    // Call whenever a mechanism's live readiness may have changed
    // (Main.qml wires this to mechanismModel.onEidpReadyChanged -
    // currently the only selectable mechanism whose readiness can
    // change at all; password is always ready). Fails closed: if the
    // currently selected mechanism is no longer ready, never leave it
    // silently selected.
    function reconsiderCurrentMechanism() {
        var current =
            root.mechanismModel
                ? root.mechanismModel.mechanism(
                    root.selectedMechanism
                )
                : null

        if (current && current.ready)
            return

        root.returnToPassword()
    }

    function _leaveCurrentMechanism() {
        if (
            root.selectedMechanism === "eidp"
            && root.smartphoneFlow
            && root.smartphoneFlow.live
        )
            root.smartphoneFlow.cancelCurrent(false)
    }
}
