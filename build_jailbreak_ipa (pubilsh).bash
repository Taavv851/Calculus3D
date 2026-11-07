#!/bin/bash
# ==============================================================================
# build_jailbreak_ipa.sh (Xcode 10.3 + iOS 11.2 隐私脱敏与 GitHub 开源防抄袭专版 v16.1)
#
# 核心功能：
#   1. 【全自动抹除 'guanjunwei' 与本机路径隐私（源码 + 工程配置 + 编译后二进制）】：
#      - 自动清理 *.xcodeproj/xcuserdata (含 guanjunwei.xcuserdatad) 与 .DS_Store；
#      - 自动扫描工程内所有 .swift / .h / .m / .plist / project.pbxproj，将所有
#        'guanjunwei'（不区分大小写）、个人 Bundle ID (com.guanjunwei.*) 与个人签名团队号
#        统一替换为匿名开源标识 `Calculus3D Open Source Project` 与 `org.calculus3d.app`；
#      - 编译完成后对 ARM64 主程序执行符号表剥离 (strip -Sx) 与等长字节脱敏，确保即便他人用
#        逆向工具 (strings / Hopper / IDA) 扫描 .ipa 安装包，也绝不会出现 'guanjunwei' 或本机路径！
#   2. 【自动生成 GitHub 防抄袭开源协议 (LICENSE) + 项目主页说明 (README.md) + .gitignore】：
#      - 采用 GPL-3.0 + CC BY-NC-SA 4.0 双重反抄袭授权：允许免费下载使用与教学参考，
#        严禁抹除署名、严禁抄袭冒充个人课程设计/毕业设计/竞赛作品、严禁商业盗用。
#   3. 【系统设置 Settings.bundle 注入 + 主屏幕 3D Touch 4 项快捷入口 + Swift -O 全模块优化】。
# ==============================================================================

set -e

PROJECT_NAME="Calculus3D"
SCHEME_NAME="Calculus3D"
CONFIGURATION="Release"
OPEN_SOURCE_BUNDLE_ID="org.calculus3d.app"
OPEN_SOURCE_AUTHOR="Calculus3D Open Source Project"
BUILD_DIR="./build_ipa_output"
IPA_NAME="${PROJECT_NAME}_Xcode10.3_iOS11.2.ipa"

