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

    implicitHeight:
        manualMode
            ? manualColumn.implicitHeight
            : listColumn.implicitHeight

    function chooseAccount(
        index,
        username,
        realName,
        iconSource
    ) {
        var display =
            realName
            && realName.length > 0
                ? realName
                : username

        root.manualMode = false

        root.selectedIndex = index
        root.selectedUsername = username || ""
        root.selectedDisplayName = display || ""
        root.selectedIcon = iconSource || ""

        root.lastListIndex = index
        root.lastListUsername =
            root.selectedUsername
        root.lastListDisplayName =
            root.selectedDisplayName
        root.lastListIcon =
            root.selectedIcon

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

        var clean =
            value
                ? value.trim()
                : ""

        if (root.selectedUsername === clean)
            return

        root.selectedUsername = clean
        root.selectedDisplayName = clean
        root.selectedIcon = ""

        root.accountChanged()
    }

    function showUserList() {
        root.manualMode = false

        root.selectedIndex =
            root.lastListIndex

        root.selectedUsername =
            root.lastListUsername

        root.selectedDisplayName =
            root.lastListDisplayName

        root.selectedIcon =
            root.lastListIcon

        root.accountChanged()
    }

    Repeater {
        model: root.userModelSource

        delegate: Item {
            required property int index
            required property var model

            visible: false

            Component.onCompleted: {
                if (
                    root.selectedUsername.length === 0
                    && index === root.initialIndex
                ) {
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

            text: qsTr("Konto")

            color: "#7e90a3"

            font.pixelSize: 10
            font.weight: Font.Medium
        }

        Rectangle {
            Layout.fillWidth: true

            Layout.preferredHeight:
                Math.min(
                    root.compactMode
                        ? 102
                        : 132,
                    Math.max(
                        root.compactMode
                            ? 46
                            : 50,
                        userList.contentHeight
                            + 8
                    )
                )

            radius: 12

            color: Qt.rgba(0.035, 0.055, 0.078, 0.86)

            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.075)

            ListView {
                id: userList

                anchors.fill: parent
                anchors.margins: 4

                model: root.userModelSource

                clip: true
                spacing: 3

                currentIndex:
                    root.selectedIndex

                delegate: QQC2.ItemDelegate {
                    id: accountDelegate

                    required property int index
                    required property var model

                    readonly property string accountName:
                        model.name || ""

                    readonly property string accountRealName:
                        model.realName || ""

                    readonly property string accountIcon:
                        model.icon || ""

                    width: ListView.view.width

                    height:
                        root.compactMode
                            ? 44
                            : 48

                    highlighted:
                        !root.manualMode
                        && index
                            === root.selectedIndex

                    onClicked:
                        root.chooseAccount(
                            index,
                            accountName,
                            accountRealName,
                            accountIcon
                        )

                    background: Rectangle {
                        radius: 9

                        color:
                            accountDelegate.highlighted
                                ? Qt.rgba(
                                    0.20,
                                    0.46,
                                    0.88,
                                    0.26
                                )
                                : accountDelegate.hovered
                                    ? Qt.rgba(
                                        1,
                                        1,
                                        1,
                                        0.05
                                    )
                                    : "transparent"

                        border.width:
                            accountDelegate.highlighted
                                ? 1
                                : 0

                        border.color:
                            Qt.rgba(
                                0.35,
                                0.62,
                                1,
                                0.42
                            )
                    }

                    contentItem: RowLayout {
                        spacing: 9

                        UserAvatar {
                            Layout.preferredWidth:
                                root.compactMode
                                    ? 30
                                    : 34

                            Layout.preferredHeight:
                                root.compactMode
                                    ? 30
                                    : 34

                            iconSource:
                                accountDelegate.accountIcon

                            label:
                                accountDelegate.accountName
                        }

                        ColumnLayout {
                            Layout.fillWidth: true

                            spacing: 0

                            QQC2.Label {
                                Layout.fillWidth: true

                                text:
                                    accountDelegate.accountName

                                color: "#f2f6fa"

                                elide: Text.ElideRight

                                font.pixelSize: 12
                                font.bold: true
                            }

                            QQC2.Label {
                                Layout.fillWidth: true

                                visible:
                                    accountDelegate
                                        .accountRealName
                                        .length > 0
                                    && accountDelegate
                                        .accountRealName
                                        !== accountDelegate
                                            .accountName

                                text:
                                    accountDelegate
                                        .accountRealName

                                color: "#75879a"

                                elide: Text.ElideRight

                                font.pixelSize: 9
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7

                            visible:
                                accountDelegate.highlighted

                            radius: 4
                            color: "#64a3ff"
                        }
                    }
                }
            }
        }

        PolishedButton {
            compact: true

            Layout.alignment: Qt.AlignLeft

            text:
                qsTr(
                    "Anderes Konto"
                )

            onClicked:
                root.beginManualEntry()
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

            color: "#7e90a3"

            font.pixelSize: 10
            font.weight: Font.Medium
        }

        PolishedTextField {
            id: manualField

            Layout.fillWidth: true

            placeholderText:
                qsTr(
                    "Benutzername eingeben"
                )

            onTextChanged:
                root.setManualUsername(text)
        }

        PolishedButton {
            compact: true

            text:
                qsTr(
                    "Zur Kontoauswahl"
                )

            onClicked:
                root.showUserList()
        }
    }
}
