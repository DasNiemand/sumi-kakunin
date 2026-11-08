#!/bin/bash
# kakunin.sh: điểm vào của `sumi kakunin` (manifest "run"). Ba lớp:
#   1. FILTER  - đọc cửa sổ đang focus + protectedClasses. Chỉ đọc, không làm gì, không chạy Quickshell.
#   2. EXECUTE - class không khớp danh sách  -> đóng cửa sổ ngay (không có dialog, không khởi động Quickshell).
#   3. DIALOG  - class khớp danh sách        -> mới chạy Quickshell hiện dialog; Yes mới đóng.
# Cửa sổ luôn được đóng theo ĐỊA CHỈ đã đọc ở lớp 1, nên lia chuột/đổi focus trong lúc hỏi không làm đóng nhầm.
# Danh sách: ~/.config/sumi/config.json -> apps.kakunin.options.protectedClasses (chỉnh trong hub: OPTIONS của kakunin).
#   - Chưa đặt / file thiếu / JSON hỏng : mặc định zen* và Minecraft*
#   - Đặt thành []                       : không bảo vệ app nào
# Mỗi mục là glob (chữ, số và _ . * ? -); mục sai định dạng bị bỏ qua.
# Mã thoát: 0 = đã đóng, 1 = không đóng (No/Esc, không có cửa sổ, không đọc được hyprctl).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/sumi/config.json"
KLOG="${SUMI_KAKUNIN_LOG:-/tmp/sumi-kakunin.log}"
PROTECTED=('zen*' 'Minecraft*')

# ---------- 1. FILTER ----------
load_protected() {
    local out line first=1
    out="$(jq -r '
        (.apps.kakunin.options.protectedClasses) as $p
        | if ($p | type) == "array"
          then "SET", ($p[] | select(type == "string" and test("^[A-Za-z0-9_.*?-]{1,64}$")))
          else "UNSET" end' "$CFG" 2>/dev/null)" || return 0
    [[ "$out" == SET* ]] || return 0
    PROTECTED=()
    while IFS= read -r line; do
        if (( first )); then first=0; continue; fi
        [[ -n "$line" ]] && PROTECTED+=("$line")
    done <<<"$out"
}
is_protected() {
    local p
    for p in "${PROTECTED[@]}"; do
        # shellcheck disable=SC2254
        case "$1" in $p) return 0 ;; esac
    done
    return 1
}

WIN_JSON="$(hyprctl activewindow -j 2>/dev/null)" || exit 1
ACTIVE_CLASS="$(jq -r '.class // empty' <<<"$WIN_JSON" 2>/dev/null)"
ADDR="$(jq -r '.address // empty' <<<"$WIN_JSON" 2>/dev/null)"
[[ -n "$ACTIVE_CLASS" && "$ADDR" =~ ^0x[0-9a-fA-F]+$ ]] || exit 1
load_protected

# ---------- 2. EXECUTE ----------
close_window() {
    { echo "close $ADDR ($ACTIVE_CLASS)"; hyprctl dispatch "hl.dsp.window.close({ window = \"address:$ADDR\" })"; } >>"$KLOG" 2>&1
}
if ! is_protected "$ACTIVE_CLASS"; then
    close_window
    exit 0
fi

# ---------- 3. DIALOG ----------
# Không cho mở nhiều dialog cùng lúc (giữ phím)
pgrep -f -- "-p $DIR/shell\.qml" >/dev/null && exit 1

MON_ID="$(jq -r '.monitor // -1' <<<"$WIN_JSON")"
CONFIRM_MONITOR="$(hyprctl monitors -j 2>/dev/null | jq -r --argjson id "$MON_ID" '.[] | select(.id == $id) | .name' 2>/dev/null | head -n1)"
CONFIRM_APP="$ACTIVE_CLASS" \
CONFIRM_TITLE="$(jq -r '.title // empty' <<<"$WIN_JSON")" \
CONFIRM_WS="$(jq -r '.workspace.name // empty' <<<"$WIN_JSON")" \
CONFIRM_MONITOR="$CONFIRM_MONITOR" \
    "${QUICKSHELL:-quickshell}" -p "$DIR/shell.qml"
if [ $? -eq 0 ]; then close_window; exit 0; fi
exit 1
