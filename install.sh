#!/bin/bash
# Legacy redirect - use install-windows.sh or install-vps.sh instead
echo "[!] install.sh는 더 이상 사용하지 않습니다."
echo ""
echo "대신 다음을 사용하세요:"
echo "  Windows WSL2: bash install-windows.sh"
echo "  VPS (Linux):  bash install-vps.sh"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-detect and redirect
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "WSL2 환경 감지. install-windows.sh 실행..."
    exec bash "$SCRIPT_DIR/install-windows.sh" "$@"
elif command -v docker &>/dev/null || [ -f /etc/os-release ]; then
    echo "Linux 환경 감지. install-vps.sh 실행..."
    exec bash "$SCRIPT_DIR/install-vps.sh" "$@"
fi
