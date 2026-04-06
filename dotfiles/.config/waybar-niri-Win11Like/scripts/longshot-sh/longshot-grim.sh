#!/bin/bash

# =================语言=================
if env | grep -q "zh_CN"; then
    STR_NEXT="截取下一张 (仅需定高度)"
    STR_FINISH="完成并处理"
    STR_ABORT="放弃"
    STR_ERR="错误"
    STR_SAVED="已保存"
else
    STR_NEXT="Capture Next (Height only)"
    STR_FINISH="Finish"
    STR_ABORT="Abort"
    STR_ERR="Error"
    STR_SAVED="Saved"
fi

# =================配置=================
CONFIG_DIR="$HOME/.cache/longshot-sh"
CONFIG_FILE="$CONFIG_DIR/mode"
SAVE_DIR="$HOME/Pictures/Screenshots/longshots"

TMP_DIR="/tmp/longshot_grim_$(date +%s)"
FILENAME="longshot_$(date +%Y%m%d_%H%M%S).png"
RESULT_PATH="$SAVE_DIR/$FILENAME"
TMP_STITCHED="$TMP_DIR/stitched.png"

mkdir -p "$SAVE_DIR" "$TMP_DIR"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT SIGINT SIGTERM

# 菜单工具
# [修改]: 将 fuzzel 宽度从 45 调整为 30，使其更紧凑
CMD_FUZZEL="fuzzel -d --anchor=top --y-margin=20 --lines=3 --width=30"
CMD_WOFI="wofi --dmenu --lines 3"
CMD_ROFI="rofi -dmenu -l 3"

if command -v fuzzel &> /dev/null; then MENU_CMD="$CMD_FUZZEL"
elif command -v wofi &> /dev/null; then MENU_CMD="$CMD_WOFI"
elif command -v rofi &> /dev/null; then MENU_CMD="$CMD_ROFI"
else exit 1; fi

# [新增]: 动态计算宽度函数 (主要针对 wofi)
function get_dynamic_width() {
    local text="$1"
    # 获取最长行的长度
    local max_len=$(echo -e "$text" | wc -L)
    # 计算: 字符数 * 28px + 60px 边距 (可根据屏幕分辨率微调)
    echo $(( max_len * 28 + 60 ))
}

# [修改]: 增加对 wofi 的动态宽度支持
function show_menu() {
    local content="$1"
    
    if [[ "$MENU_CMD" == *"wofi"* ]]; then
        # 如果是 wofi，计算宽度并附加参数
        local width=$(get_dynamic_width "$content")
        echo -e "$content" | $MENU_CMD --width "$width"
    else
        # 其他工具 (fuzzel/rofi) 保持原样
        echo -e "$content" | $MENU_CMD
    fi
}

# ======================================
# Step 1: 第一张截图 (直接开始，不询问)
# ======================================
# 用户在主菜单点击了 "选择区域"，所以这里直接 Slurp
GEO_1=$(slurp)
if [ -z "$GEO_1" ]; then exit 0; fi

IFS=', x' read -r FIX_X FIX_Y FIX_W FIX_H <<< "$GEO_1"
grim -g "$GEO_1" "$TMP_DIR/001.png"

# ======================================
# Step 2: 循环截图
# ======================================
INDEX=2
DO_SAVE=false

while true; do
    # 菜单提示下一张 (show_menu 会自动处理宽度)
    ACTION=$(show_menu "$STR_NEXT\n$STR_FINISH\n$STR_ABORT")
    
    case "$ACTION" in
        *"📸"*)
            sleep 0.2
            GEO_NEXT=$(slurp)
            if [ -z "$GEO_NEXT" ]; then continue; fi
            
            # 锁定宽度和X轴，只取新高度
            IFS=', x' read -r _TX NEW_Y _TW NEW_H <<< "$GEO_NEXT"
            FINAL_GEO="${FIX_X},${NEW_Y} ${FIX_W}x${NEW_H}"
            
            IMG_NAME="$(printf "%03d" $INDEX).png"
            grim -g "$FINAL_GEO" "$TMP_DIR/$IMG_NAME"
            ((INDEX++))
            ;;
        *"💾"*) DO_SAVE=true; break ;;
        *"❌"*) exit 0 ;;
        *) break ;; # 意外退出
    esac
done

# ======================================
# Step 3: 处理与自动动作
# ======================================
COUNT=$(ls "$TMP_DIR"/*.png 2>/dev/null | wc -l)

if [ "$COUNT" -gt 0 ] && [ "$DO_SAVE" = true ]; then
    # 拼接
    magick "$TMP_DIR"/*.png -append "$TMP_STITCHED"
    mv "$TMP_STITCHED" "$RESULT_PATH"
    
    # 复制到剪贴板
    if command -v wl-copy &> /dev/null; then wl-copy < "$RESULT_PATH"; fi
    
    # 读取配置执行动作
    FINAL_MODE=$(cat "$CONFIG_FILE" 2>/dev/null || echo "PREVIEW")
    
    case "$FINAL_MODE" in
        "PREVIEW")
            imv "$RESULT_PATH"
            ;;
        "EDIT")
            if command -v satty &> /dev/null; then satty -f "$RESULT_PATH"
            else imv "$RESULT_PATH"; fi
            ;;
        "SAVE")
            notify-send -i "$RESULT_PATH" "Longshot" "$STR_SAVED: $(basename "$RESULT_PATH")"
            ;;
    esac
fi
