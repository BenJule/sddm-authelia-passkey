// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

Item {
    id: root

    property var userModelSource
    property int initialIndex: 0
    property bool compactMode: false

    property int selectedIndex: -1
    property string selectedUsername: ""
    property string selectedDisplayName: ""
    property string selectedIcon: ""

    property bool manualMode: false

    property int lastListIndex: -1
    property string lastListUsername: ""
    property string lastListDisplayName: ""
    property string lastListIcon: ""

    signal accountChanged()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Benutzerkonto")

    implicitHeight:
        manualMode
            ? manualColumn.implicitHeight
            : listColumn.implicitHeight

    function chooseAccount(index, username, realName, iconSource) {
        var display =
            realName && realName.length > 0
                ? realName
                : username

        root.manualMode = false
        root.selectedIndex = index
        root.selectedUsername = username || ""
        root.selectedDisplayName = display || ""
        root.selectedIcon = iconSource || ""

        root.lastListIndex = index
        root.lastListUsername = root.selectedUsername
        root.lastListDisplayName = root.selectedDisplayName
        root.lastListIcon = root.selectedIcon

        root.accountChanged()
    }

    function beginManualEntry() {
        root.manualMode = true
        root.selectedIndex = -1
        root.selectedUsername = ""
        root.selectedDisplayName = ""
        root.selectedIcon = ""
        manualField.text = ""
        root.accountChanged()
        Qt.callLater(function() {
            manualField.forceActiveFocus()
        })
    }

    function setManualUsername(value) {
        if (!root.manualMode)
            return

        var clean = value ? value.trim() : ""

        if (root.selectedUsername === clean)
            return

        root.selectedUsername = clean
        root.selectedDisplayName = clean
        root.selectedIcon = ""
        root.accountChanged()
    }

    function showUserList() {
        root.manualMode = false

        root.selectedIndex = root.lastListIndex
        root.selectedUsername = root.lastListUsername
        root.selectedDisplayName = root.lastListDisplayName
        root.selectedIcon = root.lastListIcon

        root.accountChanged()

        Qt.callLater(function() {
            if (userList.currentItem)
                userList.currentItem.forceActiveFocus()
        })
    }

    // Materialize the model once to resolve the initial role values without
    // inventing a second account database.
    Repeater {
        model: root.userModelSource

        delegate: Item {
            required property int index
            required property var model

            visible: false

            Component.onCompleted: {
                if (root.selectedUsername.length === 0
                        && index === root.initialIndex) {
                    root.chooseAccount(
                        index,
                        model.name || "",
                        model.realName || "",
                        model.icon || ""
                    )
                }
            }
        }
    }

    ColumnLayout {
        id: listColumn

        width: root.width
        visible: !root.manualMode
        spacing: 6

        QQC2.Label {
            Layout.fillWidth: true
            text: qsTr("Benutzerkonto")
            color: "white"
            opacity: 0.76
            font.pixelSize: 12
            Accessible.ignored: true
        }

        ListView {
            id: userList

            Layout.fillWidth: true
            Layout.preferredHeight:
                Math.min(
                    root.compactMode ? 96 : 132,
                    Math.max(
                        root.compactMode ? 40 : 44,
                        contentHeight
                    )
                )

            model: root.userModelSource
            clip: true
            spacing: 2
            currentIndex: root.selectedIndex

            Accessible.role: Accessible.List
            Accessible.name: qsTr("Benutzerkonten")

            delegate: QQC2.ItemDelegate {
                id: userDelegate

                required property int index
                required property var model

                readonly property string accountName:
                    model.name || ""

                readonly property string accountRealName:
                    model.realName || ""

                readonly property string accountIcon:
                    model.icon || ""

                width: ListView.view.width
                height: root.compactMode ? 40 : 44

                highlighted:
                    !root.manualMode
                    && index === root.selectedIndex

                Accessible.role: Accessible.ListItem
                Accessible.name:
                    accountRealName.length > 0
                        ? accountRealName
                        : accountName
                Accessible.description:
                    accountRealName.length > 0
                    && accountRealName !== accountName
                        ? qsTr("Benutzername: %1").arg(accountName)
                        : ""
                Accessible.selected: highlighted
                Accessible.focusable: true

                Accessible.onPressAction: root.chooseAccount(
                    index,
                    accountName,
                    accountRealName,
                    accountIcon
                )

                onClicked: root.chooseAccount(
                    index,
                    accountName,
                    accountRealName,
                    accountIcon
                )

                contentItem: RowLayout {
                    spacing: 10

                    UserAvatar {
                        Layout.preferredWidth:
                            root.compactMode ? 28 : 32
                        Layout.preferredHeight:
                            root.compactMode ? 28 : 32
                        iconSource: userDelegate.accountIcon
                        label:
                            userDelegate.accountRealName.length > 0
                                ? userDelegate.accountRealName
                                : userDelegate.accountName
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        QQC2.Label {
                            Layout.fillWidth: true
                            text:
                                userDelegate.accountRealName.length > 0
                                    ? userDelegate.accountRealName
                                    : userDelegate.accountName
                            color: "white"
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            font.bold: true
                            Accessible.ignored: true
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: userDelegate.accountName
                            color: "white"
                            opacity: 0.58
                            elide: Text.ElideRight
                            font.pixelSize: 10
                            Accessible.ignored: true
                        }
                    }
                }
            }
        }

        QQC2.Button {
            Layout.alignment: Qt.AlignLeft
            text: qsTr("Anderes Konto eingeben")
            onClicked: root.beginManualEntry()
        }
    }

    ColumnLayout {
        id: manualColumn

        width: root.width
        visible: root.manualMode
        spacing: 7

        QQC2.Label {
            Layout.fillWidth: true
            text: qsTr("Benutzername")
            color: "white"
            opacity: 0.76
            font.pixelSize: 12
            Accessible.ignored: true
        }

        QQC2.TextField {
            id: manualField

            Layout.fillWidth: true
            placeholderText: qsTr("Benutzername eingeben")

            Accessible.name: qsTr("Benutzername")
            Accessible.description:
                qsTr("Benutzerkonto manuell eingeben")

            onTextChanged: root.setManualUsername(text)
        }

        QQC2.Button {
            text: qsTr("Zur Benutzerliste")
            onClicked: root.showUserList()
        }
    }
}
