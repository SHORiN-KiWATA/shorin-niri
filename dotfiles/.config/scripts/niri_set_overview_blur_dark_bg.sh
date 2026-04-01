#!/bin/bash

# ==============================================================================
# 1. 用户配置 (User Configuration)
# ==============================================================================

# --- 核心设置 ---
# 可选: "swww", "awww" 或 "swaybg"
WALLPAPER_BACKEND="awww" 

# [SWWW 专用] 参数
SWWW_ARGS="-n overview --transition-type fade --transition-duration 0.5"

# [AWWW 专用] 参数 (保持与 SWWW 相似的过渡参数)
AWWW_ARGS="-n overview --transition-type fade --transition-duration 0.5"

# [Swaybg 专用] 填充模式 (fill, fit, center, tile)
SWAYBG_MODE="fill"

# [Waypaper] 配置文件路径 (用于当 backend 为 swaybg 时获取当前壁纸)
WAYPAPER_CONFIG="$HOME/.config/waypaper/config.ini"

# --- ImageMagick 参数 ---
IMG_BLUR_STRENGTH="0x15"
IMG_FILL_COLOR="black"
IMG_COLORIZE_STRENGTH="40%"

# --- 路径配置 ---
REAL_CACHE_BASE="$HOME/.cache/blur-wallpapers"
CACHE_SUBDIR_NAME="niri-overview-blur-dark"
LINK_NAME="cache-niri-overview-blur-dark"

# --- 自动预生成与清理配置 ---
AUTO_PREGEN="true"                # true/false：是否在后台进行维护
ORPHAN_CACHE_LIMIT=10            # 允许保留多少个“非重要壁纸”的缓存

# [关键配置] 重要壁纸目录
WALL_DIR="$HOME/Pictures/Wallpapers"

# ==============================================================================
# 2. 依赖与输入检查
# ==============================================================================

DEPENDENCIES=("magick" "notify-send")

# 根据后端不同，动态检查依赖
if [ "$WALLPAPER_BACKEND" == "swww" ]; then
    DEPENDENCIES+=("swww" "niri")
elif [ "$WALLPAPER_BACKEND" == "awww" ]; then
    DEPENDENCIES+=("awww" "niri")
elif [ "$WALLPAPER_BACKEND" == "swaybg" ]; then
    DEPENDENCIES+=("swaybg")
fi

for cmd in "${DEPENDENCIES[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        notify-send -u critical "Blur Error" "缺少依赖: $cmd，请检查是否安装"
        exit 1
    fi
done

INPUT_FILE="$1"

# === 自动获取当前壁纸逻辑 ===
if [ -z "$INPUT_FILE" ]; then
    # 策略 1: 尝试从 swww query 获取 (最准确，如果正在运行 swww)
    if command -v swww &> /dev/null && swww query &> /dev/null; then
        INPUT_FILE=$(swww query | head -n1 | grep -oP 'image: \K.*')
    fi
    
    # 策略 2: 尝试从 awww query 获取 (如果是 awww 用户)
    if [ -z "$INPUT_FILE" ] && command -v awww &> /dev/null && awww query &> /dev/null; then
        INPUT_FILE=$(awww query | head -n1 | grep -oP 'image: \K.*')
    fi

    # 策略 3: 如果上述都没拿到，且配置文件指向 waypaper，尝试读取 waypaper 配置
    if [ -z "$INPUT_FILE" ] && [ -f "$WAYPAPER_CONFIG" ]; then
        # 读取 ini 文件中的 wallpaper = /path/to/img 字段
        # 使用 grep 和 cut 提取，xargs 去除空格
        INPUT_FILE=$(grep "^wallpaper =" "$WAYPAPER_CONFIG" | cut -d '=' -f2 | xargs)
        # 处理可能的波浪号 ~ 路径
        INPUT_FILE="${INPUT_FILE/#\~/$HOME}"
    fi
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    notify-send "Blur Error" "无法自动获取当前壁纸 (尝试了 swww/awww query 和 waypaper config)。请手动指定路径。"
    exit 1
fi

# 如果配置的 WALL_DIR 不存在，回退到当前图片所在目录
if [ -z "$WALL_DIR" ] || [ ! -d "$WALL_DIR" ]; then
    WALL_DIR=$(dirname "$INPUT_FILE")
fi

# ==============================================================================
# 3. 路径与链接逻辑
# ==============================================================================

REAL_CACHE_DIR="$REAL_CACHE_BASE/$CACHE_SUBDIR_NAME"
mkdir -p "$REAL_CACHE_DIR"

WALLPAPER_DIR=$(dirname "$INPUT_FILE")
SYMLINK_PATH="$WALLPAPER_DIR/$LINK_NAME"

if [ ! -L "$SYMLINK_PATH" ] || [ "$(readlink -f "$SYMLINK_PATH")" != "$REAL_CACHE_DIR" ]; then
    if [ -d "$SYMLINK_PATH" ] && [ ! -L "$SYMLINK_PATH" ]; then
        : 
    else
        ln -sfn "$REAL_CACHE_DIR" "$SYMLINK_PATH"
    fi
fi

FILENAME=$(basename "$INPUT_FILE")
SAFE_OPACITY="${IMG_COLORIZE_STRENGTH%\%}"
SAFE_COLOR="${IMG_FILL_COLOR#\#}"
PARAM_PREFIX="blur-${IMG_BLUR_STRENGTH}-${SAFE_COLOR}-${SAFE_OPACITY}-"

