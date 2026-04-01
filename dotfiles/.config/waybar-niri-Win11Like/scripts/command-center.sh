#!/bin/bash

# ==============================================================================
# Command Center - 常用维护指令集
# ==============================================================================
# 脚本功能：
# 1. 严格模式执行，保障代码健壮性。
# 2. 启动时检测必要的前置依赖 (kitty)，若缺失则报错。
# 3. 动态环境与命令探测，按需生成菜单选项，不显示当前环境中不可用的功能：
#    - BTRFS 检测：检测环境与依赖，决定是否显示快速存读档。
#    - 维护命令探测：检测 sysup/mirror-update/clean 等命令是否独立存在于
#      ~/.local/bin 中，或作为 shorin 的子命令存在。仅存在时才予以显示。
#    - Niri 更新检测：结合目录与执行路径共同判断。
#    - 深度清理：结合 BTRFS 条件与 clean 命令共同判断。
#    - 网络与蓝牙工具：探测 NetworkManager 状态及可用的前端工具并显示。
# ==============================================================================

# 启用严格模式：
# -e: 命令执行失败(非0)时立即退出
# -u: 使用未定义变量时报错并退出
# -o pipefail: 管道中任何一个命令失败都会导致整个管道返回失败
set -euo pipefail

# 错误处理与通知函数
report_error() {
    local error_msg="$1"
    echo "错误：$error_msg" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -a "Command Center" "Shorin 指令异常" "$error_msg" || true
    fi
}

# 辅助函数：检测命令可执行路径或替代方案 (KISS原则：直接输出可供执行的命令格式)
# 参数 $1: 命令名称 (如 sysup)
get_exec_cmd() {
    local target="$1"
    if [[ -x "$HOME/.local/bin/$target" ]]; then
        # 优先使用 .local/bin 下的独立脚本
        echo "$HOME/.local/bin/$target"
    elif command -v shorin >/dev/null 2>&1; then
        # 如果不存在独立脚本但 shorin 存在，则转交为 shorin 的子命令
        echo "shorin $target"
    else
        # 都不存在则输出空
        echo ""
    fi
}

# 0. 基础依赖检测 (kitty)
if ! command -v kitty >/dev/null 2>&1; then
    report_error "未找到 kitty 终端，请先安装。"
    exit 1
fi

# 声明所有可能用到的选项和执行命令变量，满足 set -u 要求
OPT_SAVE="快速存档 (quicksave)"
OPT_LOAD="快速读档 (quickload)"

OPT_MIRROR=""
CMD_MIRROR=""
OPT_SYSUP=""
CMD_SYSUP=""
OPT_SHORIN=""
CMD_SHORIN=""
OPT_CLEAN=""
CMD_CLEAN=""
OPT_DEEP_CLEAN=""

OPT_NETWORK=""
NET_TOOL=""
OPT_BLUETOOTH=""
BT_TOOL=""

# 使用数组存储动态生成的选项
OPTIONS_ARR=()

# 1. BTRFS 相关判断
BTRFS_MODE=false
if [[ "$(stat -f -c %T /)" == "btrfs" ]] && \
   command -v shorin >/dev/null 2>&1 && \
   command -v snapper >/dev/null 2>&1 && \
   command -v btrfs-assistant >/dev/null 2>&1; then
    BTRFS_MODE=true
    OPTIONS_ARR+=("$OPT_SAVE")
    OPTIONS_ARR+=("$OPT_LOAD")
fi

# 探测并添加：更新镜像源
CMD_MIRROR=$(get_exec_cmd "mirror-update")
if [[ -n "$CMD_MIRROR" ]]; then
    OPT_MIRROR="更新镜像源 (mirror-update)"
    OPTIONS_ARR+=("$OPT_MIRROR")
fi

# 探测并添加：更新系统
CMD_SYSUP=$(get_exec_cmd "sysup")
if [[ -n "$CMD_SYSUP" ]]; then
    OPT_SYSUP="更新系统 (sysup)"
    OPTIONS_ARR+=("$OPT_SYSUP")
fi

# 探测并添加：Shorin Niri 更新 (需同时满足目录存在和命令可用)
if [[ -d "$HOME/.local/share/shorin-niri" ]]; then
    CMD_SHORIN=$(get_exec_cmd "shorin-update")
    if [[ -n "$CMD_SHORIN" ]]; then
        OPT_SHORIN="更新Shorin's Niri (shorin-update)"
        OPTIONS_ARR+=("$OPT_SHORIN")
    fi
