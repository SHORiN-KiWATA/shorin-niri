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
RETRY_INTERVAL=30      # 检查失败（例如没网）后多久重试
NET_WAIT_MAX=60        # 启动时最多等网络多少轮（每轮 5 秒，即 5 分钟）
PACMAN_LOG="/var/log/pacman.log"

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

# === 网络检测 ===
check_network() {
    # NetworkManager 认为在线 + 真的能访问外网，两个都满足才继续
    if command -v nm-online >/dev/null 2>&1; then
        nm-online -q -t 3 >/dev/null 2>&1 || return 1
    fi
    curl -sI --connect-timeout 3 "http://captive.apple.com/hotspot-detect.html" >/dev/null 2>&1
}

# 等待网络就绪；超时返回 1
wait_for_network() {
    local tries=0
    while ! check_network; do
        tries=$((tries + 1))
        if [[ $tries -ge $NET_WAIT_MAX ]]; then
            return 1
        fi
        sleep 5
    done
    return 0
}

# === 上次系统更新时间 ===
format_age() {
    local seconds=$1

    if [[ "$seconds" -lt 0 ]]; then
        seconds=0
    fi

    if [[ "$seconds" -lt 60 ]]; then
        printf '刚刚'
    elif [[ "$seconds" -lt 3600 ]]; then
        printf '%d 分钟前' $((seconds / 60))
    elif [[ "$seconds" -lt 86400 ]]; then
        printf '%d 小时前' $((seconds / 3600))
    elif [[ "$seconds" -lt 2592000 ]]; then
        printf '%d 天前' $((seconds / 86400))
    elif [[ "$seconds" -lt 31536000 ]]; then
        printf '%d 个月前' $((seconds / 2592000))
    else
        printf '%d 年前' $((seconds / 31536000))
    fi
}

get_last_system_update_info() {
    if [[ ! -r "$PACMAN_LOG" ]]; then
        printf '上次系统更新：未知'
        return
    fi

    local last_line timestamp last_update current_time age
    # Count only full system upgrade commands, not AUR/local package upgrades.
    last_line=$(tac "$PACMAN_LOG" 2>/dev/null | grep -m1 -E "\[PACMAN\] Running 'pacman ([^']*-S[^[:space:]']*u|[^']*-S[[:space:]][^']*[[:space:]](-u|--sysupgrade)|[^']*--sync[^']*[[:space:]](-u|--sysupgrade))" || true)

    if [[ -z "$last_line" ]]; then
        printf '上次系统更新：无记录'
        return
    fi

    timestamp=${last_line%%]*}
    timestamp=${timestamp#\[}
    last_update=$(date -d "$timestamp" +%s 2>/dev/null || true)

    if [[ -z "$last_update" ]]; then
        printf '上次系统更新：未知'
        return
    fi

    current_time=$(date +%s)
    age=$((current_time - last_update))
    printf '上次系统更新：%s' "$(format_age "$age")"
}

# === 生成 JSON 函数 ===
generate_json() {
    local updates=$1
    local count
    local last_update_info

    last_update_info=$(get_last_system_update_info)
    
    updates=$(echo "$updates" | grep -v '^\s*$' || true)
    
    if [[ -z "$updates" ]]; then
        count=0
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date\\n----------------\\n%s"}\n' "$last_update_info"
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

    tooltip_text="${tooltip_text}\\n----------------\\n${last_update_info}"

    printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip_text"
}

# === 从缓存文本重新生成输出，避免 tooltip 的相对时间被 JSON 缓存卡住 ===
emit_cached_json() {
    local repo_cache="${CACHE_FILE%.json}-repo.txt"
    local aur_cache="${CACHE_FILE%.json}-aur.txt"
    local REPO_UPDATES=""
    local AUR_UPDATES=""
    local ALL_UPDATES=""

    if [[ ! -f "$repo_cache" && ! -f "$aur_cache" ]]; then
        cat "$CACHE_FILE"
        return
    fi

    if [[ -f "$repo_cache" ]]; then
        REPO_UPDATES=$(<"$repo_cache")
    fi

    if [[ -f "$aur_cache" ]]; then
        AUR_UPDATES=$(<"$aur_cache")
    fi

    if [[ -n "$REPO_UPDATES" ]] && [[ -n "$AUR_UPDATES" ]]; then
        ALL_UPDATES="$REPO_UPDATES"$'\n'"$AUR_UPDATES"
    elif [[ -n "$REPO_UPDATES" ]]; then
        ALL_UPDATES="$REPO_UPDATES"
    else
        ALL_UPDATES="$AUR_UPDATES"
    fi

    generate_json "$ALL_UPDATES"
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
            emit_cached_json
            return 0
        fi
    fi

    # 准备干脏活累活前，重置标志位
    FORCE_UPDATE=0

    # 2. 先确认网络可用；没网就快速失败，交给主循环稍后重试
    if ! wait_for_network; then
        if [[ -f "$CACHE_FILE" ]]; then
            emit_cached_json
        else
            printf '{"text": "...", "alt": "updated", "tooltip": "Waiting for network...\\n----------------\\n%s"}\n' "$(get_last_system_update_info)"
        fi
        return 1
    fi

    # 【核心修复】：动态屏蔽 SIGUSR1 信号！
    # 在执行耗时的网络和数据库操作时，无视一切 Ctrl+R 带来的外部干扰。
    trap '' SIGUSR1

    # 2. 获取锁进行更新
    local rc=0
    (
        if flock -x -n 9; then
            perform_update_check || exit 1
        else
            flock -x -w 120 9 || exit 1
        fi
    ) 9>"$LOCK_FILE" || rc=$?

    # 【核心修复】：干完活了，重新恢复对 SIGUSR1 信号的监听
    trap 'on_sigusr1' SIGUSR1

    # 3. 最终输出缓存内容
    if [[ -f "$CACHE_FILE" ]]; then
        emit_cached_json
    else
        printf '{"text": "...", "alt": "updated", "tooltip": "Checking...\\n----------------\\n%s"}\n' "$(get_last_system_update_info)"
    fi

    return $rc
}

# === 主循环 ===
while true; do
    if run_check; then
        sleep "$CHECK_INTERVAL" &
    else
        sleep "$RETRY_INTERVAL" &
    fi
    
    # 即使 sleep 被信号强行打断，|| true 也能保住脚本的命
    wait $! || true
done
