#!/bin/bash
# TailQuestions.app 을 빌드한다.
#   ./scripts/build-app.sh               이 Mac용으로 빌드
#   ./scripts/build-app.sh --install     빌드 후 ~/Applications 에 설치하고 실행
#   ./scripts/build-app.sh --universal   Apple Silicon + Intel 둘 다 되는 빌드 (배포용)
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=false
UNIVERSAL=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --universal) UNIVERSAL=true ;;
  esac
done

APP=build/TailQuestions.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if $UNIVERSAL; then
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  lipo -create \
    .build/arm64-apple-macosx/release/TailQuestions \
    .build/x86_64-apple-macosx/release/TailQuestions \
    -output "$APP/Contents/MacOS/TailQuestions"
else
  swift build -c release
  cp .build/release/TailQuestions "$APP/Contents/MacOS/"
fi

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
echo "✅ $APP ($(lipo -archs "$APP/Contents/MacOS/TailQuestions"))"

if $INSTALL; then
  mkdir -p "$HOME/Applications"
  pkill -x TailQuestions 2>/dev/null || true
  rm -rf "$HOME/Applications/TailQuestions.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/TailQuestions.app"
  echo "✅ ~/Applications/TailQuestions.app 설치 및 실행"
fi
