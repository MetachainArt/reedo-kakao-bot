#!/bin/bash
set -e

echo "============================================"
echo "  WSL2 커스텀 커널 빌드"
echo "  (Waydroid용 binder + bridge + netfilter)"
echo "============================================"
echo ""
echo "이 작업은 30-40분 소요됩니다."
echo ""

# === PITFALL: cpio 패키지가 없으면 빌드 실패! ===
echo "[0/6] 빌드 의존성 확인..."
MISSING_PKGS=""
for pkg in build-essential flex bison libssl-dev libelf-dev dwarves bc cpio lzip pahole; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

if [ -n "$MISSING_PKGS" ]; then
    echo "누락된 패키지 설치:$MISSING_PKGS"
    sudo apt-get update -qq
    sudo apt-get install -y $MISSING_PKGS
fi
echo "[OK] 빌드 의존성 확인 완료"

# 1. 소스 다운로드
echo ""
echo "[1/6] 커널 소스 다운로드..."
cd ~
if [ -d "WSL2-Linux-Kernel" ]; then
    echo "이미 존재. 업데이트..."
    cd WSL2-Linux-Kernel && git pull 2>/dev/null || true
else
    git clone --depth 1 --branch linux-msft-wsl-6.6.y \
        https://github.com/microsoft/WSL2-Linux-Kernel.git
    cd WSL2-Linux-Kernel
fi

# 2. 설정
echo ""
echo "[2/6] 커널 설정..."
cp /proc/config.gz . 2>/dev/null || true
gunzip -f config.gz 2>/dev/null || true
cp config .config 2>/dev/null || true
chmod 644 .config

# === Waydroid 필수 설정 ===
# Android binder IPC (Waydroid 핵심)
scripts/config --enable CONFIG_ASHMEM
scripts/config --enable CONFIG_ANDROID
scripts/config --enable CONFIG_ANDROID_BINDER_IPC
scripts/config --enable CONFIG_ANDROID_BINDERFS
scripts/config --set-val CONFIG_ANDROID_BINDER_DEVICES '""'

# === 네트워크 설정 (전부 =y 내장, =m 모듈은 안 됨!) ===
# PITFALL: 반드시 =y (built-in)로 설정해야 함. =m (module)으로 하면 Waydroid 네트워크 안 됨!
scripts/config --set-val CONFIG_BRIDGE y
scripts/config --set-val CONFIG_VETH y
scripts/config --set-val CONFIG_NF_NAT y
scripts/config --set-val CONFIG_NF_TABLES y
scripts/config --set-val CONFIG_NFT_NAT y
scripts/config --set-val CONFIG_NFT_MASQ y
scripts/config --set-val CONFIG_NF_CONNTRACK y
scripts/config --set-val CONFIG_NETFILTER_XTABLES y
scripts/config --set-val CONFIG_IP_NF_IPTABLES y
scripts/config --set-val CONFIG_IP_NF_NAT y
scripts/config --set-val CONFIG_IP_NF_FILTER y
scripts/config --set-val CONFIG_BRIDGE_NETFILTER y

echo "[OK] 설정 완료"
echo ""
echo "설정 검증..."
echo "  CONFIG_ANDROID=$(grep CONFIG_ANDROID= .config | head -1)"
echo "  CONFIG_BRIDGE=$(grep CONFIG_BRIDGE= .config | head -1)"
echo "  CONFIG_NF_NAT=$(grep CONFIG_NF_NAT= .config | head -1)"

# 3. 빌드
echo ""
echo "[3/6] 커널 빌드 중... (30-40분 소요)"
make olddefconfig
make -j$(nproc)
echo "[OK] 빌드 완료"

# 4. 모듈 설치
echo ""
echo "[4/6] 모듈 설치..."
sudo make modules_install
echo "[OK]"

# 5. iproute2 업그레이드 (Ubuntu 24.04의 iproute2 6.1은 커널 6.6과 호환 안 됨)
echo ""
echo "[5/6] iproute2 업그레이드 확인..."
IPROUTE_VER=$(ip -V 2>&1 | grep -oP 'iproute2-\K[0-9.]+' || echo "0")
KERNEL_VER=$(uname -r | grep -oP '^[0-9]+\.[0-9]+' || echo "0")
echo "  현재 iproute2: $IPROUTE_VER, 커널: $KERNEL_VER"

# PITFALL: Ubuntu 24.04의 iproute2 6.1은 커널 6.6에서 bridge 명령이 동작하지 않음
# 소스에서 빌드해야 함
if [ -d "/tmp/iproute2" ]; then
    echo "  iproute2 소스 이미 존재"
else
    echo "  iproute2 소스에서 빌드 중..."
    git clone https://github.com/iproute2/iproute2.git /tmp/iproute2
    cd /tmp/iproute2
    make -j$(nproc)
    sudo make install
    cd ~/WSL2-Linux-Kernel
    echo "  [OK] iproute2 업그레이드 완료"
fi

# 6. 커널 복사
echo ""
echo "[6/6] 커널 복사..."
WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "")
if [ -z "$WIN_USER" ]; then
    WIN_USER=$(ls /mnt/c/Users/ | grep -v -E "^(Public|Default|All)" | head -1)
fi
KERNEL_PATH="/mnt/c/Users/$WIN_USER/wsl-kernel-waydroid"
cp arch/x86/boot/bzImage "$KERNEL_PATH" 2>/dev/null || \
    sudo cp arch/x86/boot/bzImage "$KERNEL_PATH" 2>/dev/null || \
    { cp arch/x86/boot/bzImage ~/wsl-kernel-waydroid; KERNEL_PATH="$HOME/wsl-kernel-waydroid"; }

WIN_KERNEL_PATH="C:\\\\Users\\\\$WIN_USER\\\\wsl-kernel-waydroid"

echo "[OK] 커널 복사: $KERNEL_PATH"

echo ""
echo "============================================"
echo "  커널 빌드 완료!"
echo "============================================"
echo ""
echo "다음 단계:"
echo ""
echo "1. Windows PowerShell (관리자)에서 실행:"
echo ""
echo '   $wslconfig = @"'
echo "   [wsl2]"
echo "   kernel=$WIN_KERNEL_PATH"
echo '   "@'
echo '   Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value $wslconfig'
echo ""
echo "2. PowerShell에서 WSL 종료:"
echo "   wsl --shutdown"
echo ""
echo "3. WSL 다시 열고 install-windows.sh 실행"
echo ""
echo "=== 검증 명령어 ==="
echo "uname -r                    # 커널 버전 확인"
echo "cat /proc/filesystems       # binder 지원 확인"
echo "sudo ip link add br0 type bridge && sudo ip link del br0  # bridge 테스트"
echo ""
