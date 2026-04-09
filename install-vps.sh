#!/bin/bash
set -e

echo "============================================"
echo "  카카오톡 자동응답 봇 설치 (VPS/Linux)"
echo "  (ReDroid Docker + ADB + OpenClaw)"
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
    python3 python3-pip sqlite3 git curl wget adb 2>/dev/null

# pycryptodome for kakaodecrypt
sudo pip3 install pycryptodome --break-system-packages 2>/dev/null || \
    pip3 install pycryptodome 2>/dev/null || true
echo "[OK] 패키지 설치 완료"

# ===================================
# 2. Docker 설치
# ===================================
echo ""
echo "[2/8] Docker 설치 확인..."
if command -v docker &>/dev/null; then
    echo "[OK] Docker 이미 설치됨: $(docker --version)"
else
    echo "Docker 설치 중..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    echo "[OK] Docker 설치 완료"
    echo "[!] Docker 그룹 적용을 위해 재로그인 필요할 수 있습니다."
fi

# ===================================
# 3. 커널 모듈 (binder_linux)
# ===================================
echo ""
echo "[3/8] 커널 모듈 확인..."
# PITFALL: VPS에서는 linux-modules-extra 패키지가 필요
if ! lsmod | grep -q binder_linux; then
    echo "binder_linux 모듈 로드 중..."
    sudo apt-get install -y "linux-modules-extra-$(uname -r)" 2>/dev/null || true
    sudo modprobe binder_linux 2>/dev/null || true

    if ! lsmod | grep -q binder_linux; then
        echo "[WARN] binder_linux 모듈 로드 실패"
        echo "       커널이 binder를 지원하지 않을 수 있습니다."
        echo "       VPS 호스팅 업체에 문의하거나 커널 업그레이드가 필요합니다."
    else
        echo "[OK] binder_linux 모듈 로드 완료"
    fi

    # Persist across reboots
    echo "binder_linux" | sudo tee /etc/modules-load.d/binder.conf >/dev/null
else
    echo "[OK] binder_linux 이미 로드됨"
fi

# binderfs 마운트
if ! mount | grep -q binderfs; then
    sudo mkdir -p /dev/binderfs
    sudo mount -t binder binder /dev/binderfs 2>/dev/null || true
    echo "[OK] binderfs 마운트"
fi

# ===================================
# 4. ReDroid Docker 컨테이너
# ===================================
echo ""
echo "[4/8] ReDroid 컨테이너 확인..."
if sudo docker ps -a | grep -q redroid; then
    echo "[OK] redroid 컨테이너 이미 존재"
    # Start if stopped
    sudo docker start redroid 2>/dev/null || true
else
    echo "ReDroid 컨테이너 생성 중..."
    # PITFALL: -v redroid-data:/data 필수! 데이터 영속성을 위해 Docker volume 사용
    # PITFALL: -v /dev/binderfs:/dev/binderfs 필수! binder IPC 지원
    sudo docker run -d \
        --name redroid \
        --privileged \
        -v /dev/binderfs:/dev/binderfs \
        -v redroid-data:/data \
        -p 5555:5555 \
        redroid/redroid:13.0.0-latest \
        androidboot.use_memfd=true \
        redroid.gpu.mode=guest
    echo "[OK] ReDroid 컨테이너 생성 완료"
    echo "    시작까지 30-60초 대기..."
    sleep 30
fi

# ===================================
# 5. ADB 연결
# ===================================
echo ""
echo "[5/8] ADB 연결..."
adb connect localhost:5555 2>/dev/null || true
sleep 2
if adb -s localhost:5555 shell echo ok 2>/dev/null | grep -q ok; then
    echo "[OK] ADB 연결 완료"
else
    echo "[WARN] ADB 연결 실패. ReDroid가 완전히 시작될 때까지 기다려주세요."
    echo "       수동 연결: adb connect localhost:5555"
fi