fi

# 探测并添加：系统清理与深度清理
CMD_CLEAN=$(get_exec_cmd "clean")
if [[ -n "$CMD_CLEAN" ]]; then
    OPT_CLEAN="系统清理 (clean)"
    OPTIONS_ARR+=("$OPT_CLEAN")
    
    # 深度清理同时依赖于 BTRFS 判定条件和 clean 命令自身的存在
    if [[ "$BTRFS_MODE" == true ]]; then
        OPT_DEEP_CLEAN="深度系统清理 (clean all)"
        OPTIONS_ARR+=("$OPT_DEEP_CLEAN")
    fi
fi

# 判断当前是否使用 NetworkManager，并确定后端工具
if systemctl is-active --quiet NetworkManager; then
    if NetworkManager --print-config 2>/dev/null | grep -iq 'wifi\.backend.*iwd' || systemctl is-active --quiet iwd; then
        NET_TOOL="impala"
    else
        NET_TOOL="nmtui"
    fi
    OPT_NETWORK="联网工具 ($NET_TOOL)"
    OPTIONS_ARR+=("$OPT_NETWORK")
fi

# 判断蓝牙设备是否存在，并探测可用的界面工具
if [[ -d /sys/class/bluetooth ]] && [[ -n "$(ls -A /sys/class/bluetooth 2>/dev/null || true)" ]]; then
    if command -v bluetuith >/dev/null 2>&1; then
        BT_TOOL="bluetuith"
    elif command -v bluetui >/dev/null 2>&1; then
        BT_TOOL="bluetui"
    elif command -v blueman-manager >/dev/null 2>&1; then
        BT_TOOL="blueman-manager"
    elif command -v blueberry >/dev/null 2>&1; then
        BT_TOOL="blueberry"
    else
        BT_TOOL="bluetoothctl"
    fi
    OPT_BLUETOOTH="蓝牙工具 ($BT_TOOL)"
    OPTIONS_ARR+=("$OPT_BLUETOOTH")
fi

# 如果没有探测到任何可用选项，直接退出以防止 fuzzel 报错
if [[ ${#OPTIONS_ARR[@]} -eq 0 ]]; then
    report_error "未探测到任何可用的维护指令。"
    exit 1
fi

# 调用 Fuzzel 显示菜单
SELECTED=$(printf "%s\n" "${OPTIONS_ARR[@]}" | fuzzel --dmenu \
    -p "Shorin指令 > " \
    --placeholder "命令可手动运行" \
    --placeholder-color 80808099 || true)

# 如果用户未选择任何项直接退出
if [[ -z "$SELECTED" ]]; then
    exit 0
fi

# 根据选择执行命令
# 所有的命令执行都使用探测所得的 CMD_ 变量，实现了真正的逻辑解耦
case "$SELECTED" in
    "$OPT_SAVE")
        quicksave &
        ;;
    "$OPT_LOAD")
        quickload &
        ;;
    "$OPT_MIRROR")
        kitty --single-instance --class command-center --title "更新镜像源" bash -c "$CMD_MIRROR; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_SYSUP")
        kitty --single-instance --class command-center --title "系统更新" bash -c "$CMD_SYSUP; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_SHORIN")
        kitty --single-instance --class command-center --title "Shorin更新" bash -c "$CMD_SHORIN; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_CLEAN")
        kitty --single-instance --class command-center --title "系统清理" bash -c "$CMD_CLEAN; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_DEEP_CLEAN")
        # 无论是 ~/.local/bin/clean all 还是 shorin clean all 都能通过 $CMD_CLEAN all 完美适配
        kitty --single-instance --class command-center --title "深度系统清理" bash -c "$CMD_CLEAN all; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_NETWORK")
        if [[ -n "$NET_TOOL" ]]; then
            kitty --single-instance --class command-center --title "联网工具" bash -c "$NET_TOOL"
        fi
        ;;
    "$OPT_BLUETOOTH")
        if [[ -n "$BT_TOOL" ]]; then
            kitty --single-instance --class command-center --title "蓝牙工具" bash -c "$BT_TOOL"
        fi
        ;;
    *)
        report_error "未知的选项: $SELECTED"
        exit 1
        ;;
esac