BLUR_FILENAME="${PARAM_PREFIX}${FILENAME}"
FINAL_IMG_PATH="$REAL_CACHE_DIR/$BLUR_FILENAME"

# ==============================================================================
# 4. 后台维护功能
# ==============================================================================
log() { echo "[$(date '+%H:%M:%S')] $*"; }

target_for() {
    local img="$1"
    local base="${img##*/}"
    echo "$REAL_CACHE_DIR/${PARAM_PREFIX}${base}"
}

run_maintenance_in_background() {
    local current_img="$1"
    local current_cache_target="$2"
    
    (
        declare -A active_wallpapers
        local whitelist_count=0
        
        while IFS= read -r -d '' file; do
            local basename="${file##*/}"
            active_wallpapers["$basename"]=1
            whitelist_count=$((whitelist_count + 1))
        done < <(find -L "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

        local orphan_list=$(mktemp)
        local orphan_count=0
        
        while IFS= read -r -d '' cache_file; do
            local cache_name="${cache_file##*/}"
            local original_name="${cache_name#${PARAM_PREFIX}}"
            
            if [[ -z "${active_wallpapers[$original_name]}" ]]; then
                if [[ "$cache_file" != "$current_cache_target" ]]; then
                    echo "$cache_file" >> "$orphan_list"
                    orphan_count=$((orphan_count + 1))
                fi
            fi
        done < <(find "$REAL_CACHE_DIR" -maxdepth 1 -name "${PARAM_PREFIX}*" -print0)

        if [[ "$orphan_count" -gt "$ORPHAN_CACHE_LIMIT" ]]; then
            local delete_count=$((orphan_count - ORPHAN_CACHE_LIMIT))
            xargs -a "$orphan_list" ls -1tu | tail -n "$delete_count" | while read -r dead_file; do
                rm -f "$dead_file"
            done
        fi
        rm -f "$orphan_list"

        local total=0
        while IFS= read -r -d '' img; do
            [[ -n "$current_img" && "$img" == "$current_img" ]] && continue
            
            total=$((total + 1))
            local tgt
            tgt=$(target_for "$img")

            if [[ -f "$tgt" ]]; then
                continue
            fi

            if [[ -n "$IMG_FILL_COLOR" && -n "$IMG_COLORIZE_STRENGTH" ]]; then
                magick "$img" -blur "$IMG_BLUR_STRENGTH" -fill "$IMG_FILL_COLOR" -colorize "$IMG_COLORIZE_STRENGTH" "$tgt"
            else
                magick "$img" -blur "$IMG_BLUR_STRENGTH" "$tgt"
            fi
        done < <(find -L "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)
    ) & 
}

# ==============================================================================
# 5. 生成与应用函数
# ==============================================================================

apply_wallpaper() {
    local img_path="$1"
    
    touch -a "$img_path"

    # 处理 swww 和 awww 逻辑
    if [ "$WALLPAPER_BACKEND" == "swww" ] || [ "$WALLPAPER_BACKEND" == "awww" ]; then
        local daemon_name="${WALLPAPER_BACKEND}-daemon"
        
        # === 检测对应 daemon overview layer 是否存在 ===
        if ! niri msg layers | grep -q "${daemon_name}overview"; then
            # 如果 layer 不存在，启动对应的 daemon
            $daemon_name -n overview &
            # 等待一小会儿确保 socket 就绪
            sleep 0.5
        fi
        
        # 应用壁纸
        if [ "$WALLPAPER_BACKEND" == "swww" ]; then
            swww img $SWWW_ARGS "$img_path" &
        else
            awww img $AWWW_ARGS "$img_path" &
        fi
        
    elif [ "$WALLPAPER_BACKEND" == "swaybg" ]; then
        # Swaybg 逻辑
        # 1. 检查 niri 的图层状态，如果发现任何 overview 正在运行
        if niri msg layers | grep -qE "(swww-daemonoverview|awww-daemonoverview)"; then
            # 2. 杀掉对应的后台进程
            pkill -f "swww-daemon -n overview" || true
            pkill -f "awww-daemon -n overview" || true
        fi
        
        # 启动新的 swaybg 进程
        swaybg -i "$img_path" -m "$SWAYBG_MODE" &
    fi
}

# ==============================================================================
# 6. 主逻辑
# ==============================================================================

# 若缓存命中
if [ -f "$FINAL_IMG_PATH" ]; then
    apply_wallpaper "$FINAL_IMG_PATH"

    if [[ "$AUTO_PREGEN" == "true" ]]; then
        run_maintenance_in_background "$INPUT_FILE" "$FINAL_IMG_PATH"
    fi
    exit 0
fi

# 若无缓存，生成当前壁纸
if [[ -n "$IMG_FILL_COLOR" && -n "$IMG_COLORIZE_STRENGTH" ]]; then
    magick "$INPUT_FILE" -blur "$IMG_BLUR_STRENGTH" -fill "$IMG_FILL_COLOR" -colorize "$IMG_COLORIZE_STRENGTH" "$FINAL_IMG_PATH"
else
    magick "$INPUT_FILE" -blur "$IMG_BLUR_STRENGTH" "$FINAL_IMG_PATH"
fi

if [ $? -ne 0 ]; then
    notify-send "Blur Error" "ImageMagick 生成失败"
    exit 1
fi

# 应用壁纸
apply_wallpaper "$FINAL_IMG_PATH"

# 后台运行维护
if [[ "$AUTO_PREGEN" == "true" ]]; then
    run_maintenance_in_background "$INPUT_FILE" "$FINAL_IMG_PATH"
fi

exit 0
