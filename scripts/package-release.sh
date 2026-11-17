#!/bin/bash
# 배포용 zip 을 만든다 → build/TailQuestions.zip
# 릴리스: gh release create v<버전> build/TailQuestions.zip
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh --universal
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
rm -f build/TailQuestions.zip
ditto -c -k --keepParent build/TailQuestions.app build/TailQuestions.zip
echo "✅ build/TailQuestions.zip (v$VERSION)"
echo "   gh release create v$VERSION build/TailQuestions.zip --title \"TailQuestions v$VERSION\""
