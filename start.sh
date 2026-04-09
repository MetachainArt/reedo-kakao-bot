#!/bin/bash
# Legacy redirect - use start-windows.sh or start-vps.sh instead
echo "[!] start.sh는 더 이상 사용하지 않습니다."
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-detect and redirect
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "WSL2 환경 감지. start-windows.sh 실행..."
    exec bash "$SCRIPT_DIR/start-windows.sh" "$@"
else
    echo "Linux 환경 감지. start-vps.sh 실행..."
    exec bash "$SCRIPT_DIR/start-vps.sh" "$@"
fi
