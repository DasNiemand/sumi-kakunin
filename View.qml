import QtQuick
import QtQuick.Shapes
import "lib"

// KAKUNIN 確認 - giao diện thẻ xác nhận (View thuần: không Process, không ghi file, không thoát tiến trình).
// Hành động ra qua signal accepted() / rejected(); shell.qml nối signal với exit code.
// Sinh từ confirm/shell.qml gốc (ConfirmCard) - chỉ đổi: palette -> SumiTheme, font -> vai trò, timing/phím -> config.
Item {
    id: card

    property bool closing: false
    property string appName: ""
    property string appTitle: ""
    property string appWs: ""
    property string bgColor: "#14161a"
    property string fgColor: "#e3e1e6"
    property string accentColor: "#a9b8f0"
    property string dangerColor: "#E63946"
    property string fontTitle: "sans-serif"     // vai trò title (tên app cỡ lớn)
    property string fontLabel: "sans-serif"     // vai trò label
    property string fontData: "monospace"       // vai trò data
    property bool previewMode: false            // true: không nhận phím, không steal focus (dùng trong hub)
    property string preset: "paper"             // theme: paper|ink|mono-white|mono-black|accent|follow
    property real tint: 0.12
    property real inkDarken: 1.5
    property int bootMs: 800
    property int outroMs: 460
    property int inputDelayMs: 180
    property real scanOpacity: 0.05
    property bool scanlinesEnabled: true
    property bool glitchEnabled: true
    property string keyYes: "Y"
    property string keyNo: "N"
    property string keyLeft: "A"
    property string keyRight: "D"
    property string keyConfirm: "Return"
    property real scaleU: 1
    property int choice: 1            // 0 = Yes, 1 = No (mặc định No cho an toàn)
    signal choiceRequested(int index)
    signal accepted()
    signal rejected()

    function px(n) { return Math.max(1, Math.round(n * scaleU)) }
    function fs(n) { return Math.max(8, Math.round(n * scaleU)) }
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    function mix(a, b, t) { return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, 1) }
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    width: px(1000)
    height: px(600)

    // ----- bảng màu giấy/mực: công thức nằm ở lib/SumiTheme.qml -----
    SumiTheme { id: th; bgColor: card.bgColor; fgColor: card.fgColor; accentColor: card.accentColor; tint: card.tint; inkDarken: card.inkDarken; preset: card.preset }
    SumiKeyMap { id: km }
    readonly property color cDanger: dangerColor
    readonly property color paper: th.paper
    readonly property color ink: th.ink
    readonly property color soft: th.soft
    readonly property color rule: th.rule
    readonly property color wash: th.wash
    readonly property color ghostB: th.ghostB

    // ----- bật máy (CRT) / tắt máy -----
    property real bp: 0
    property real outP: 0
    property bool inputReady: false
    readonly property real lineW: Math.min(1, bp / 0.28)
    readonly property real openH: Math.max(0, Math.min(1, (bp - 0.28) / 0.42))
    readonly property real contentP: clamp01((bp - 0.55) / 0.45)
    readonly property real vCollapse: clamp01((outP - 0.34) / 0.40)
    readonly property real hCollapse: clamp01((outP - 0.74) / 0.26)
    readonly property bool textOn: !closing && contentP > 0.05

    Component.onCompleted: { bootAnim.start(); inputTimer.start() }
    onClosingChanged: { if (closing) { outP = 0; outAnim.start() } }
    NumberAnimation { id: bootAnim; target: card; property: "bp"; from: 0; to: 1; duration: card.bootMs; easing.type: Easing.Linear }
    NumberAnimation { id: outAnim; target: card; property: "outP"; from: 0; to: 1; duration: card.outroMs; easing.type: Easing.Linear }
    Timer { id: inputTimer; interval: card.inputDelayMs; repeat: false; onTriggered: card.inputReady = true }

    // ----- glitch + luồng hex + giờ -----
    property bool glitchOn: false
    property real gdx: 3
    readonly property bool glitchNow: glitchOn || (closing && outP < 0.34)
    readonly property real gdxNow: closing ? px(12) : gdx
    Timer {
        id: glitchTimer
        interval: 2200
        repeat: true
        running: card.glitchEnabled && card.contentP >= 1 && !card.closing
        onTriggered: {
            card.gdx = (2 + Math.random() * 4) * card.scaleU
            card.glitchOn = true
            glitchOff.restart()
            glitchTimer.interval = 1800 + Math.random() * 3200
        }
    }
    Timer { id: glitchOff; interval: 110; repeat: false; onTriggered: card.glitchOn = false }

    property string hexStream: "0x5E1F 0C21 9BD4"
    function randHex() {
        let s = "0x"
        for (let g = 0; g < 3; g++) {
            if (g > 0) s += " "
            for (let i = 0; i < 4; i++) s += "0123456789ABCDEF".charAt(Math.floor(Math.random() * 16))
        }
        return s
    }
    Timer { interval: 130; repeat: true; running: true; onTriggered: card.hexStream = card.randHex() }
    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: card.now = new Date() }

    // ----- phím -----
    //  A/D/W/S/←/→/↑/↓/Tab: đổi lựa chọn | Space/Enter: xác nhận lựa chọn | Y: Yes | N, Esc: No
    focus: !card.previewMode
    Keys.onPressed: (event) => {
        if (card.previewMode || !inputReady || closing) return
        const k = event.key
        const ar = event.isAutoRepeat
        // Phím chính cấu hình được (yes/no/nav/confirm); Esc luôn là huỷ. Các phím phụ bên dưới cố định.
        const isNo = (k === Qt.Key_Escape) || km.match(event, card.keyNo)
        const isYes = km.match(event, card.keyYes)
        const isNav = km.match(event, card.keyLeft) || km.match(event, card.keyRight)
            || k === Qt.Key_W || k === Qt.Key_S
            || k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down
            || k === Qt.Key_Tab || k === Qt.Key_Backtab
        const isAct = km.match(event, card.keyConfirm) || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space
        if (isNo) { if (!ar) card.rejected(); event.accepted = true }
        else if (isYes) { if (!ar) card.accepted(); event.accepted = true }
        else if (isNav) { card.choiceRequested(1 - card.choice); event.accepted = true }
        else if (isAct) {
            if (!ar) { if (card.choice === 0) card.accepted(); else card.rejected() }
            event.accepted = true
        }
    }

    // ==================================================================
    // Khung CRT
    // ==================================================================
    Item {
        id: clipper
        anchors.centerIn: parent
        width: Math.max(0, card.width * card.lineW * (1 - card.hCollapse))
        height: card.bp <= 0 ? 0 : Math.max(px(3), card.height * card.openH * (1 - card.vCollapse))
        clip: true
        opacity: card.bp < 0.04 ? 0 : (card.bp < 0.4 && Math.floor(card.bp * 70) % 2 === 1) ? 0.5 : 1

        Rectangle { anchors.fill: parent; color: card.ink; visible: clipper.height < px(8) }

        Item {
            id: inner
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: (card.closing && card.outP < 0.34) ? (Math.random() - 0.5) * px(24) : 0
            width: card.width
            height: card.height
            readonly property real m: px(26)

            // nền giấy + khung vát góc dưới phải
            Shape {
                anchors.fill: parent
                ShapePath {
                    id: bodySP
                    readonly property real c: px(44)
                    fillColor: card.paper
                    strokeColor: card.ink
                    strokeWidth: 1.5
                    startX: 0; startY: 0
                    PathLine { x: inner.width; y: 0 }
                    PathLine { x: inner.width; y: inner.height - bodySP.c }
                    PathLine { x: inner.width - bodySP.c; y: inner.height }
                    PathLine { x: 0; y: inner.height }
                    PathLine { x: 0; y: 0 }
                }
            }

            // ---------- thanh trên ----------
            Item {
                id: bar
                x: inner.m; y: px(18)
                width: inner.width - 2 * inner.m; height: px(34)
                opacity: card.contentP
                Rectangle {
                    width: px(130); height: parent.height; color: card.ink
                    Text { anchors.centerIn: parent; text: "CONFIRM"; color: card.paper
                        font.family: card.fontData; font.pixelSize: fs(15); font.bold: true; font.letterSpacing: 3 }
                }
                Text {
                    x: px(148); anchors.verticalCenter: parent.verticalCenter
                    text: "CLOSE.REQUEST"
                    color: card.soft
                    font.family: card.fontData; font.pixelSize: fs(14); font.letterSpacing: 2
                }
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: px(40)
                    text: card.hexStream
                    color: card.soft
                    font.family: card.fontData; font.pixelSize: fs(13); font.letterSpacing: 1
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(card.now, "HH:mm")
                    color: card.ink
                    font.family: card.fontData; font.pixelSize: fs(18); font.bold: true
                }
                Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: -px(8); width: parent.width; height: 1; color: card.rule }
            }

            // ---------- cột trái: khoá pixel ----------
            Rectangle {
                id: field
                x: inner.m; y: px(76)
                width: px(262); height: inner.height - px(76) - px(76)
                color: card.wash
                opacity: card.contentP

                Repeater {
                    model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                    delegate: Text {
                        required property var modelData
                        x: modelData[0] === 0 ? px(10) : field.width - width - px(10)
                        y: modelData[1] === 0 ? px(6) : field.height - height - px(6)
                        text: "+"
                        color: card.soft
                        font.family: card.fontData; font.pixelSize: fs(22)
                    }
                }

                // khoá: 11 x 12 ô; chọn Yes thì quai khoá nâng lên (như đang mở)
                Item {
                    id: lock
                    readonly property real cs: px(15)
                    readonly property var rows: [
                        "...XXXXX...", "..XX...XX..", "..X.....X..", "..X.....X..", "..X.....X..",
                        "XXXXXXXXXXX", "XXXXXXXXXXX", "XXXXX.XXXXX", "XXXXX.XXXXX", "XXXXX.XXXXX",
                        "XXXXXXXXXXX", "XXXXXXXXXXX"
                    ]
                    x: (field.width - 11 * cs) / 2
                    y: px(54)
                    Repeater {
                        model: 12 * 11
                        delegate: Rectangle {
                            required property int index
                            readonly property int r: Math.floor(index / 11)
                            readonly property int c: index % 11
                            visible: lock.rows[r].charAt(c) === "X"
                            x: c * lock.cs
                            y: r * lock.cs - (r < 5 && card.choice === 0 ? lock.cs * 1.7 : 0)
                            width: lock.cs - 1; height: lock.cs - 1
                            color: (r >= 7 && r <= 9 && c === 5) ? card.cDanger : card.ink
                            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - px(112)
                    text: "TWO-STEP GUARD"
                    color: card.ink
                    font.family: card.fontData; font.pixelSize: fs(14); font.bold: true; font.letterSpacing: 2
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - px(88)
                    text: card.choice === 0 ? "RELEASING" : "ARMED"
                    color: card.choice === 0 ? card.cDanger : card.soft
                    font.family: card.fontData; font.pixelSize: fs(13); font.letterSpacing: 3
                }
            }

            // ---------- cột phải ----------
            Item {
                id: rc
                x: field.x + field.width + px(28); y: px(76)
                width: inner.width - x - inner.m
                height: field.height

                Rectangle { width: parent.width; height: 1; color: card.ink }

                // tên app + bóng tách kênh khi glitch
                Text {
                    x: px(2) - card.gdxNow; y: px(6); width: rc.width; height: px(92)
                    verticalAlignment: Text.AlignVCenter
                    visible: card.glitchNow && card.textOn
                    text: titleText.text
                    color: card.cDanger; opacity: 0.75
                    font.family: card.fontTitle; font.bold: true
                    font.pixelSize: fs(76); fontSizeMode: Text.Fit; minimumPixelSize: fs(28)
                }
                Text {
                    x: px(2) + card.gdxNow; y: px(6); width: rc.width; height: px(92)
                    verticalAlignment: Text.AlignVCenter
                    visible: card.glitchNow && card.textOn
                    text: titleText.text
                    color: card.ghostB; opacity: 0.75
                    font.family: card.fontTitle; font.bold: true
                    font.pixelSize: fs(76); fontSizeMode: Text.Fit; minimumPixelSize: fs(28)
                }
                ScrambleText {
                    id: titleText
                    x: px(2); y: px(6); width: rc.width; height: px(92)
                    full: card.appName.toUpperCase()
                    active: card.textOn
                    color: card.ink
                    verticalAlignment: Text.AlignVCenter
                    font.family: card.fontTitle; font.bold: true
                    font.pixelSize: fs(76); fontSizeMode: Text.Fit; minimumPixelSize: fs(28)
                }
                ScrambleText {
                    anchors.right: parent.right
                    y: px(100)
                    full: "PROTECTED APPLICATION"
                    active: card.textOn
                    color: card.ink
                    font.family: card.fontLabel; font.pixelSize: fs(14); font.bold: true; font.letterSpacing: 1.5
                }
                Rectangle { y: px(124); width: parent.width; height: 1; color: card.ink }

                Text {
                    y: px(136); width: parent.width
                    opacity: card.contentP
                    text: "Close this window? Unsaved work may be lost."
                    color: card.ink
                    font.family: card.fontLabel; font.pixelSize: fs(19)
                }

                // thông tin thật của cửa sổ
                Repeater {
                    model: [
                        ["CLASS", card.appName],
                        ["TITLE", card.appTitle !== "" ? card.appTitle : "-"],
                        ["WORKSPACE", card.appWs !== "" ? card.appWs : "-"]
                    ]
                    delegate: Item {
                        required property int index
                        required property var modelData
                        y: px(176) + index * px(38)
                        width: rc.width; height: px(38)
                        opacity: card.contentP
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]
                            color: card.soft
                            font.family: card.fontLabel; font.pixelSize: fs(15); font.letterSpacing: 1.5
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - px(150)
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: modelData[1]
                            color: card.ink
                            font.family: card.fontData; font.pixelSize: fs(16); font.bold: true
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: card.rule; opacity: 0.7 }
                    }
                }

                // Yes / No (thanh chọn tối kiểu NieR)
                Item {
                    id: list
                    y: rc.height - px(112) - px(14)
                    width: rc.width; height: px(112)
                    opacity: card.contentP
                    Rectangle { width: parent.width; height: 1; color: card.ink }
                    Repeater {
                        model: [ { label: "Yes, close it", key: "Y" }, { label: "No, keep it open", key: "N" } ]
                        delegate: Item {
                            id: row
                            required property int index
                            required property var modelData
                            readonly property bool sel: card.choice === index
                            y: 1 + index * px(54)
                            width: list.width; height: px(54)
                            Rectangle {
                                x: row.sel ? 0 : -px(8)
                                width: parent.width; height: parent.height - 1
                                color: row.sel ? card.ink : (rowMouse.containsMouse ? card.wash : "transparent")
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 110 } }
                            }
                            Text {
                                x: px(16); anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.label
                                color: row.sel ? card.paper : card.ink
                                font.family: card.fontLabel; font.pixelSize: fs(22); font.bold: true
                                Behavior on color { ColorAnimation { duration: 110 } }
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: px(16)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "[" + row.modelData.key + "]"
                                color: row.sel ? card.paper : card.soft
                                font.family: card.fontData; font.pixelSize: fs(18); font.bold: true
                                Behavior on color { ColorAnimation { duration: 110 } }
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: card.choiceRequested(row.index)
                                onClicked: row.index === 0 ? card.accepted() : card.rejected()
                            }
                        }
                    }
                    Rectangle { y: 1 + 2 * px(54); width: parent.width; height: 1; color: card.ink }
                }
            }

            // ---------- chân trang ----------
            Item {
                x: inner.m; y: inner.height - px(60)
                width: inner.width - 2 * inner.m - px(40); height: px(30)
                opacity: card.contentP
                Row {
                    spacing: px(28)
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        spacing: px(10)
                        Rectangle {
                            width: px(24); height: width; radius: width / 2
                            color: "transparent"; border.width: 2; border.color: card.ink
                            Text { anchors.centerIn: parent; text: "×"; color: card.ink; font.pixelSize: fs(17); font.bold: true }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "CONFIRM"; color: card.ink
                            font.family: card.fontLabel; font.pixelSize: fs(16); font.bold: true; font.letterSpacing: 1 }
                    }
                    Row {
                        spacing: px(10)
                        Rectangle {
                            width: px(24); height: width; radius: width / 2
                            color: "transparent"; border.width: 2; border.color: card.ink
                            Rectangle { anchors.centerIn: parent; width: px(8); height: width; radius: width / 2; color: card.ink }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "BACK"; color: card.ink
                            font.family: card.fontLabel; font.pixelSize: fs(16); font.bold: true; font.letterSpacing: 1 }
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "A/D  SELECT      SPACE  CONFIRM      ESC  CANCEL"
                    color: card.soft
                    font.family: card.fontData; font.pixelSize: fs(13); font.letterSpacing: 1
                }
            }

            // ---------- scanline + thanh quét + flash lúc tắt ----------
            Repeater {
                model: card.scanlinesEnabled ? Math.ceil(inner.height / Math.max(3, Math.round(3 * card.scaleU))) : 0
                delegate: Rectangle {
                    required property int index
                    y: index * Math.max(3, Math.round(3 * card.scaleU))
                    width: inner.width; height: 1
                    color: card.ink; opacity: card.scanOpacity; z: 50
                }
            }
            Rectangle {
                id: scanBar
                width: inner.width; height: px(110); z: 49
                visible: card.contentP > 0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.07) }
                    GradientStop { position: 1.0; color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.0) }
                }
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: card.contentP > 0
                    NumberAnimation { from: -scanBar.height; to: inner.height; duration: 2800; easing.type: Easing.Linear }
                    PauseAnimation { duration: 900 }
                }
            }
            Rectangle {
                anchors.fill: parent; z: 60
                color: Qt.lighter(card.paper, 1.5)
                opacity: card.closing ? Math.max(0, 0.75 - Math.abs(card.outP - 0.38) * 5) : 0
            }
            Rectangle {
                anchors.fill: parent; z: 61
                color: card.ink
                opacity: card.closing ? card.vCollapse * 0.8 : 0
            }
        }
    }
}
