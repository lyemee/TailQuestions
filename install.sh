#!/bin/bash
# TailQuestions 설치 / 업데이트
#   curl -fsSL https://raw.githubusercontent.com/lyemee/TailQuestions/main/install.sh | bash
set -euo pipefail

URL="https://github.com/lyemee/TailQuestions/releases/latest/download/TailQuestions.zip"
DEST="$HOME/Applications"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "⬇️  TailQuestions 내려받는 중…"
curl -fL --progress-bar "$URL" -o "$TMP/TailQuestions.zip"

pkill -x TailQuestions 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/TailQuestions.app"
ditto -x -k "$TMP/TailQuestions.zip" "$DEST"
# 직접 내려받은 앱이라 macOS의 '확인되지 않은 개발자' 경고가 뜨지 않게 격리 표시를 지운다
xattr -dr com.apple.quarantine "$DEST/TailQuestions.app" 2>/dev/null || true
open "$DEST/TailQuestions.app"

echo "✅ 설치 완료: ~/Applications/TailQuestions.app"
echo "   앱에 뜨는 설정 도우미를 따라 Claude Code 로그인과 손쉬운 사용 권한을 켜 주세요."