# ===================================
# 6. ADB Keyboard 설치
# ===================================
echo ""
echo "[6/8] ADB Keyboard 설치..."
ADB_APK="$HOME/ADBKeyBoard.apk"
if [ ! -f "$ADB_APK" ] || [ ! -s "$ADB_APK" ]; then
    wget -q "https://github.com/senzhk/ADBKeyBoard/releases/download/v2.4-dev/keyboardservice-debug.apk" \
        -O "$ADB_APK"
fi
adb -s localhost:5555 install "$ADB_APK" 2>/dev/null || echo "[WARN] APK 설치 실패 - ReDroid 시작 후 재시도"

# ADB Keyboard 활성화
adb -s localhost:5555 shell settings put secure enabled_input_methods \
    "com.android.adbkeyboard/.AdbIME:com.android.inputmethod.latin/.LatinIME" 2>/dev/null || true
adb -s localhost:5555 shell ime enable com.android.adbkeyboard/.AdbIME 2>/dev/null || true
adb -s localhost:5555 shell ime set com.android.adbkeyboard/.AdbIME 2>/dev/null || true
echo "[OK] ADB Keyboard 설정 완료"

# ===================================
# 7. kakaodecrypt 설치
# ===================================
echo ""
echo "[7/8] kakaodecrypt 설치 중..."
if [ -d "$HOME/kakaodecrypt" ]; then
    echo "[OK] 이미 설치됨"
else
    git clone https://github.com/jiru/kakaodecrypt.git "$HOME/kakaodecrypt"
    echo "[OK] kakaodecrypt 설치 완료"
fi

# ===================================
# 8. 봇 파일 복사 + 설정
# ===================================
echo ""
echo "[8/8] 봇 설정..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/" 2>/dev/null || true

# sudo 권한 설정
# PITFALL: daemon이 docker cp와 chmod을 sudo로 실행해야 함
SUDOERS_FILE="/etc/sudoers.d/reedo-kakao-bot"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "sudo 권한 설정 중..."
    CURRENT_USER=$(whoami)
    sudo tee "$SUDOERS_FILE" > /dev/null << EOFSUDOERS
# reedo-kakao-bot: daemon needs sudo for docker cp and chmod
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/docker cp *
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/chmod *
EOFSUDOERS
    sudo chmod 440 "$SUDOERS_FILE"
    echo "[OK] sudo 권한 설정 완료"
fi

if [ ! -f "$INSTALL_DIR/config.json" ] || [ "$1" = "--reconfigure" ]; then
    echo ""
    echo "봇 이름을 입력하세요 (기본: 뽀리):"
    read -r BOT_NAME
    BOT_NAME="${BOT_NAME:-뽀리}"

    echo "말투를 입력하세요 (기본: 존댓말로 친근하고 귀엽게. 이모티콘 적당히.):"
    read -r STYLE
    STYLE="${STYLE:-존댓말로 친근하고 귀엽게. 이모티콘 적당히.}"

    # Detect OpenClaw path
    OPENCLAW_PATH=$(which openclaw 2>/dev/null || echo "")
    if [ -z "$OPENCLAW_PATH" ]; then
        OPENCLAW_PATH="$HOME/.npm-global/bin/openclaw"
    fi
    echo "OpenClaw 경로: $OPENCLAW_PATH"

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
echo "  1. 카카오톡 설치 (scrcpy 사용):"
echo "     로컬에서: scrcpy --tcpip=$(curl -s ifconfig.me):5555 --no-audio"
echo "     또는: adb -s localhost:5555 install-multiple base.apk split_config.*.apk"
echo ""
echo "  2. OpenClaw 설정: bash $INSTALL_DIR/setup-openclaw.sh"
echo "  3. 봇 시작:      bash $INSTALL_DIR/start-vps.sh"
echo ""
echo "=== 카카오톡 APK 설치 (split APK) ==="
echo "  adb -s localhost:5555 install-multiple base.apk split_config.arm64_v8a.apk split_config.xxhdpi.apk split_config.ko.apk"
echo ""
