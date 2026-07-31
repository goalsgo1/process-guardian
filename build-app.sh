#!/bin/bash
# ProcessGuardian.app 번들을 만든다. 서명/공증은 별도 스크립트(sign-and-notarize.sh)에서 진행.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ProcessGuardian"
BUNDLE_ID="com.haeminlee.processguardian"
VERSION="1.0.0"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"

echo "==> Release 빌드"
swift build -c release

echo "==> .app 번들 구조 생성"
rm -rf "${DIST_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Process Guardian</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Personal use only.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "==> 완료: ${APP_DIR}"
