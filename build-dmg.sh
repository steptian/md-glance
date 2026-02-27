#!/bin/bash
# md-glance 打包脚本
# 生成 .app 和 .dmg 安装包（适配当前 SPM + Ink 架构）

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$PROJECT_DIR/release"
APP_NAME="md-glance"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"

echo "🔨 构建 Release 版本..."
swift build -c release

# SPM 输出目录因架构而异，用 --show-bin-path 获取
BIN_PATH="$(swift build -c release --show-bin-path)"
echo "   产物目录: $BIN_PATH"

echo "📦 创建 .app bundle..."
rm -rf "$RELEASE_DIR/$APP_BUNDLE"
mkdir -p "$RELEASE_DIR/$APP_BUNDLE/Contents/MacOS"
mkdir -p "$RELEASE_DIR/$APP_BUNDLE/Contents/Resources"

# 可执行文件
cp "$BIN_PATH/$APP_NAME" "$RELEASE_DIR/$APP_BUNDLE/Contents/MacOS/"

# Core 资源 bundle 必须放在 .app 根目录（Bundle.module 查找路径）
cp -R "$BIN_PATH/md-glance_md-glanceCore.bundle" "$RELEASE_DIR/$APP_BUNDLE/"

# 主 target 资源 bundle（含 HELP.md），放在 Contents/Resources 供帮助菜单打开
cp -R "$BIN_PATH/md-glance_md-glance.bundle" "$RELEASE_DIR/$APP_BUNDLE/Contents/Resources/"

# 图标
if [ -f "$PROJECT_DIR/md-glance/App/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/md-glance/App/Resources/AppIcon.icns" "$RELEASE_DIR/$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 帮助文档直拷一份到 Contents/Resources，作为 openHelp() 的兜底路径
cp "$PROJECT_DIR/md-glance/App/HELP.md" "$RELEASE_DIR/$APP_BUNDLE/Contents/Resources/HELP.md" 2>/dev/null || true

# 可选：关于页图片
for f in wechat.jpg wechat-pay.jpg; do
    if [ -f "$PROJECT_DIR/md-glance/App/$f" ]; then
        cp "$PROJECT_DIR/md-glance/App/$f" "$RELEASE_DIR/$APP_BUNDLE/Contents/Resources/"
    fi
done

# Info.plist
cat > "$RELEASE_DIR/$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>md-glance</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.mdglance.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>md-glance</string>
    <key>CFBundleDisplayName</key>
    <string>md-glance</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "📀 创建 .dmg 安装包..."
rm -f "$RELEASE_DIR/$DMG_NAME"
DMG_TEMP="$RELEASE_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$RELEASE_DIR/$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$RELEASE_DIR/$DMG_NAME"
rm -rf "$DMG_TEMP"

echo ""
echo "✅ 打包完成！"
echo ""
echo "📁 输出位置:"
echo "   .app: $RELEASE_DIR/$APP_BUNDLE"
echo "   .dmg: $RELEASE_DIR/$DMG_NAME"
echo ""
echo "🚀 安装: 打开 .dmg，将 md-glance 拖到 Applications"
echo ""
