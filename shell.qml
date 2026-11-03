import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "lib"

// KAKUNIN 確認 - dialog xác nhận đóng cửa sổ được bảo vệ (gọi từ safe-close.sh qua `sumi kakunin`).
// Hợp đồng: thoát mã 0 = Yes (đóng app), mã 1 = No / Esc / bấm ra ngoài.
// Biến môi trường đọc vào: CONFIRM_APP, CONFIRM_TITLE, CONFIRM_WS, CONFIRM_MONITOR (đều tuỳ chọn).
// Chạy độc lập: không cần hub, không đụng mạng; lỗi config thì dùng mặc định.
ShellRoot {
    id: root

    // ===== Config (~/.config/sumi/config.json) + màu Noctalia (~/.config/sumi/colors.json) =====
    SumiColors { id: colors }
    SumiConfig { id: cfg; appId: "kakunin" }

    readonly property string fontTitle: cfg.font("title", "sans-serif")
    readonly property string fontLabel: cfg.font("label", "sans-serif")
    readonly property string fontData: cfg.font("data", "monospace")
    readonly property color dangerColor: "#E63946"

    readonly property real tint: cfg.lookNum("tint", 0, 0.6, 0.12)
    readonly property real inkDarken: cfg.lookNum("inkDarken", 1, 2.5, 1.5)
    readonly property real scanOpacity: cfg.lookNum("scanlineOpacity", 0, 0.2, 0.05)
    readonly property bool scanlinesEnabled: cfg.lookBool("scanlines", true)
    readonly property bool glitchEnabled: cfg.lookBool("glitch", true)
    readonly property real scaleBoost: cfg.lookNum("scaleBoost", 0.5, 2, 1)
    readonly property int bootMs: cfg.optionNum("crtBootMs", 0, 3000, 800)
    readonly property int outroMs: cfg.optionNum("crtOutroMs", 0, 3000, 460)
    readonly property int inputDelayMs: cfg.optionNum("acceptKeysDelayMs", 0, 1000, 180)

    readonly property string appName: Quickshell.env("CONFIRM_APP") || "ứng dụng"
    readonly property string appTitle: Quickshell.env("CONFIRM_TITLE") || ""
    readonly property string appWs: Quickshell.env("CONFIRM_WS") || ""
    readonly property string monName: Quickshell.env("CONFIRM_MONITOR") || ""

    // ===== Màn hình hiện dialog: màn chứa cửa sổ bị đóng (fallback: màn đầu tiên) =====
    readonly property string primaryName: {
        const sc = Quickshell.screens
        for (let i = 0; i < sc.length; i++) if (sc[i].name === monName) return monName
        return sc.length > 0 ? sc[0].name : ""
    }

    // ===== Kết thúc: chạy animation tắt rồi thoát với mã tương ứng =====
    property bool resolving: false
    property int exitCode: 1
    function resolve(accept) {
        if (resolving) return
        resolving = true
        exitCode = accept ? 0 : 1
        exitTimer.restart()
    }
    Timer {
        id: exitTimer
        interval: Math.max(480, root.outroMs + 20)
        repeat: false
        onTriggered: Qt.exit(root.exitCode)
    }

    // ===== Một cửa sổ layer-shell phủ mỗi màn hình; thẻ chỉ hiện ở màn chính =====
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool primary: modelData.name === root.primaryName

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "confirm-close"
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // nền tối; bấm ra ngoài = huỷ
            Rectangle {
                id: dim
                anchors.fill: parent
                color: "#000000"
                opacity: 0
                MouseArea { anchors.fill: parent; onClicked: root.resolve(false) }
                NumberAnimation on opacity { to: 0.5; duration: 180; running: true }
                states: State { name: "out"; when: root.resolving; PropertyChanges { target: dim; opacity: 0 } }
                transitions: Transition { to: "out"; NumberAnimation { property: "opacity"; duration: 380 } }
            }

            View {
                id: card
                visible: win.primary
                anchors.centerIn: parent
                scaleU: Math.max(0.6, Math.min(win.width / 1920, win.height / 1080)) * root.scaleBoost
                closing: root.resolving
                appName: root.appName
                appTitle: root.appTitle
                appWs: root.appWs
                bgColor: colors.adapter.surface
                fgColor: colors.adapter.on_surface
                accentColor: colors.adapter.primary
                dangerColor: root.dangerColor
                fontTitle: root.fontTitle
                fontLabel: root.fontLabel
                fontData: root.fontData
                tint: root.tint
                inkDarken: root.inkDarken
                bootMs: root.bootMs
                outroMs: root.outroMs
                inputDelayMs: root.inputDelayMs
                scanOpacity: root.scanOpacity
                scanlinesEnabled: root.scanlinesEnabled
                glitchEnabled: root.glitchEnabled
                keyYes: cfg.keyFor("yes", "Y")
                keyNo: cfg.keyFor("no", "N")
                keyLeft: cfg.keyFor("nav.left", "A")
                keyRight: cfg.keyFor("nav.right", "D")
                keyConfirm: cfg.keyFor("confirm", "Return")
                onChoiceRequested: (i) => choice = i
                onAccepted: root.resolve(true)
                onRejected: root.resolve(false)
            }
        }
    }
}

