#!/bin/bash
# md-glance CLI 安装脚本
# 将 md-glanceCLI 安装到 /usr/local/bin

set -e

# 配置
CLI_NAME="mdg"
INSTALL_DIR="/usr/local/bin"
BUILD_DIR=".build/debug"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔨 正在构建 mdg..."
cd "$PROJECT_ROOT"
swift build --product mdg

echo "📦 正在安装 $CLI_NAME 到 $INSTALL_DIR..."

# 检查安装目录是否存在
if [ ! -d "$INSTALL_DIR" ]; then
    echo "⚠️  $INSTALL_DIR 不存在，尝试创建..."
    sudo mkdir -p "$INSTALL_DIR"
fi

# 复制可执行文件
sudo cp "$BUILD_DIR/mdg" "$INSTALL_DIR/$CLI_NAME"
sudo chmod +x "$INSTALL_DIR/$CLI_NAME"

echo "✅ 安装完成！"
echo ""
echo "现在可以从任何位置运行："
echo "  $CLI_NAME <file.md>"
echo ""
echo "示例："
echo "  $CLI_NAME README.md"
echo "  $CLI_NAME ~/Documents/notes.md"
