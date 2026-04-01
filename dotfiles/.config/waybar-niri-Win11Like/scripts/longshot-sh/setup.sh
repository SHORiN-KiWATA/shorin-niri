#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

echo "🔧 初始化环境..."

# 1. 检查系统工具
# 涵盖了两个方案所需的所有工具
REQUIRED_TOOLS=("wf-recorder" "grim" "slurp" "wl-copy" "magick" "python3")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "⚠️  警告: 缺少以下系统工具，请使用包管理器安装："
    echo "   ${MISSING_TOOLS[*]}"
    echo "   (例如 Arch: sudo pacman -S wf-recorder grim slurp wl-clipboard imagemagick python)"
    echo "   (例如 Debian/Ubuntu: sudo apt install wf-recorder grim slurp wl-clipboard imagemagick python3-venv)"
fi

# 2. Python 虚拟环境
if [ ! -d "$VENV_DIR" ]; then
    echo "📦 创建 Python 虚拟环境..."
    python3 -m venv "$VENV_DIR"
fi

# 3. 安装 Python 依赖
echo "⬇️  安装 Python 库..."
"$VENV_DIR/bin/pip" install --upgrade pip > /dev/null
"$VENV_DIR/bin/pip" install opencv-python numpy > /dev/null

# 4. 赋予执行权限
chmod +x "$SCRIPT_DIR/longshot.sh"
chmod +x "$SCRIPT_DIR/longshot-wf-recorder.sh"
chmod +x "$SCRIPT_DIR/longshot-grim.sh"
chmod +x "$SCRIPT_DIR/stitch.py"

echo "✅ 完成！请运行 ./longshot.sh"