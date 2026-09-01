#!/bin/bash
# Пересобирает и перезапускает eCorgi.app.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkill -x eCorgi 2>/dev/null || true
"$ROOT/scripts/build_app.sh" "${1:-debug}"
open "$ROOT/build/eCorgi.app"
echo "Запущено. Остановить: pkill -x eCorgi"
