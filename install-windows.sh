#!/bin/bash
set -e

echo "============================================"
echo "  카카오톡 자동응답 봇 설치 (Windows WSL2)"
echo "  (WSL2 + Waydroid + OpenClaw)"
echo "============================================"
echo ""

INSTALL_DIR="$HOME/reedo-kakao-bot"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ===================================
# 1. 필수 패키지 설치
# ===================================
echo "[1/8] 필수 패키지 설치 중..."
sudo apt-get update -qq
sudo apt-get install -y \
    build-essential flex bison libssl-dev libelf-dev \
    dwarves bc python3 python3-pip sqlite3 git curl wget \
    cpio lzip pahole adb 2>/dev/null

# PITFALL: pip install은 --break-system-packages 필요 (Ubuntu 24.04+)
sudo pip3 install pycryptodome --break-system-packages 2>/dev/null || \
    pip3 install pycryptodome 2>/dev/null || true
echo "[OK] 패키지 설치 완료"

# ===================================
# 2. kakaodecrypt 설치
# ===================================
echo ""
echo "[2/8] kakaodecrypt 설치 중..."
if [ -d "$HOME/kakaodecrypt" ]; then
    echo "[OK] 이미 설치됨"
else
    git clone https://github.com/jiru/kakaodecrypt.git "$HOME/kakaodecrypt"
    echo "[OK] kakaodecrypt 설치 완료"
fi

# ===================================
# 3. 커널 확인 (bridge + binder 지원)
# ===================================
echo ""
echo "[3/8] WSL2 커널 확인..."
KERNEL_OK=true

# Check bridge support
if ! sudo ip link add __test_br type bridge 2>/dev/null; then
    echo "[!] bridge 미지원"
    KERNEL_OK=false
else
    sudo ip link del __test_br 2>/dev/null
    echo "  [OK] bridge 지원"
fi

# Check binder support
if ! grep -q binder /proc/filesystems 2>/dev/null; then
    echo "[!] binder 미지원"
    KERNEL_OK=false
else
    echo "  [OK] binder 지원"
fi

if [ "$KERNEL_OK" = false ]; then
    echo ""
    echo "[!] 커스텀 커널이 필요합니다."
    echo "    다음 명령을 실행하세요:"
    echo ""
    echo "    bash $SCRIPT_DIR/kernel/build-kernel.sh"
    echo ""
    echo "    커널 빌드 후 이 스크립트를 다시 실행하세요."
    exit 1
fi
echo "[OK] 커널 확인 완료"

# ===================================
# 4. Waydroid 설치
# ===================================
echo ""
echo "[4/8] Waydroid 설치 중..."
if command -v waydroid &>/dev/null; then
    echo "[OK] 이미 설치됨: $(waydroid --version 2>&1 || echo 'unknown')"
else
    curl -s https://repo.waydro.id | sudo bash
    sudo apt-get install -y waydroid
    echo "[OK] Waydroid 설치 완료"
fi

# ===================================
# 5. Waydroid 초기화 + GAPPS
# ===================================
echo ""
echo "[5/8] Waydroid 초기화..."
if [ -f "/var/lib/waydroid/waydroid.cfg" ]; then
    echo "[OK] 이미 초기화됨"
else
    # PITFALL: -s GAPPS 필수! Play Store에서 카카오톡 설치하려면 Google 서비스 필요
    sudo waydroid init -s GAPPS
    echo "[OK] Waydroid 초기화 완료 (GAPPS 포함)"
fi

# ===================================
# 6. ARM 호환 레이어 (libhoudini)
# ===================================
echo ""
echo "[6/8] ARM 호환 레이어 설치..."
if [ -d "/tmp/waydroid_script" ]; then
    echo "[OK] waydroid_script 이미 존재"
else
    git clone https://github.com/casualsnek/waydroid_script.git /tmp/waydroid_script 2>/dev/null || true
fi
cd /tmp/waydroid_script 2>/dev/null || true
sudo pip3 install inquirer InquirerPy tqdm --break-system-packages 2>/dev/null || \
    pip3 install inquirer InquirerPy tqdm 2>/dev/null || true
sudo python3 main.py install libhoudini 2>/dev/null || \
    echo "[WARN] libhoudini 자동 설치 실패 - 수동 설치 필요"
cd - >/dev/null 2>&1

# nftables 모드 설정
# PITFALL: 기본 LXC_USE_NFT="false"이면 Waydroid 네트워크 안 됨
if [ -f "/usr/lib/waydroid/data/scripts/waydroid-net.sh" ]; then
    sudo sed -i 's/LXC_USE_NFT="false"/LXC_USE_NFT="true"/' \
        /usr/lib/waydroid/data/scripts/waydroid-net.sh
    echo "[OK] nftables 모드 활성화"
fi

# ===================================
# 7. ADB Keyboard 다운로드
# ===================================
echo ""
echo "[7/8] ADB Keyboard 다운로드..."
ADB_APK="$HOME/ADBKeyBoard.apk"
if [ ! -f "$ADB_APK" ] || [ ! -s "$ADB_APK" ]; then
    wget -q "https://github.com/senzhk/ADBKeyBoard/releases/download/v2.4-dev/keyboardservice-debug.apk" \
        -O "$ADB_APK"
    echo "[OK] ADB Keyboard 다운로드 완료"
else
    echo "[OK] 이미 다운로드됨"
fi

# ===================================
# 8. 봇 파일 복사 + 설정
# ===================================
echo ""
echo "[8/8] 봇 설정..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/" 2>/dev/null || true

if [ ! -f "$INSTALL_DIR/config.json" ] || [ "$1" = "--reconfigure" ]; then
    echo ""
    echo "봇 이름을 입력하세요 (기본: 뽀리):"
    read -r BOT_NAME
    BOT_NAME="${BOT_NAME:-뽀리}"

    echo "말투를 입력하세요 (기본: 존댓말로 친근하고 귀엽게. 이모티콘 적당히.):"
    read -r STYLE
    STYLE="${STYLE:-존댓말로 친근하고 귀엽게. 이모티콘 적당히.}"

    cat > "$INSTALL_DIR/config.json" << EOFCONFIG
{
  "bot_name": "$BOT_NAME",
  "style": "$STYLE",
  "model": "openai-codex/gpt-5.4",
  "interval": 5,
  "reply_all_dm": true,
  "group_trigger": "$BOT_NAME",
  "max_reply_length": 1000,
  "openclaw_agent_id": "kakao",
  "quiet_hours_start": 23,
  "quiet_hours_end": 8
}
EOFCONFIG
    echo "[OK] config.json 생성 완료"
else
    echo "[OK] config.json 이미 존재"
fi

echo ""
echo "============================================"
echo "  설치 완료!"
echo "============================================"
echo ""
echo "다음 단계:"
echo "  1. 카카오톡 설치: bash $INSTALL_DIR/setup-kakao.sh"
echo "  2. OpenClaw 설정: bash $INSTALL_DIR/setup-openclaw.sh"
echo "  3. 봇 시작:      bash $INSTALL_DIR/start-windows.sh"
echo ""
