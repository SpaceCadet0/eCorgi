#!/bin/bash
# Собирает eCorgi.app из SPM-сборки.
# Использование: scripts/build_app.sh [debug|release]   (по умолчанию release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/eCorgi.app"

cd "$ROOT"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/eCorgi" "$APP/Contents/MacOS/eCorgi"
cp -R "$BIN_DIR/eCorgi_eCorgiKit.bundle" "$APP/Contents/Resources/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Скачанные спрайты приносят com.apple.quarantine, а codesign отказывается
# подписывать бандл с расширенными атрибутами.
xattr -cr "$APP"

# Ad-hoc подпись: для локального запуска хватает.
# Перед раздачей — Developer ID + notarytool (см. PLAN.md, раздел 7).
codesign --force --deep --sign - "$APP"

echo "Собрано: $APP"
