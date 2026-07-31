#!/bin/bash
# ProcessGuardian.app을 서명하고 애플에 공증(notarize) 제출한다.
# 사전 조건: build-app.sh로 dist/ProcessGuardian.app이 이미 만들어져 있어야 하고,
#            `xcrun notarytool store-credentials "process-guardian" ...` 로 자격 증명이
#            키체인에 저장되어 있어야 한다 (앱 전용 암호 필요, appleid.apple.com에서 발급).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ProcessGuardian"
APP_PATH="dist/${APP_NAME}.app"
SIGNING_IDENTITY="Developer ID Application: Haemin Lee (T6ZG22W7A9)"
KEYCHAIN_PROFILE="process-guardian"
ZIP_PATH="dist/${APP_NAME}.zip"

if [ ! -d "$APP_PATH" ]; then
    echo "먼저 ./build-app.sh 를 실행해서 ${APP_PATH} 을 만들어야 합니다." >&2
    exit 1
fi

echo "==> 코드 서명 (hardened runtime)"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_PATH"

echo "==> 서명 검증"
codesign --verify --strict --verbose=2 "$APP_PATH"

echo "==> 공증 제출용 zip 생성"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> 공증 제출 (몇 분 걸릴 수 있음, 완료까지 대기)"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "==> 공증 티켓 붙이기(staple)"
xcrun stapler staple "$APP_PATH"

echo "==> 완료: ${APP_PATH} (서명+공증됨)"
