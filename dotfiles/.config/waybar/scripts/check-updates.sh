#!/bin/bash
# ==============================================================================
# 功能：Waybar 更新检测后台守护脚本
# 特性：定期检查 Pacman 和 AUR 更新，生成 JSON 和 txt 供前端极速读取。
# 修复：引入动态信号屏蔽与 FORCE_UPDATE 标志，完美解决高频触发导致的并发地狱。
# ==============================================================================

set -euo pipefail

# === 配置区域 ===
CACHE_DIR="$HOME/.cache/shorin-check-arch-updates"
CACHE_FILE="$CACHE_DIR/updates.json"
LOCK_FILE="/tmp/waybar-updates.lock"
MAX_LINES=50
CHECK_INTERVAL=3600

# 确保缓存目录存在
mkdir -p "$CACHE_DIR"

# 全局状态标志：0=按需检查，1=强制无视缓存检查
FORCE_UPDATE=0

# === 自动检测 AUR Helper ===
if command -v paru &> /dev/null; then
    AUR_HELPER="paru"
elif command -v yay &> /dev/null; then
    AUR_HELPER="yay"
else
    AUR_HELPER=""
fi

# === 信号处理函数 ===
# 不再粗暴删除文件，仅修改标志位
on_sigusr1() {
    FORCE_UPDATE=1
}

# 初始绑定信号
trap 'on_sigusr1' SIGUSR1

# === 生成 JSON 函数 ===
generate_json() {
    local updates=$1
    local count
    
    updates=$(echo "$updates" | grep -v '^\s*$' || true)
    
    if [[ -z "$updates" ]]; then
        count=0
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date"}\n'
        return
    else
        count=$(echo "$updates" | wc -l)
    fi

    local tooltip_text=""
    if [[ "$count" -gt "$MAX_LINES" ]]; then
        local remainder=$((count - MAX_LINES))
        local top_list=$(echo "$updates" | head -n "$MAX_LINES")
        local escaped_list=$(echo "$top_list" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' )
        tooltip_text="${escaped_list}----------------\\n<b>⚠️ ... and ${remainder} more updates</b>"
    else
        tooltip_text=$(echo "$updates" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | head -c -2 || true)
    fi

    printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip_text"
}

# === 真正的检查逻辑 ===
perform_update_check() {
    local REPO_UPDATES=""
    local STATUS=0
    REPO_UPDATES=$(checkupdates 2>/dev/null) || STATUS=$?

    local AUR_UPDATES=""
    if [[ -n "$AUR_HELPER" ]]; then
        AUR_UPDATES=$("$AUR_HELPER" -Qua 2>/dev/null || true)
    fi

    local ALL_UPDATES=""
    if [[ $STATUS -eq 0 ]] || [[ $STATUS -eq 2 ]]; then
        if [[ -n "$REPO_UPDATES" ]] && [[ -n "$AUR_UPDATES" ]]; then
            ALL_UPDATES="$REPO_UPDATES"$'\n'"$AUR_UPDATES"
        elif [[ -n "$REPO_UPDATES" ]]; then
            ALL_UPDATES="$REPO_UPDATES"
        else
            ALL_UPDATES="$AUR_UPDATES"
        fi
        
        echo "$REPO_UPDATES" > "${CACHE_FILE%.json}-repo.txt"
        echo "$AUR_UPDATES" > "${CACHE_FILE%.json}-aur.txt"
        generate_json "$ALL_UPDATES" > "$CACHE_FILE"
    else
        return 1
    fi
}

# === 主控制逻辑 ===
run_check() {
    # 1. 检查缓存是否新鲜 (如果收到刷新信号 FORCE_UPDATE=1，则跳过判断)
    if [[ $FORCE_UPDATE -eq 0 ]] && [[ -f "$CACHE_FILE" ]]; then
        local current_time file_time age
        current_time=$(date +%s)
        file_time=$(stat -c %Y "$CACHE_FILE")
        age=$((current_time - file_time))
        
        if [[ $age -lt $((CHECK_INTERVAL - 10)) ]]; then
            cat "$CACHE_FILE"
            return
        fi
    fi

    # 准备干脏活累活前，重置标志位
    FORCE_UPDATE=0
    
    # 【核心修复】：动态屏蔽 SIGUSR1 信号！
    # 在执行耗时的网络和数据库操作时，无视一切 Ctrl+R 带来的外部干扰。
    trap '' SIGUSR1

    # 2. 获取锁进行更新
    (
        if flock -x -n 9; then
            perform_update_check || true
        else
            flock -x -w 120 9 || true
        fi
    ) 9>"$LOCK_FILE" || true

    # 【核心修复】：干完活了，重新恢复对 SIGUSR1 信号的监听
    trap 'on_sigusr1' SIGUSR1

    # 3. 最终输出缓存内容
    if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
    else
        printf '{"text": "...", "alt": "updated", "tooltip": "Checking..."}\n'
    fi
}

# === 主循环 ===
while true; do
    run_check
    sleep "$CHECK_INTERVAL" &
    
    # 即使 sleep 被信号强行打断，|| true 也能保住脚本的命
    wait $! || true
done
