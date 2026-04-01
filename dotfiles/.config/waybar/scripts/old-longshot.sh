#!/bin/bash

# ==============================================================================
# 1. 本地化与文案配置
# ==============================================================================
# 默认英文
STR_PROMPT="Longshot> "
STR_START="⛶  Start Selection (Width as baseline)"
STR_CANCEL="❌ Cancel"
STR_NEXT="📸 Capture Next (Height only)"
STR_SAVE="💾 Save & Finish"
STR_EDIT="🎨 Edit & Finish"
STR_ABORT="❌ Abort"
STR_NOTIFY_TITLE="Longshot"
STR_NOTIFY_SAVED="Saved to"
STR_NOTIFY_COPIED="Copied to clipboard"
STR_ERR_DEP="Missing dependency"
STR_ERR_MENU="Menu tool not found"
STR_ERR_TITLE="Error"

# 中文检测
if env | grep -q "zh_CN"; then
    STR_PROMPT="长截图> "
    STR_START="⛶  开始框选（该图宽视为基准）"
    STR_CANCEL="❌ 取消"
    STR_NEXT="📸 截取下一张（只需确定高度）"
    STR_SAVE="💾 完成并保存"
    STR_EDIT="🎨 完成并编辑"
    STR_ABORT="❌ 放弃并退出"
    STR_NOTIFY_TITLE="长截图完成"
    STR_NOTIFY_SAVED="已保存至"
    STR_NOTIFY_COPIED="并已复制到剪贴板"
    STR_ERR_DEP="缺少核心依赖"
    STR_ERR_MENU="未找到菜单工具 (fuzzel/rofi/wofi)"
    STR_ERR_TITLE="错误"
fi

# ==============================================================================
# 2. 用户配置与安全初始化
# ==============================================================================
SAVE_DIR="$HOME/Pictures/Screenshots/longshots"
TMP_BASE_NAME="niri_longshot"
TMP_DIR="/tmp/${TMP_BASE_NAME}_$(date +%s)"
FILENAME="longshot_$(date +%Y%m%d_%H%M%S).png"
RESULT_PATH="$SAVE_DIR/$FILENAME"
TMP_STITCHED="$TMP_DIR/stitched_temp.png"

# --- [保险措施 1] 启动时清理陈旧垃圾 ---
# 查找 /tmp 下名字包含 niri_longshot 且修改时间超过 10 分钟的目录并删除
# 这可以防止因断电或 kill -9 导致的垃圾堆积，同时不影响刚启动的其他实例
find /tmp -maxdepth 1 -type d -name "${TMP_BASE_NAME}_*" -mmin +10 -exec rm -rf {} + 2>/dev/null

# 创建目录
mkdir -p "$SAVE_DIR"
mkdir -p "$TMP_DIR"

# --- [保险措施 2] 增强型 Trap ---
# 无论脚本是正常退出 (EXIT)、被 Ctrl+C (SIGINT)、还是被 kill (SIGTERM)，都执行清理
# 这里的逻辑是：只要脚本进程结束，就删掉本次生成的 TMP_DIR
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT SIGINT SIGTERM SIGHUP

# ==============================================================================
# 3. 依赖与工具探测
# ==============================================================================
CMD_FUZZEL="fuzzel -d --anchor=top --y-margin=10 --lines=5 --width=45 --prompt=$STR_PROMPT"
CMD_ROFI="rofi -dmenu -i -p $STR_PROMPT -l 5"
CMD_WOFI="wofi --dmenu --lines 5 --prompt $STR_PROMPT"

REQUIRED_CMDS=("grim" "slurp" "magick" "notify-send")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        PKG_NAME="$cmd"
        [[ "$cmd" == "magick" ]] && PKG_NAME="imagemagick"
        notify-send -u critical "$STR_ERR_TITLE" "$STR_ERR_DEP: $cmd\nInstall: sudo pacman -S $PKG_NAME"
        exit 1
    fi
done

EDITOR_CMD=""
if command -v satty &> /dev/null; then EDITOR_CMD="satty --filename"; 
elif command -v swappy &> /dev/null; then EDITOR_CMD="swappy -f"; fi

