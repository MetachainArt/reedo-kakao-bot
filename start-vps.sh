#!/bin/bash
echo "============================================"
echo "  카카오톡 봇 시작 (VPS/ReDroid)"
echo "============================================"

INSTALL_DIR="$HOME/reedo-kakao-bot"
CONFIG="$INSTALL_DIR/config.json"
BOT_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG'))['bot_name'])" 2>/dev/null || echo "봇")

# ===================================
# 1. binder 모듈 확인
# ===================================
echo "[1/4] binder 모듈 확인..."
if ! lsmod | grep -q binder_linux; then
    sudo modprobe binder_linux 2>/dev/null || true
fi
if ! mount | grep -q binderfs; then
    sudo mkdir -p /dev/binderfs
    sudo mount -t binder binder /dev/binderfs 2>/dev/null || true
fi
echo "[OK]"

# ===================================
# 2. ReDroid 컨테이너 시작
# ===================================
echo "[2/4] ReDroid 컨테이너 확인..."
if sudo docker ps | grep -q redroid; then
    echo "[OK] 이미 실행 중"
else
    sudo docker start redroid 2>/dev/null || {
        echo "[!] ReDroid 컨테이너가 없습니다. install-vps.sh를 먼저 실행하세요."
        exit 1
    }
    echo "ReDroid 시작 대기 (30초)..."
    sleep 30
    echo "[OK]"
fi

# ===================================
# 3. ADB 연결
# ===================================
echo "[3/4] ADB 연결..."
adb connect localhost:5555 2>/dev/null || true
sleep 2
if adb -s localhost:5555 shell echo ok 2>/dev/null | grep -q ok; then
    echo "[OK] ADB 연결 완료"

    # ADB Keyboard 활성화 확인
    adb -s localhost:5555 shell ime set com.android.adbkeyboard/.AdbIME 2>/dev/null || true
else
    echo "[WARN] ADB 연결 실패. 잠시 후 재시도..."
    sleep 10
    adb connect localhost:5555 2>/dev/null || true
fi

# ===================================
# 4. 데몬 시작
# ===================================
echo "[4/4] $BOT_NAME 데몬 시작..."
echo ""
echo "============================================"
echo "  $BOT_NAME 봇이 실행 중입니다!"
echo "  DM: 자동 답장"
echo "  그룹: '$BOT_NAME' 이라고 부르면 답장"
echo "  종료: Ctrl+C"
echo "============================================"
echo ""
echo "화면 접근: scrcpy --tcpip=localhost:5555 --no-audio"
echo ""

# Clean up old temp DB
rm -f /tmp/reedo_kakao.db*

# Detect OpenClaw path
OPENCLAW_PATH=$(which openclaw 2>/dev/null || echo "$HOME/.npm-global/bin/openclaw")
export OPENCLAW_BIN="$OPENCLAW_PATH"

python3 "$INSTALL_DIR/reedo-daemon-vps.py" --config "$CONFIG"
