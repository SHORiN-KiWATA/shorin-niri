#!/bin/bash

# GNOME 下监听壁纸变化，换壁纸后调用 matugen-update.sh 同步配色
# 由 ~/.config/systemd/user/matugen-gnome-watch.service 在 GNOME 会话里启动

UPDATE_SCRIPT="$HOME/.config/scripts/matugen-update.sh"
MODE_FILE="$HOME/.cache/matugen-strategy/mode"
CONVERT_DIR="$HOME/.cache/matugen-gnome"
mkdir -p "$CONVERT_DIR"

# --- 要取色的壁纸：matugen-update.sh 会把 GNOME 切到 matugen 的明暗模式，
#     暗色模式下 GNOME 显示的是 picture-uri-dark ---
current_wallpaper() {
    local key="picture-uri-dark"
    if [ "$(cat "$MODE_FILE" 2>/dev/null)" == "light" ]; then
        key="picture-uri"
    fi
    local uri
    uri=$(gsettings get org.gnome.desktop.background "$key")
    uri="${uri#\'}"
    uri="${uri%\'}"
    uri="${uri#file://}"
    # 还原 %E5%A3%81 这类转义（中文文件名）
    printf '%b' "${uri//%/\\x}"
}

# --- matugen 读不了 GNOME 自带的 jxl/svg 壁纸，先转成 png ---
prepare_image() {
    local wall="$1"
    case "${wall,,}" in
        *.png|*.jpg|*.jpeg|*.webp)
            echo "$wall"
            return
            ;;
    esac
    local out="$CONVERT_DIR/$(echo -n "$wall" | md5sum | awk '{print $1}').png"
    if [ ! -f "$out" ]; then
        magick "$wall" -resize '1000x1000>' "$out" || return 1
    fi
    echo "$out"
}

sync_colors() {
    local wall img
    wall=$(current_wallpaper)
    [ -f "$wall" ] || return
    img=$(prepare_image "$wall") || return
    "$UPDATE_SCRIPT" "$img"
}

# 登录时先同步一次（壁纸没变的话 matugen-update.sh 会自己跳过）
sync_colors

gsettings monitor org.gnome.desktop.background | while read -r line; do
    [[ "$line" == picture-uri* ]] || continue
    # 设置面板会连着改 picture-uri 和 picture-uri-dark，等两项都改完再处理
    while read -r -t 0.5 _; do :; done
    sync_colors
done
