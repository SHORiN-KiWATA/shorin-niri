#!/bin/bash

# --- 1. 参数解析 ---
WALLPAPER=""
NO_INDEX=false

show_help() {
    echo "Usage: matugen-update.sh [OPTIONS] [WALLPAPER]"
    echo ""
    echo "Options:"
    echo "  -h, --help       显示此帮助信息"
    echo "  -n, --no-index   不指定 index，在终端运行时唤起 matugen 原生的交互式颜色选择"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -n|--no-index)
            NO_INDEX=true
            shift
            ;;
        *)
            WALLPAPER="$1"
            shift
            ;;
    esac
done

# --- 2. 路径与状态定义 ---
CACHE_DIR="$HOME/.cache/matugen-strategy"
TYPE_FILE="$CACHE_DIR/type"
MODE_FILE="$CACHE_DIR/mode"
INDEX_MODE_FILE="$CACHE_DIR/index_mode"
LAST_WALL_FILE="$CACHE_DIR/last_wallpaper"     
CURRENT_INDEX_FILE="$CACHE_DIR/current_index"  
VALID_INDICES_FILE="$CACHE_DIR/valid_indices"  
SHRUNK_CACHE_DIR="$CACHE_DIR/shrunk_images"   # 新增：独立的缓存池目录
WAYPAPER_CONFIG="$HOME/.config/waypaper/config.ini"

mkdir -p "$SHRUNK_CACHE_DIR"

# --- 3. 获取壁纸路径 ---
if [ -z "$WALLPAPER" ]; then
    if command -v swww &>/dev/null && pgrep -x "swww-daemon" >/dev/null; then
         DETECTED_WALL=$(swww query | head -n 1 | awk -F ': ' '{print $2}' | awk '{print $1}')
         if [ -n "$DETECTED_WALL" ] && [ -f "$DETECTED_WALL" ]; then
            WALLPAPER="$DETECTED_WALL"
         fi
    fi
    if [ -z "$WALLPAPER" ] && [ -f "$WAYPAPER_CONFIG" ]; then
        WP_PATH=$(sed -n 's/^wallpaper[[:space:]]*=[[:space:]]*//p' "$WAYPAPER_CONFIG")
        WP_PATH="${WP_PATH/#\~/$HOME}"
        if [ -n "$WP_PATH" ] && [ -f "$WP_PATH" ]; then
            WALLPAPER="$WP_PATH"
        fi
    fi
fi

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    notify-send "Matugen Error" "无法找到壁纸路径。"
    exit 1
fi
ln -sf "$WALLPAPER" "$HOME/.cache/.current_wallpaper"

# --- 4. [智能缓存] 哈希化与选择性转换 ---
# 利用 MD5 生成该路径独一无二的缓存文件名
WALL_HASH=$(echo -n "$WALLPAPER" | md5sum | awk '{print $1}')
CACHED_IMAGE="$SHRUNK_CACHE_DIR/${WALL_HASH}.png"
TARGET_IMAGE="$WALLPAPER" # 默认直接喂原图

# 仅获取真实 MIME 类型
FILE_MIME=$(file -b --mime-type "$WALLPAPER")
NEED_CONVERT=false

# 只有真实格式是 webp 时，才触发 ImageMagick 转换，修复 5249 致命错误
if [[ "$FILE_MIME" == *"webp"* ]]; then
    NEED_CONVERT=true
fi

if [ "$NEED_CONVERT" = true ]; then
    TARGET_IMAGE="$CACHED_IMAGE"
    # 如果缓存池里还没有这张图，才去调用 ImageMagick
    if [ ! -f "$CACHED_IMAGE" ]; then
        if command -v magick &>/dev/null; then
            magick "$WALLPAPER" -resize 500x500\> "$CACHED_IMAGE"
        elif command -v convert &>/dev/null; then
            convert "$WALLPAPER" -resize 500x500\> "$CACHED_IMAGE"
        elif command -v ffmpeg &>/dev/null; then
            ffmpeg -y -i "$WALLPAPER" -vf "scale='min(500,iw)':-1" "$CACHED_IMAGE" &>/dev/null
        else
            # 没有工具就只能硬着头皮上原图了
            TARGET_IMAGE="$WALLPAPER" 
        fi
    fi
fi

# 检查是否换了壁纸，用于清空有效颜色的探测状态
LAST_WALL=""
[ -f "$LAST_WALL_FILE" ] && LAST_WALL=$(cat "$LAST_WALL_FILE")
if [ "$LAST_WALL" != "$WALLPAPER" ]; then
    rm -f "$VALID_INDICES_FILE"
fi

# --- 5. 读取策略与模式 ---
if [ -f "$TYPE_FILE" ]; then STRATEGY=$(cat "$TYPE_FILE"); else STRATEGY="scheme-tonal-spot"; fi
if [ -f "$MODE_FILE" ]; then MODE=$(cat "$MODE_FILE"); else MODE="dark"; fi

# --- 6. 执行 Matugen ---
if [ "$NO_INDEX" = true ]; then
    matugen image "$TARGET_IMAGE" -t "$STRATEGY" -m "$MODE"
else
    # 后台自动化模式
    FORCE_ZERO=true
    if [ -f "$INDEX_MODE_FILE" ]; then
        if [ "$(cat "$INDEX_MODE_FILE")" == "random" ]; then
            FORCE_ZERO=false
        fi
    fi

    if [ "$FORCE_ZERO" = true ]; then
        SELECTED_INDEX=0
    else
        # 判断：如果探测缓存都存在，直接走“光速轮换”
        if [ "$LAST_WALL" == "$WALLPAPER" ] && [ -f "$VALID_INDICES_FILE" ] && [ -f "$CURRENT_INDEX_FILE" ]; then
            
            read -r -a VALID_INDICES < "$VALID_INDICES_FILE"
            LAST_INDEX=$(cat "$CURRENT_INDEX_FILE")
            NEXT_POS=0
            
            for j in "${!VALID_INDICES[@]}"; do
                if [ "${VALID_INDICES[$j]}" == "$LAST_INDEX" ]; then
                    NEXT_POS=$(( (j + 1) % ${#VALID_INDICES[@]} ))
                    break
                fi
            done
            SELECTED_INDEX=${VALID_INDICES[$NEXT_POS]}

        else
            # === 首次处理本壁纸：执行探测 ===
            VALID_INDICES=()
            for i in {0..5}; do
                if matugen image "$TARGET_IMAGE" --source-color-index "$i" --dry-run &>/dev/null; then
                    VALID_INDICES+=("$i")
                else
                    break
                fi
            done
            
            echo "${VALID_INDICES[@]}" > "$VALID_INDICES_FILE"
            
            if [ ${#VALID_INDICES[@]} -eq 0 ]; then
                SELECTED_INDEX=0 # 兜底
            else
                RANDOM_INDEX=$((RANDOM % ${#VALID_INDICES[@]}))
                SELECTED_INDEX=${VALID_INDICES[$RANDOM_INDEX]}
            fi
        fi
        
        echo "$SELECTED_INDEX" > "$CURRENT_INDEX_FILE"
    fi
    
    # 最终执行，传入决定好的 TARGET_IMAGE (可能是原图，也可能是缓存的缩小图)
    matugen image "$TARGET_IMAGE" -t "$STRATEGY" -m "$MODE" --source-color-index "$SELECTED_INDEX"
    
    # 状态持久化
    echo "$WALLPAPER" > "$LAST_WALL_FILE"
fi

# 刷新 GNOME 主题设置
if [ "$MODE" == "light" ]; then
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk"
else
    gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
fi