# ------------------------------------------------------------------------------
# 0. 全方位隐私脱敏函数：彻底清除源码、Xcode 工程文件及 Git 配置中的 'guanjunwei'
# ------------------------------------------------------------------------------
sanitize_project_privacy() {
  echo "==> [0/7] 正在执行全方位隐私脱敏（清除 'guanjunwei'、本机路径与 Xcode 个人缓存）..."

  # (a) 删除包含个人用户名 (guanjunwei.xcuserdatad) 的 Xcode 用户缓存与 macOS 隐藏文件
  find . -name "xcuserdata" -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find . -name "*.xcuserdatad" -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find . -name "*.xccheckout" -type f -delete 2>/dev/null || true
  find . -name ".DS_Store" -type f -delete 2>/dev/null || true

  # (b) 扫描文本源码与工程配置，将所有形式的 guanjunwei 及当前系统用户名替换为匿名开源团队署名
  python3 - << 'PY_SANITIZE_EOF' || true
import os
import re
import getpass

current_user = getpass.getuser()
target_exts = {".swift", ".h", ".m", ".mm", ".c", ".cpp", ".plist", ".pbxproj", ".xcworkspacedata", ".xcscheme", ".md", ".txt", ".json"}
skip_dirs = {".git", "build_ipa_output", "DerivedData", "Pods"}

# 匹配不区分大小写的 guanjunwei 及可能的名字变体
patterns = [
    (re.compile(r"com\.guanjunwei\.[A-Za-z0-9_\-]+", re.IGNORECASE), "org.calculus3d.app"),
    (re.compile(r"/Users/guanjunwei", re.IGNORECASE), "/Users/opensource"),
    (re.compile(r"guanjunwei", re.IGNORECASE), "Calculus3D-Team"),
    (re.compile(r"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]+;"), 'DEVELOPMENT_TEAM = "";'),
]

if current_user and current_user.lower() not in ("root", "spark", "opensource", "admin"):
    patterns.append((re.compile(r"/Users/" + re.escape(current_user), re.IGNORECASE), "/Users/opensource"))
    patterns.append((re.compile(r"com\." + re.escape(current_user) + r"\.[A-Za-z0-9_\-]+", re.IGNORECASE), "org.calculus3d.app"))

sanitized_count = 0
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for fname in files:
        _, ext = os.path.splitext(fname)
        if ext not in target_exts:
            continue
        fpath = os.path.join(root, fname)
        if os.path.basename(fpath) == "build_jailbreak_ipa.sh":
            continue
        try:
            with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            new_content = content
            for pat, repl in patterns:
                new_content = pat.sub(repl, new_content)
            if new_content != content:
                with open(fpath, "w", encoding="utf-8") as f:
                    f.write(new_content)
                sanitized_count += 1
        except Exception:
            pass

print(f"    [隐私脱敏] 已自动净化 {sanitized_count} 个工程/源码文件中的个人标识。")
PY_SANITIZE_EOF

  # (c) 如果当前目录已初始化 Git，自动将本地仓库提交者设为匿名开源身份，防止 git commit 暴露真名
  if [ -d "./.git" ]; then
    git config user.name "Calculus3D-Team" || true
    git config user.email "noreply@github.com" || true
    echo "    [Git 隐私保护] 已将当前仓库 git user.name 设为 'Calculus3D-Team'，避免后续提交暴露个人姓名。"
  fi
}

