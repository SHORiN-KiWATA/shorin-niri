#!/usr/bin/env bash

# ==============================================================================
# 脚本名称: nm-backend-selector.sh
# 功能描述: 检测 NetworkManager 的 WiFi 后端并启动相应的 TUI 工具 (impala 或 nmtui)
# 最佳实践: 严格模式、错误处理、函数化、依赖检查
# ==============================================================================

# --- 严格模式设定 ---
set -Eeuo pipefail
trap 'echo "Error: line $LINENO, command: $BASH_COMMAND"' ERR

# --- 常量定义 ---
readonly NM_CONF_DIR="/etc/NetworkManager"
readonly DEFAULT_BACKEND="wpa_supplicant"

# --- 函数: 打印帮助信息 ---
usage() {
    echo "Usage: $0"
    echo "检测 NetworkManager 后端并在 iwd 时开启 impala，在 wpa_supplicant 时开启 nmtui。"
}

# --- 函数: 检测依赖是否存在 ---
check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        return 1
    fi
}

# --- 函数: 获取 NM 的 WiFi 后端 ---
get_wifi_backend() {
    local backend=""

    # 1. 优先尝试通过 nmcli 获取（最准确，反映当前运行状态）
    # 注意：并非所有版本的 nmcli 都能直接输出 wifi-backend
    if check_dependency "nmcli"; then
        backend=$(nmcli -t -f DEVICE,WIFI-BACKEND device show 2>/dev/null | head -n 1 | cut -d':' -f2 || true)
    fi

    # 2. 如果 nmcli 未能获取，则解析配置文件
    if [[ -z "$backend" ]]; then
        # 搜索所有可能的配置文件，查找 [device] 节下的 wifi.backend
        # 使用 awk 处理多文件，匹配节和键值对
        backend=$(awk -F'=' '
            /^\[device\]/ { in_device=1; next }
            /^\[/ { in_device=0 }
            in_device && $1 ~ /wifi.backend/ { gsub(/[[:space:]]/, "", $2); print $2; exit }
        ' "$NM_CONF_DIR"/NetworkManager.conf "$NM_CONF_DIR"/conf.d/*.conf 2>/dev/null | tail -n 1 || true)
    fi

    # 3. 如果依然为空，则返回默认值
    echo "${backend:-$DEFAULT_BACKEND}"
}

# --- 主逻辑 ---
main() {
    # 0. 检查 NetworkManager 是否正在运行
    if ! check_dependency "nmcli"; then
        echo "Error: 'nmcli' 未安装，无法检测 NetworkManager 状态。" >&2
        exit 1
    fi

    # 1. 获取后端名称
    local current_backend
    current_backend=$(get_wifi_backend)
    echo "检测到 NetworkManager WiFi 后端为: $current_backend"

    # 2. 根据后端决定执行工具
    case "$current_backend" in
        "iwd")
            if check_dependency "impala"; then
                echo "启动 impala..."
                exec impala
            else
                echo "Warning: 后端为 iwd 但未找到 'impala'。回退到 nmtui..." >&2
                exec nmtui
            fi
            ;;
        "wpa_supplicant" | *)
            echo "启动 nmtui..."
            if check_dependency "nmtui"; then
                exec nmtui
            else
                echo "Error: 未找到 'nmtui'，请检查 networkmanager 是否安装完整。" >&2
                exit 1
            fi
            ;;
    esac
}

# 启动脚本
main "$@"