MENU_CMD=""
if command -v fuzzel &> /dev/null; then MENU_CMD="$CMD_FUZZEL"
elif command -v rofi &> /dev/null; then MENU_CMD="$CMD_ROFI"
elif command -v wofi &> /dev/null; then MENU_CMD="$CMD_WOFI"
else
    notify-send -u critical "$STR_ERR_TITLE" "$STR_ERR_MENU"
    exit 1
fi

function show_menu() { echo -e "$1" | $MENU_CMD; }

# ==============================================================================
# 步骤 1: 第一张截图 (基准)
# ==============================================================================

SELECTION=$(show_menu "$STR_START\n$STR_CANCEL")
if [[ "$SELECTION" != "$STR_START" ]]; then exit 0; fi

sleep 0.2 
GEO_1=$(slurp)
# 如果第一步被 Super+Q 杀掉 slurp，GEO_1 为空，脚本会在此退出并触发 cleanup
if [ -z "$GEO_1" ]; then exit 0; fi

IFS=', x' read -r FIX_X FIX_Y FIX_W FIX_H <<< "$GEO_1"
grim -g "$GEO_1" "$TMP_DIR/001.png"

# ==============================================================================
# 步骤 2: 循环截图
# ==============================================================================
INDEX=2
SAVE_MODE=""

while true; do
    MENU_OPTIONS="$STR_NEXT\n$STR_SAVE"
    if [[ -n "$EDITOR_CMD" ]]; then MENU_OPTIONS="$MENU_OPTIONS\n$STR_EDIT"; fi
    MENU_OPTIONS="$MENU_OPTIONS\n$STR_ABORT"
    
    # 如果此时 Super+Q 杀掉了 Fuzzel，ACTION 为空
    ACTION=$(show_menu "$MENU_OPTIONS")
    
    case "$ACTION" in
        *"📸"*)
            sleep 0.2
            GEO_NEXT=$(slurp)
            
            # 如果此时 Super+Q 杀掉 Slurp，GEO_NEXT 为空，回到菜单
            if [ -z "$GEO_NEXT" ]; then 
                continue 
            fi
            
            IFS=', x' read -r _TEMP_X NEW_Y _TEMP_W NEW_H <<< "$GEO_NEXT"
            FINAL_GEO="${FIX_X},${NEW_Y} ${FIX_W}x${NEW_H}"
            
            IMG_NAME="$(printf "%03d" $INDEX).png"
            grim -g "$FINAL_GEO" "$TMP_DIR/$IMG_NAME"
            ((INDEX++))
            ;;
            
        *"💾"*) 
            SAVE_MODE="save"
            break 
            ;;
            
        *"🎨"*) 
            SAVE_MODE="edit"
            break 
            ;;
            
        *"❌"*) 
            exit 0 
            ;;
            
        *) 
            # Fuzzel 被 Super+Q 关闭，ACTION 为空，进入这里
            # 直接 Break 跳出循环，进入保存/拼接流程 (防止误操作导致丢失)
            # 或者如果你想放弃，这里改成 exit 0
            break 
            ;;
    esac
done

# ==============================================================================
# 步骤 3: 拼接与后续处理
# ==============================================================================
COUNT=$(ls "$TMP_DIR"/*.png 2>/dev/null | wc -l)

if [ "$COUNT" -gt 0 ]; then
    magick "$TMP_DIR"/*.png -append "$TMP_STITCHED"
    
    if [[ "$SAVE_MODE" == "edit" ]]; then
        $EDITOR_CMD "$TMP_STITCHED"
    fi
    
    # 只要有保存意向 (SAVE_MODE不为空)，或者是因为意外退出且至少有图
    # 如果你是"意外退出菜单"，默认是不保存的 (SAVE_MODE为空)
    # 这里我们只在显式选择保存/编辑时才保存
    if [[ -n "$SAVE_MODE" ]]; then
        mv "$TMP_STITCHED" "$RESULT_PATH"
        
        COPY_MSG=""
        if command -v wl-copy &> /dev/null; then
            wl-copy < "$RESULT_PATH"
            COPY_MSG="$STR_NOTIFY_COPIED"
        fi
        
        notify-send -i "$RESULT_PATH" "$STR_NOTIFY_TITLE" "$STR_NOTIFY_SAVED $FILENAME\n$COPY_MSG"
    fi
fi

# 脚本结束，触发 Trap 清理 TMP_DIR