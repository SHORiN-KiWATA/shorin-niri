#!/bin/bash
# 功能：使用 wl-screenrec 进行屏幕区域录制，用于后续长截图拼接。
# 包含了基于 fuzzel/wofi/rofi 的停止录制菜单，并在录制完成后调用 python 脚本拼接并根据配置预览或保存。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$SCRIPT_DIR/venv/bin/python"
PY_STITCH="$SCRIPT_DIR/stitch.py"

CONFIG_DIR="$HOME/.cache/longshot-sh"
CONFIG_FILE="$CONFIG_DIR/mode"
SAVE_DIR="$HOME/Pictures/Screenshots/longshots"
mkdir -p "$SAVE_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TMP_VIDEO="/tmp/longshot_${TIMESTAMP}.mp4"
OUTPUT_IMG="${SAVE_DIR}/longshot_${TIMESTAMP}.png"

# 语言
if env | grep -q "zh_CN" || false; then
    TXT_REC="录制中"
    TXT_MSG="正在拼接..."
    TXT_SAVED="已保存并复制"
    WIDTH=6
else
    TXT_REC="Recording"
    TXT_MSG="Stitching..."
    TXT_SAVED="Saved"
    WIDTH=10
fi

# 录制菜单
if command -v fuzzel &> /dev/null; then
    MENU_REC_CMD="fuzzel -d --anchor top --y-margin 20 --width $WIDTH --lines 0"
elif command -v wofi &> /dev/null; then
    MENU_REC_CMD="wofi -d -i -p Rec"
else
    MENU_REC_CMD="rofi -dmenu -p Rec"
fi

# Step 1: 选区
# 捕获取消操作，防止 set -e 导致非正常中断退出
GEOMETRY=$(slurp) || exit 0
if [ -z "$GEOMETRY" ]; then exit 1; fi

# Step 2: 录制
# wl-screenrec 默认表现优异，极简传参即可满足拼接所需的高帧率无损画质
wl-screenrec -g "$GEOMETRY" -f "$TMP_VIDEO" &> /dev/null &
REC_PID=$!

sleep 0.5
if ! kill -0 $REC_PID 2>/dev/null; then
    notify-send "Error" "wl-screenrec failed"
    exit 1
fi

# Step 3: 停止菜单
echo "Stop" | $MENU_REC_CMD -p "$TXT_REC" > /dev/null || true

kill -SIGINT $REC_PID || true
# wait 在接收到中断时会返回非 0，必须加 || true 防止 set -e 异常捕获
wait $REC_PID 2>/dev/null || true

# Step 4: 处理
if [ -f "$TMP_VIDEO" ]; then
    notify-send "Longshot" "$TXT_MSG"
    
    # --- 后台通知循环 ---
    (
        while true; do
            sleep 8
            notify-send "Longshot" "$TXT_MSG"
        done
    ) &
    NOTIFY_PID=$!
    # -------------------------------
    
    "$VENV_PYTHON" "$PY_STITCH" "$TMP_VIDEO" "$OUTPUT_IMG"
    
    # --- 生成完成后杀死通知循环 ---
    kill $NOTIFY_PID 2>/dev/null || true
    # -----------------------------------

    rm -f "$TMP_VIDEO"
    
    if [ -f "$OUTPUT_IMG" ]; then
        if command -v wl-copy &> /dev/null; then wl-copy < "$OUTPUT_IMG"; fi
        
        # 自动执行动作
        FINAL_MODE=$(cat "$CONFIG_FILE" 2>/dev/null || echo "PREVIEW")
        case "$FINAL_MODE" in
            "PREVIEW") imv "$OUTPUT_IMG" ;;
            "EDIT")    if command -v satty &> /dev/null; then satty -f "$OUTPUT_IMG"; else imv "$OUTPUT_IMG"; fi ;;
            "SAVE")    notify-send "Longshot" "$TXT_SAVED: $(basename "$OUTPUT_IMG")" ;;
        esac
    fi
else
    notify-send "Error" "No video"
fi
