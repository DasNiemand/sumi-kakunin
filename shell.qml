import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "lib"

// KAKUNIN 確認 - đóng cửa sổ đang focus, hỏi xác nhận nếu class khớp OPTION protectedClasses.
// Hai chế độ:
//  - TỰ ĐỘNG (mặc định, `sumi kakunin` gắn thẳng vào keybind): tự hỏi hyprctl cửa sổ đang focus; class không nằm trong
//    protectedClasses thì đóng ngay, nằm trong danh sách thì hiện dialog, Yes mới đóng. Không cần script ngoài.
//  - TƯƠNG THÍCH (có biến môi trường CONFIRM_APP, vd từ safe-close.sh cũ): chỉ hiện dialog, KHÔNG tự đóng cửa sổ.
// Mã thoát: 0 = đã đóng / Yes, 1 = No / Esc / bấm ra ngoài / không có cửa sổ.
// Biến môi trường (chế độ tương thích): CONFIRM_APP, CONFIRM_TITLE, CONFIRM_WS, CONFIRM_MONITOR (đều tuỳ chọn).
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

    readonly property string themePreset: cfg.look("theme", "paper")
    readonly property real tint: cfg.lookNum("tint", 0, 0.6, 0.12)
    readonly property real inkDarken: cfg.lookNum("inkDarken", 1, 2.5, 1.5)
    readonly property real scanOpacity: cfg.lookNum("scanlineOpacity", 0, 0.2, 0.05)
    readonly property bool scanlinesEnabled: cfg.lookBool("scanlines", true)
    readonly property bool glitchEnabled: cfg.lookBool("glitch", true)
    readonly property real scaleBoost: cfg.lookNum("scaleBoost", 0.5, 2, 1)
    readonly property int bootMs: cfg.optionNum("crtBootMs", 0, 3000, 800)
    readonly property int outroMs: cfg.optionNum("crtOutroMs", 0, 3000, 460)
    readonly property int inputDelayMs: cfg.optionNum("acceptKeysDelayMs", 0, 1000, 180)

    // chế độ tương thích khi có CONFIRM_APP; ngược lại tự dò cửa sổ qua hyprctl
    readonly property bool auto: !Quickshell.env("CONFIRM_APP")
    property string appName: Quickshell.env("CONFIRM_APP") || ""
    property string appTitle: Quickshell.env("CONFIRM_TITLE") || ""
    property string appWs: Quickshell.env("CONFIRM_WS") || ""
    property string monName: Quickshell.env("CONFIRM_MONITOR") || ""
    property int monId: -1
    property bool showDialog: !auto       // tự động: chỉ hiện sau khi biết cửa sổ thuộc danh sách bảo vệ
    property bool gotWindow: false

    // ===== Danh sách bảo vệ: glob (chữ, số, _ . * ? -). Chưa đặt = mặc định; [] = không bảo vệ app nào =====
    readonly property var defaultProtected: ["zen*", "Minecraft*"]
    function protectedList() {
        const v = cfg.option("protectedClasses", null)
        if (!Array.isArray(v)) return defaultProtected
        return v.filter(s => typeof s === "string" && /^[A-Za-z0-9_.*?-]{1,64}$/.test(s))
    }
    function globToRe(g) { return new RegExp("^" + g.replace(/\./g, "\\.").replace(/\*/g, ".*").replace(/\?/g, ".") + "$") }
    function isProtected(cls, list) {
        for (let i = 0; i < list.length; i++) if (globToRe(list[i]).test(cls)) return true
        return false
    }

    // ===== Chế độ tự động: đọc cửa sổ focus + danh sách màn hình SONG SONG -> quyết định hỏi hay đóng luôn =====
    property string winAddr: ""
    property bool wantAsk: false
    property bool monDone: false
    property string monJson: ""
    function onWindow(txt) {
        let w = {}
        try { w = JSON.parse(txt) } catch (e) { w = {} }
        const cls = (w && w["class"] !== undefined && w["class"] !== null) ? String(w["class"]) : ""
        gotWindow = true
        if (cls === "") { Qt.exit(1); return }
        appName = cls
        appTitle = w.title ? String(w.title) : ""
        appWs = (w.workspace && w.workspace.name !== undefined) ? String(w.workspace.name) : ""
        monId = (typeof w.monitor === "number") ? w.monitor : -1
        winAddr = (typeof w.address === "string" && /^0x[0-9a-fA-F]+$/.test(w.address)) ? w.address : ""
        if (isProtected(cls, protectedList())) { wantAsk = true; resolveMon() }
        else closeWindow()
    }
    function onMonitors(txt) { monJson = txt; monDone = true; resolveMon() }
    function resolveMon() {
        if (!wantAsk || !monDone) return
        try {
            const a = JSON.parse(monJson)
            for (let i = 0; i < a.length; i++) if (a[i].id === monId) { monName = String(a[i].name); break }
        } catch (e) { }
        showDialog = true
    }
    // Đóng ĐÚNG cửa sổ đã hỏi theo địa chỉ (Lua dispatcher của Hyprland), không phụ thuộc focus/vị trí chuột lúc bấm Yes.
    // Kết quả hyprctl ghi vào /tmp/sumi-kakunin.log.
    function closeWindow() {
        if (winAddr === "") { Qt.exit(1); return }
        closeProc.command = ["sh", "-c",
            "{ echo \"close " + winAddr + "\"; hyprctl dispatch 'hl.dsp.window.close({ window = \"address:" + winAddr + "\" })'; } >>/tmp/sumi-kakunin.log 2>&1"]
        closeProc.running = true
    }
    Process {
        id: activeProc
        command: ["hyprctl", "activewindow", "-j"]
        running: root.auto
        stdout: StdioCollector { onStreamFinished: root.onWindow(this.text) }
    }
    Process {
        id: monProc
        command: ["hyprctl", "monitors", "-j"]
        running: root.auto
        stdout: StdioCollector { onStreamFinished: root.onMonitors(this.text) }
    }
    Process { id: closeProc; onExited: Qt.exit(0) }
    // hyprctl không chạy được / không trả lời thì thoát thay vì treo
    Timer { interval: 3000; running: root.auto; repeat: false; onTriggered: if (!root.gotWindow) Qt.exit(1) }
    // Yes (chế độ tự động): ẩn dialog cho focus trả về cửa sổ rồi mới đóng
    Timer { id: closeDelay; interval: 120; repeat: false; onTriggered: root.closeWindow() }

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
        onTriggered: {
            if (root.auto && root.exitCode === 0) { root.showDialog = false; closeDelay.restart() }
            else Qt.exit(root.exitCode)
        }
    }

    // ===== Một cửa sổ layer-shell phủ mỗi màn hình; thẻ chỉ hiện ở màn chính =====
    Variants {
        model: root.showDialog ? Quickshell.screens : []

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
                appName: root.appName || "ứng dụng"
                appTitle: root.appTitle
                appWs: root.appWs
                bgColor: colors.adapter.surface
                fgColor: colors.adapter.on_surface
                accentColor: colors.adapter.primary
                dangerColor: root.dangerColor
                fontTitle: root.fontTitle
                fontLabel: root.fontLabel
                fontData: root.fontData
                preset: root.themePreset
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

