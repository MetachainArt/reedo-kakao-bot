#!/bin/bash
echo "============================================"
echo "  카카오톡 봇 시작 (Windows WSL2)"
echo "============================================"

INSTALL_DIR="$HOME/reedo-kakao-bot"
CONFIG="$INSTALL_DIR/config.json"
BOT_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG'))['bot_name'])" 2>/dev/null || echo "봇")

# ===================================
# 1. Binder 마운트 (매 부팅마다 필요!)
# ===================================
echo "[1/5] Binder 마운트..."
# PITFALL: WSL2는 매 부팅마다 binderfs 마운트가 초기화됨
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs 2>/dev/null || true

# PITFALL: 심볼릭 링크도 매번 다시 만들어야 함
sudo ln -sf /dev/binderfs/anbox-binder /dev/anbox-binder 2>/dev/null
sudo ln -sf /dev/binderfs/anbox-hwbinder /dev/anbox-hwbinder 2>/dev/null
sudo ln -sf /dev/binderfs/anbox-vndbinder /dev/anbox-vndbinder 2>/dev/null
echo "[OK]"

# ===================================
# 2. nftables 모드 확인
# ===================================
echo "[2/5] nftables 모드 확인..."
# PITFALL: LXC_USE_NFT="false"이면 Waydroid 네트워크 안 됨
if [ -f "/usr/lib/waydroid/data/scripts/waydroid-net.sh" ]; then
    sudo sed -i 's/LXC_USE_NFT="false"/LXC_USE_NFT="true"/' \
        /usr/lib/waydroid/data/scripts/waydroid-net.sh 2>/dev/null
fi
echo "[OK]"

# ===================================
# 3. Waydroid 컨테이너 시작
# ===================================
echo "[3/5] Waydroid 컨테이너 시작..."
sudo waydroid container start 2>/dev/null || true
echo "[OK]"

# ===================================
# 4. Waydroid 세션 + UI (백그라운드)
# ===================================
echo "[4/5] Waydroid 세션 시작..."
waydroid session start &>/dev/null &
sleep 3
waydroid show-full-ui &>/dev/null &
sleep 2

# ADB Keyboard 설치 + 활성화 (매번 확인)
ADB_APK="$HOME/ADBKeyBoard.apk"
if [ -f "$ADB_APK" ] && [ -s "$ADB_APK" ]; then
    waydroid app install "$ADB_APK" 2>/dev/null || true
    sudo waydroid shell -- settings put secure enabled_input_methods \
        "com.android.adbkeyboard/.AdbIME:com.android.inputmethod.latin/.LatinIME" 2>/dev/null
    sudo waydroid shell -- ime enable com.android.adbkeyboard/.AdbIME 2>/dev/null
    sudo waydroid shell -- ime set com.android.adbkeyboard/.AdbIME 2>/dev/null
fi
echo "[OK]"

# ===================================
# 5. 데몬 시작
# ===================================
echo "[5/5] $BOT_NAME 데몬 시작..."
echo ""
echo "============================================"
echo "  $BOT_NAME 봇이 실행 중입니다!"
echo "  DM: 자동 답장"
echo "  그룹: '$BOT_NAME' 이라고 부르면 답장"
echo "  종료: Ctrl+C"
echo "============================================"
echo ""

# Clean up old temp DB
sudo rm -f /tmp/reedo_kakao.db*

# PITFALL: sudo HOME=$HOME 필수!
# sudo는 HOME을 /root로 바꾸므로, openclaw 경로를 찾지 못함
sudo HOME="$HOME" python3 "$INSTALL_DIR/reedo-daemon.py" --config "$CONFIG"
