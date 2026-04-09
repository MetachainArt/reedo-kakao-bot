#!/bin/bash
echo "============================================"
echo "  systemd 서비스 등록 (24시간 자동 실행)"
echo "============================================"

INSTALL_DIR="$HOME/reedo-kakao-bot"
SERVICE_FILE="$INSTALL_DIR/reedo-daemon.service"
USER=$(whoami)

if [ ! -f "$SERVICE_FILE" ]; then
    echo "[ERROR] $SERVICE_FILE 파일이 없습니다."
    exit 1
fi

# 1. sudoers 설정 (docker cp, chmod에 비밀번호 없이 실행)
echo "[1/3] sudoers 설정..."
sudo bash -c "echo '$USER ALL=(ALL) NOPASSWD: /usr/bin/docker cp *, /usr/bin/chmod *' > /etc/sudoers.d/reedo-daemon"
echo "[OK]"

# 2. 서비스 파일에서 유저/경로 치환 후 복사
echo "[2/3] systemd 서비스 등록..."
TMP_SERVICE="/tmp/reedo-daemon.service"
sed -e "s|User=reedo|User=$USER|g" \
    -e "s|WorkingDirectory=/home/reedo|WorkingDirectory=$HOME|g" \
    -e "s|/home/reedo/reedo-kakao-bot|$INSTALL_DIR|g" \
    -e "s|/home/reedo/reedo-daemon.log|$HOME/reedo-daemon.log|g" \
    -e "s|HOME=/home/reedo|HOME=$HOME|g" \
    -e "s|/home/reedo/.npm-global|$HOME/.npm-global|g" \
    "$SERVICE_FILE" > "$TMP_SERVICE"

sudo cp "$TMP_SERVICE" /etc/systemd/system/reedo-daemon.service
sudo systemctl daemon-reload
sudo systemctl enable reedo-daemon
echo "[OK]"

# 3. 기존 포그라운드 데몬 종료 후 서비스 시작
echo "[3/3] 서비스 시작..."
pkill -f "reedo-daemon-vps.py" 2>/dev/null || true
sleep 1
sudo systemctl start reedo-daemon
echo "[OK]"

echo ""
echo "============================================"
echo "  설정 완료!"
echo ""
echo "  상태: sudo systemctl status reedo-daemon"
echo "  로그: tail -f ~/reedo-daemon.log"
echo "  중지: sudo systemctl stop reedo-daemon"
echo "  재시작: sudo systemctl restart reedo-daemon"
echo "============================================"