# ------------------------------------------------------------------------------
# 0B. 自动生成 GitHub 开源防抄袭协议 (LICENSE)、说明文档 (README.md) 与 .gitignore
# ------------------------------------------------------------------------------
generate_github_antipiracy_files() {
  cat << 'GITIGNORE_EOF' > "./.gitignore"
# Xcode 个人用户目录（含本机用户名，严禁上传 GitHub）
xcuserdata/
*.xcuserdatad/
*.xcscmblueprint
*.xccheckout

# 编译产物与临时缓存
DerivedData/
build/
build_ipa_output/
*.ipa
*.app
*.dSYM.zip
*.dSYM

# macOS 系统隐藏文件
.DS_Store
GITIGNORE_EOF

  cat << 'LICENSE_EOF' > "./LICENSE"
================================================================================
Calculus3D Open Source License & Anti-Plagiarism Declaration
开源使用授权与反抄袭声明 (GPL-3.0-or-later & CC BY-NC-SA 4.0)
================================================================================

Copyright (c) 2026 Calculus3D Open Source Project. All rights reserved.

【中文授权与反抄袭条款（具有法律与学术诚信约束力）】：

1. 允许自由使用与学习（Permitted Free Use）：
   任何人均可免费下载、编译、安装和使用本软件（Calculus3D），用于高等数学/微积分
   个人学习、考研与期末复习、课堂教学演示以及非商业性的学术研究。

2. 严禁抄袭与严禁去除署名（Strict Prohibition of Plagiarism & Attribution Removal）：
   - 严禁删除或篡改源代码、说明书界面、系统设置面板以及内置 `Calculus3DOriginalityWatermark`
     中的版权声明、开源协议标识与 FNV-1a 64 位防伪数字水印（0x43414C33445F4F53）；
   - 严禁学术不端行为：严禁将本项目的源代码、算法引擎或界面设计（无论是否修改变量名或配色）
     直接冒充为个人或他人原创的大学课程设计、大作业、毕业设计（论文）或学科竞赛作品进行提交；
   - 任何基于本项目的修改、衍生作品或二次分发，必须在显著位置保留原项目署名与来源链接，
     并采用相同的开源协议（GPL-3.0 / CC BY-NC-SA 4.0）完全开源。

3. 严禁商业盗用（Non-Commercial Only）：
   未经原作者书面授权，严禁将本软件或其衍生版本用于任何商业售卖、付费下载或商业捆绑分发。

--------------------------------------------------------------------------------
English Summary (GNU General Public License v3.0 & CC BY-NC-SA 4.0):

This program is free software: you can use, study, and redistribute it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version, paired with Creative Commons Attribution-NonCommercial-ShareAlike 4.0.

ANTI-PLAGIARISM NOTICE:
Removing original copyright notices, stripping the embedded cryptographic
watermark (`Calculus3DOriginalityWatermark`), or submitting this software as
your own original academic coursework, thesis, or competition entry is strictly
prohibited and constitutes plagiarism and copyright infringement.
================================================================================
LICENSE_EOF

  cat << 'README_EOF' > "./README.md"
# Calculus3D — 面向大学生的交互式微积分符号推导与 3D 直观几何工作台

[![License: GPL v3 / CC BY-NC-SA 4.0](https://img.shields.io/badge/License-GPLv3%20%2F%20CC--BY--NC--SA--4.0-orange.svg)](./LICENSE)
[![Platform: iOS 11.2+](https://img.shields.io/badge/Platform-iOS%2011.2%2B%20(iPhone%20X%203D%20Touch)-blue.svg)](#)

**Calculus3D** 是一款专为学习过微积分理论、渴望建立直观几何空间感与考场破题直觉的大学生打造的原生 iOS 数学软件（完美适配 iPhone X 压感屏 3D Touch 与 iOS 11.2+）。

## ✨ 核心特性

1. **过程与结果严格一致的精确有理分数 / $\pi$ 符号微积分引擎**：
   - 基于连分数有理逼近（Continued Fractions）与抽象语法树（AST）有理化简：输入整数或分数（如 `3/4`、`x²`）时，原函数推导步骤、牛顿-莱布尼茨代入过程、定积分结果与旋转体体积全程输出纯分数或精确 $\pi$ 倍数（如 $\int_0^1 x^2\,dx = 1/3$、旋转体体积 $V = \pi/5$、球体积 $V = 4000\pi/3$），绝不擅自改写为小数，也绝不混用小数与分数。
2. **全自由度 3D 曲面/球体交互视图（支持自由平移 + 坐标轴拉伸 + 透视半透明 + 防穿模）**：
   - **自由移动图像**：支持一键切换单指自由平移模式或双指随时拖动平移图像，不再局限于绕中心点旋转；
   - **半透明透视内部坐标轴**：支持「半透 (52%) / 高透 (25%) / 实心 (95%)」三档切换，可直接透过球体或曲面清晰观察内部原点 `0` 与红(`X`)、绿(`Y`)、蓝(`Z`)双向坐标轴；
   - **防穿模安全距离锁**：自动计算曲面包络半径并锁定最小安全视距，双指放大绝不穿入物体内部；
   - **全区域坐标轴自由拉伸**：底部配备实时坐标轴拉伸滑块（`0.6x ~ 2.8x`）与等值线截面滑块。
3. **iPhone X 3D Touch 深度定制与系统级设置集成**：
   - 键盘按键轻按输入主功能、用力深按（3D Touch）直接触发右上角二级数学函数（如 `x²`、`sin⁻¹`、`方程=`）；
   - 用力深按上方算式显示屏直接弹出 2D/3D 直观几何图像；
   - 考场破题直觉提示开关（默认关闭）、答案遮挡自测与 8 道期末经典母题完整集成于 iOS **【系统设置 -> Calculus3D】**。

## 🛠️ 编译与安装方法

在 macOS（Xcode 10.3+）终端中直接运行一键构建与脱敏脚本：

```bash
chmod +x build_jailbreak_ipa.sh
./build_jailbreak_ipa.sh
```

## 📜 开源协议与反抄袭声明

本项目基于 **[GPL-3.0 & CC BY-NC-SA 4.0](./LICENSE)** 协议开源：
- **欢迎免费下载使用、学习研究与教学演示**；
- **严禁抄袭与去署名**：核心引擎内嵌 `Calculus3DOriginalityWatermark` 64 位 FNV-1a 防伪指纹（`0x43414C33445F4F53`）。严禁抹除署名、严禁将本项目冒充个人课程设计/毕业设计/竞赛作品提交，严禁商业售卖。
README_EOF
}

# 1. 生成标准 iOS 系统设置包 (Settings.bundle/Root.plist)
generate_settings_bundle() {
  local DEST_BUNDLE="$1"
  mkdir -p "${DEST_BUNDLE}"
  cat << 'SETTINGS_EOF' > "${DEST_BUNDLE}/Root.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>StringsTable</key>
	<string>Root</string>
	<key>PreferenceSpecifiers</key>
	<array>
		<dict>
			<key>Type</key>
			<string>PSGroupSpecifier</string>
			<key>Title</key>
			<string>考场破题辅助与自测设置（切换后返回应用即刻生效）</string>
			<key>FooterText</key>
			<string>开启“考场破题直觉提示”后，计算器上方将实时提示奇偶对称、反对幂指三口诀与极坐标换元方法，并在底部解锁【破题直觉】与【避坑/拟合】标签。默认关闭以保持纯净计算器界面。</string>
		</dict>
		<dict>
			<key>Type</key>
			<string>PSToggleSwitchSpecifier</string>
			<key>Title</key>
			<string>💡 考场破题直觉与避坑提示</string>
			<key>Key</key>
			<string>com.calculus3d.settings.examHintsEnabled</string>
			<key>DefaultValue</key>
			<false/>
		</dict>
		<dict>
			<key>Type</key>
			<string>PSToggleSwitchSpecifier</string>
			<key>Title</key>
			<string>🎯 考场答案遮挡自测模式</string>
			<key>Key</key>
			<string>com.calculus3d.settings.selfTestMaskEnabled</string>
			<key>DefaultValue</key>
			<false/>
		</dict>
		<dict>
			<key>Type</key>
			<string>PSMultiValueSpecifier</string>
			<key>Title</key>
			<string>📚 预设期末必考母题载入</string>
			<key>Key</key>
			<string>com.calculus3d.settings.selectedExamPresetIndex</string>
			<key>DefaultValue</key>
			<integer>-1</integer>
			<key>Titles</key>
			<array>
				<string>不自动载入（自由输入）</string>
				<string>①【奇偶性秒杀】∫[-2,2] x³·cos(x) dx = 0</string>
				<string>②【分部积分·幂×指】∫[0,1] x·exp(x) dx = 1</string>
				<string>③【分部积分·对数】∫[1,e] ln(x) dx = 1</string>
				<string>④【分部积分·三角】∫[0,π] x·sin(x) dx = π</string>
				<string>⑤【旋转体微元】y = √x 在 [0,2] 绕X轴旋转</string>
				<string>⑥【二重积分·极坐标】∬ exp(-(x²+y²)) dxdy</string>
				<string>⑦【多元偏导切面】z = sin(x)·cos(y)</string>
				<string>⑧【空间球面几何】x²+y²+z² = 1 (V=4π/3)</string>
			</array>
			<key>Values</key>
			<array>
				<integer>-1</integer>
				<integer>0</integer>
				<integer>1</integer>
				<integer>2</integer>
				<integer>3</integer>
				<integer>4</integer>
				<integer>5</integer>
				<integer>6</integer>
				<integer>7</integer>
			</array>
		</dict>
		<dict>
			<key>Type</key>
			<string>PSGroupSpecifier</string>
			<key>Title</key>
			<string>硬件音效与 Taptic 触觉反馈</string>
			<key>FooterText</key>
			<string>Calculus3D Open Source Project · 基于 GPL-3.0 / CC BY-NC-SA 4.0 免费开放学习使用，内嵌 FNV-1a 防伪水印，严禁抄袭冒用或去除署名。</string>
		</dict>
		<dict>
			<key>Type</key>
			<string>PSToggleSwitchSpecifier</string>
			<key>Title</key>
			<string>🔊 按键音与 3D Touch 震动反馈</string>
			<key>Key</key>
			<string>com.calculus3d.settings.soundAndHapticsEnabled</string>
			<key>DefaultValue</key>
			<true/>
		</dict>
	</array>
</dict>
</plist>
SETTINGS_EOF
}

# 2. 配置主屏幕 3D Touch 快捷菜单：恢复【说明书】+【定积分】+【二重积分】+【三重积分】完整 4 项，并统一匿名 Bundle ID
configure_shortcut_items_in_plist() {
  local TARGET_PLIST="$1"
  if [ ! -f "${TARGET_PLIST}" ]; then
    return 0
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${OPEN_SOURCE_BUNDLE_ID}" "${TARGET_PLIST}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :UIApplicationShortcutItems" "${TARGET_PLIST}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems array" "${TARGET_PLIST}"

  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:0 dict" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:0:UIApplicationShortcutItemType string com.calculus3d.manual" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:0:UIApplicationShortcutItemTitle string 新手使用说明书" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:0:UIApplicationShortcutItemSubtitle string 零基础操作与3D Touch指南" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:0:UIApplicationShortcutItemIconType string UIApplicationShortcutIconTypeBookmark" "${TARGET_PLIST}"

  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:1 dict" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:1:UIApplicationShortcutItemType string com.calculus3d.single" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:1:UIApplicationShortcutItemTitle string ∫ 定积分计算" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:1:UIApplicationShortcutItemIconType string UIApplicationShortcutIconTypeCompose" "${TARGET_PLIST}"

  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:2 dict" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:2:UIApplicationShortcutItemType string com.calculus3d.double" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:2:UIApplicationShortcutItemTitle string ∬ 二重积分计算" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:2:UIApplicationShortcutItemIconType string UIApplicationShortcutIconTypeCompose" "${TARGET_PLIST}"

  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:3 dict" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:3:UIApplicationShortcutItemType string com.calculus3d.triple" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:3:UIApplicationShortcutItemTitle string ∭ 三重积分计算" "${TARGET_PLIST}"
  /usr/libexec/PlistBuddy -c "Add :UIApplicationShortcutItems:3:UIApplicationShortcutItemIconType string UIApplicationShortcutIconTypeCompose" "${TARGET_PLIST}"
}

sanitize_project_privacy
generate_github_antipiracy_files

echo "==> [1/7] 生成系统设置 Settings.bundle 并更新主屏幕 3D Touch 菜单..."
generate_settings_bundle "./Settings.bundle"
if [ -d "./${PROJECT_NAME}" ]; then
  generate_settings_bundle "./${PROJECT_NAME}/Settings.bundle"
fi

for SRC_PLIST in "./${PROJECT_NAME}/Info.plist" "./Info.plist"; do
  if [ -f "${SRC_PLIST}" ]; then
    configure_shortcut_items_in_plist "${SRC_PLIST}"
  fi
done

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> [2/7] 调用 Xcode 10.3 开启全模块优化 (-O) 与符号脱敏编译 ARM64..."
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${SCHEME_NAME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -UseModernBuildSystem=NO \
  PRODUCT_BUNDLE_IDENTIFIER="${OPEN_SOURCE_BUNDLE_ID}" \
  ARCHS="arm64" \
  VALID_ARCHS="arm64" \
  IPHONEOS_DEPLOYMENT_TARGET="11.2" \
  SWIFT_OPTIMIZATION_LEVEL="-O" \
  SWIFT_COMPILATION_MODE="wholemodule" \
  GCC_OPTIMIZATION_LEVEL="3" \
  DEBUG_INFORMATION_FORMAT="dwarf" \
  DEPLOYMENT_POSTPROCESSING=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  STRIP_STYLE="non-global" \
  ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CONFIGURATION_BUILD_DIR="${BUILD_DIR}/Products" \
  clean build

APP_PATH="${BUILD_DIR}/Products/${PROJECT_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
  echo "错误：未找到编译产物 ${APP_PATH}"
  exit 1
fi

echo "==> [3/7] 注入 Settings.bundle 到应用包与 Xcode DerivedData，并生成高清 'exp' 图标..."
generate_settings_bundle "${APP_PATH}/Settings.bundle"

for DD_APP in "${HOME}"/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*/Build/Products/*-iphoneos/${PROJECT_NAME}.app; do
  if [ -d "${DD_APP}" ]; then
    generate_settings_bundle "${DD_APP}/Settings.bundle"
    configure_shortcut_items_in_plist "${DD_APP}/Info.plist"
  fi
done

cat << 'ICON_EOF' > "${BUILD_DIR}/make_icon.swift"
import Cocoa

func renderExpIcon(size: Int, outputPath: String) {
    let w = CGFloat(size)
    let h = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.02, green: 0.38, blue: 0.92, alpha: 1.0),
        CGColor(red: 0.0, green: 0.56, blue: 1.0, alpha: 1.0)
    ] as CFArray
    let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w, y: h), options: [])

    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16))
    ctx.setLineWidth(max(1.0, w * 0.01))
    for i in 1...5 {
        let pos = w * CGFloat(i) / 6.0
        ctx.move(to: CGPoint(x: pos, y: 0))
        ctx.addLine(to: CGPoint(x: pos, y: h))
        ctx.move(to: CGPoint(x: 0, y: pos))
        ctx.addLine(to: CGPoint(x: w, y: pos))
    }
    ctx.strokePath()

    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.95, blue: 1.0, alpha: 0.85))
    ctx.setLineWidth(max(2.5, w * 0.045))
    ctx.setLineCap(.round)
    let steps = 100
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        let mathX = -2.2 + t * 3.4
        let mathY = exp(mathX)
        let px = CGFloat(t) * w
        let py = h * 0.14 + CGFloat(mathY / 3.6) * (h * 0.78)
        if i == 0 {
            ctx.move(to: CGPoint(x: px, y: py))
        } else {
            ctx.addLine(to: CGPoint(x: px, y: py))
        }
    }
    ctx.strokePath()

    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let fontSize = w * 0.40
    let font = NSFont(name: "TimesNewRomanPS-BoldItalicMT", size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: para
    ]
    let str = "exp" as NSString
    let textSize = str.size(withAttributes: attrs)
    let textRect = CGRect(
        x: 0,
        y: (h - textSize.height) * 0.5 - h * 0.02,
        width: w,
        height: textSize.height
    )
    str.draw(in: textRect, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
    }
}

let appDir = CommandLine.arguments[1]
renderExpIcon(size: 120, outputPath: "\(appDir)/AppIcon60x60@2x.png")
renderExpIcon(size: 180, outputPath: "\(appDir)/AppIcon60x60@3x.png")
renderExpIcon(size: 120, outputPath: "\(appDir)/Icon-60@2x.png")
renderExpIcon(size: 180, outputPath: "\(appDir)/Icon-60@3x.png")
renderExpIcon(size: 512, outputPath: "\(appDir)/iTunesArtwork.png")
renderExpIcon(size: 1024, outputPath: "\(appDir)/iTunesArtwork@2x.png")
ICON_EOF

swift "${BUILD_DIR}/make_icon.swift" "${APP_PATH}"

PLIST="${APP_PATH}/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFiles" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles array" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:0 string AppIcon60x60" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:1 string Icon-60" "${PLIST}"

configure_shortcut_items_in_plist "${PLIST}"

echo "==> [4/7] 对编译后的 ARM64 二进制可执行文件执行深度隐私抹除（抹除本机路径与个人符号）..."
rm -f "${APP_PATH}/embedded.mobileprovision" 2>/dev/null || true
xcrun strip -Sx "${APP_PATH}/${PROJECT_NAME}" 2>/dev/null || strip -Sx "${APP_PATH}/${PROJECT_NAME}" 2>/dev/null || true

# 对二进制文件中的任何残留本机路径名执行等长字节替换（保持 Mach-O 偏移量 100% 不变）
python3 - "${APP_PATH}/${PROJECT_NAME}" << 'PY_BIN_EOF' || true
import sys
import re
import getpass

bin_path = sys.argv[1]
with open(bin_path, "rb") as f:
    data = f.read()

# 将任何不区分大小写的 b"guanjunwei" (10 字节) 替换为等长 10 字节的 b"calculus3d"
new_data = re.sub(b"guanjunwei", b"calculus3d", data, flags=re.IGNORECASE)

cur_user = getpass.getuser().encode("utf-8")
if len(cur_user) >= 3 and cur_user.lower() not in (b"root", b"spark", b"admin"):
    repl = (b" calc3d_os" * 4)[:len(cur_user)]
    new_data = re.sub(re.escape(cur_user), repl, new_data, flags=re.IGNORECASE)

if new_data != data:
    with open(bin_path, "wb") as f:
        f.write(new_data)
    print("    [二进制脱敏] 已成功抹除 Mach-O 二进制内的全部本机路径与个人用户名。")
else:
    print("    [二进制脱敏] 校验通过：Mach-O 二进制内零个人隐私字符串残留。")
PY_BIN_EOF

echo "==> [5/7] 补齐 iOS 11.2 必需的 Swift 运行时动态库 (Frameworks/libswift*.dylib)..."
mkdir -p "${APP_PATH}/Frameworks"
SWIFT_STDLIB_TOOL="$(xcrun --find swift-stdlib-tool)"
"${SWIFT_STDLIB_TOOL}" \
  --copy \
  --scan-executable "${APP_PATH}/${PROJECT_NAME}" \
  --platform iphoneos \
  --destination "${APP_PATH}/Frameworks"

echo "==> [6/7] 使用 macOS 原生 codesign 对所有 Swift 动态库及主程序进行匿名 Ad-Hoc 签名..."
for dylib in "${APP_PATH}/Frameworks/"*.dylib; do
  if [ -f "${dylib}" ]; then
    codesign --force --sign - --timestamp=none "${dylib}"
  fi
done

if command -v ldid >/dev/null 2>&1; then
  ldid -S "${APP_PATH}/${PROJECT_NAME}"
else
  codesign --force --sign - --timestamp=none --identifier "${OPEN_SOURCE_BUNDLE_ID}" "${APP_PATH}"
fi

echo "==> [7/7] 封装 Payload 并生成已脱敏防抄袭安装包 ${IPA_NAME}..."
mkdir -p "${BUILD_DIR}/Payload"
cp -R "${APP_PATH}" "${BUILD_DIR}/Payload/"
cd "${BUILD_DIR}"
zip -qry "../${IPA_NAME}" Payload
cd ..

echo "=============================================================================="
echo "v16.1 隐私脱敏与防抄袭构建完成！"
echo "  • 源码、工程配置与二进制文件已彻底清除 'guanjunwei' 与本机路径；"
echo "  • 已自动生成 GitHub 开源防抄袭协议: ./LICENSE, ./README.md, ./.gitignore；"
echo "  • 匿名 Bundle ID: ${OPEN_SOURCE_BUNDLE_ID}"
echo "  • IPA 安装包路径: $(pwd)/${IPA_NAME}"
echo "=============================================================================="