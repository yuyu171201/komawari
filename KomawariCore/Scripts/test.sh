#!/bin/sh
# Swift のテストを実行する。
# Xcode を入れていない環境（コマンドラインツールのみ）では Testing フレームワークが
# 既定の検索パスに無いので、場所を明示する。Xcode があれば `swift test` だけでよい。
set -e
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools
FRAMEWORKS=$CLT/Library/Developer/Frameworks
if ! xcodebuild -version >/dev/null 2>&1 && [ -d "$FRAMEWORKS/Testing.framework" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib" "$@"
fi
exec swift test "$@"
