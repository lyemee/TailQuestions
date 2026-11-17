#!/bin/bash
# TailQuestions.app 을 빌드한다.  ./scripts/build-app.sh --install 로 ~/Applications 에 설치 후 실행.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/TailQuestions.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TailQuestions "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
IDENTITY="TailQuestions Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  # 고정 인증서로 서명 → 다시 빌드해도 손쉬운 사용 권한이 유지됨
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "⚠️  서명 인증서가 없어서 임시 서명해요. 다시 빌드하면 손쉬운 사용 권한을 다시 등록해야 해요."
  echo "    ./scripts/setup-signing.sh 를 한 번 실행하면 해결돼요."
  codesign --force --sign - "$APP"
fi
echo "✅ $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x TailQuestions 2>/dev/null || true
  rm -rf "$HOME/Applications/TailQuestions.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/TailQuestions.app"
  echo "✅ ~/Applications/TailQuestions.app 설치 및 실행"
fi
