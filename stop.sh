#!/bin/bash
echo "============================================"
echo "  카카오톡 봇 종료"
echo "============================================"
echo ""

# Detect environment
if command -v waydroid &>/dev/null; then
    MODE="windows"
else
    MODE="vps"
fi

# Stop daemon
echo "[1/3] 데몬 종료..."
sudo pkill -f "reedo-daemon.py" 2>/dev/null || true
sudo pkill -f "reedo-daemon-vps.py" 2>/dev/null || true
echo "[OK]"

if [ "$MODE" = "windows" ]; then
    # Windows WSL2 mode
    echo "[2/3] Waydroid 세션 종료..."
    sudo waydroid session stop 2>/dev/null || true
    echo "[OK]"

    echo "[3/3] Waydroid 컨테이너 종료..."
    sudo waydroid container stop 2>/dev/null || true
    echo "[OK]"
else
    # VPS mode - don't stop ReDroid (it keeps KakaoTalk session)
    echo "[2/3] ADB 연결 해제..."
    adb disconnect localhost:5555 2>/dev/null || true
    echo "[OK]"

    echo "[3/3] ReDroid 컨테이너는 유지합니다 (카카오톡 세션 보존)."
    echo "      완전 종료: sudo docker stop redroid"
fi

# Clean up temp files
rm -f /tmp/reedo_kakao.db*

echo ""
echo "종료 완료!"
