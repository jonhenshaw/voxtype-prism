import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui as Ui

// Theme-native multiline editor used for prompts, dictionaries, samples, and
// results. It keeps the stock TextArea editing semantics while replacing the
// platform chrome with the Omarchy control tokens.
FocusScope {
    id: root

    property alias text: editor.text
    property alias placeholderText: editor.placeholderText
    property alias readOnly: editor.readOnly
    property alias control: editor
    property string accessibleName: "Text editor"
    property string accessibleDescription: ""
    property int maximumLength: 32768
    property int maximumBytes: 0
    property bool showCount: false
    property bool hasError: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color errorColor: Color.urgent
    property real horizontalPadding: Style.spacing.controlPaddingX
    property real verticalPadding: Style.spacing.inputPaddingY
    property bool clampingText: false

    readonly property bool activeEditorFocus: editor.activeFocus
    readonly property bool hovered: hoverHandler.hovered
    readonly property int characterCount: editor.length
    readonly property int byteCount: utf8ByteLength(editor.text)
    readonly property bool overByteLimit: maximumBytes > 0 && byteCount > maximumBytes
    readonly property bool invalid: hasError || overByteLimit

    signal edited()

    function utf8ByteLength(value) {
        const text = String(value || "")
        let bytes = 0
        for (let i = 0; i < text.length; ++i) {
            const code = text.charCodeAt(i)
            if (code <= 0x7f) bytes += 1
            else if (code <= 0x7ff) bytes += 2
            else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
                    && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
                bytes += 4
                ++i
            } else bytes += 3
        }
        return bytes
    }

    implicitWidth: Style.space(320)
    implicitHeight: Style.space(180)
    activeFocusOnTab: true
    onActiveFocusChanged: if (activeFocus) editor.forceActiveFocus()

    Accessible.role: Accessible.EditableText
    Accessible.name: accessibleName
    Accessible.description: accessibleDescription
    Accessible.focusable: true
    Accessible.focused: activeEditorFocus

    Ui.BorderSurface {
        id: frame
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Style.controlFill(root.activeEditorFocus, root.hovered,
            root.foreground, root.invalid ? root.errorColor : root.accent)
        borderSpec: Border.controlSpec(root.invalid ? "focus"
            : (root.activeEditorFocus ? "focus" : (root.hovered ? "hover-cursor" : "normal")),
            root.foreground, root.invalid ? root.errorColor : root.accent)

        HoverHandler { id: hoverHandler }

        QQC.ScrollView {
            id: scrollView
            anchors.fill: parent
            anchors.leftMargin: frame.borderLeft
            anchors.rightMargin: frame.borderRight
            anchors.topMargin: frame.borderTop
            anchors.bottomMargin: frame.borderBottom
                + ((root.showCount || root.maximumBytes > 0) ? countText.height + Style.spacing.sm : 0)
            clip: true
            QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff

            QQC.TextArea {
                id: editor
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                activeFocusOnTab: true
                color: root.foreground
                selectionColor: Style.selectionFillFor(root.foreground, root.accent)
                selectedTextColor: root.foreground
                placeholderTextColor: Qt.darker(root.foreground, 1.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                leftPadding: root.horizontalPadding
                rightPadding: root.horizontalPadding
                topPadding: root.verticalPadding
                bottomPadding: root.verticalPadding
                background: Item {}
                Accessible.name: root.accessibleName
                Accessible.description: root.accessibleDescription
                onTextChanged: {
                    if (!root.clampingText && text.length > root.maximumLength) {
                        root.clampingText = true
                        const oldCursor = cursorPosition
                        text = text.slice(0, root.maximumLength)
                        cursorPosition = Math.min(oldCursor, text.length)
                        root.clampingText = false
                    }
                    if (activeFocus && !root.clampingText) root.edited()
                }
            }
        }

        Text {
            id: countText
            visible: root.showCount || root.maximumBytes > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: frame.borderRight + Style.spacing.controlPaddingX
            anchors.bottomMargin: frame.borderBottom + Style.spacing.sm
            text: root.maximumBytes > 0
                ? (root.byteCount.toLocaleString(Qt.locale(), "f", 0) + " / "
                    + root.maximumBytes.toLocaleString(Qt.locale(), "f", 0) + " bytes"
                    + (root.overByteLimit ? " · limit exceeded" : ""))
                : (root.characterCount.toLocaleString(Qt.locale(), "f", 0)
                    + " / " + root.maximumLength.toLocaleString(Qt.locale(), "f", 0))
            color: root.invalid ? root.errorColor : Qt.darker(root.foreground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
}
