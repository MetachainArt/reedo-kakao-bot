# Windows WSL2 설치 가이드

카카오톡 자동응답 봇을 Windows WSL2 + Waydroid 환경에서 설치하는 상세 가이드입니다.

## 필수 조건

- **Windows 11** (WSL2 지원)
- **RAM 16GB 이상** 권장
- **디스크 공간** 20GB 이상 (커널 빌드 + Waydroid 이미지)
- **카카오톡 계정** (에뮬레이터 로그인 시 폰에서 로그아웃됨!)
- **OpenClaw** 설치 + API 키 설정 완료

## 전체 흐름

```
1. WSL2 설치
2. 커스텀 커널 빌드 (30-40분, 최초 1회)
3. 봇 설치 (install-windows.sh)
4. 카카오톡 설치 (setup-kakao.sh)
5. OpenClaw 설정 (setup-openclaw.sh)
6. 봇 시작 (start-windows.sh)
```

---

## Step 1: WSL2 설치

Windows PowerShell (관리자)에서:

```powershell
wsl --install
```

설치 후 재부팅하고, Ubuntu를 열어 사용자 설정을 완료하세요.

---

## Step 2: 프로젝트 다운로드

WSL 터미널에서:

```bash
cd ~
git clone https://github.com/<username>/reedo-kakao-bot.git
cd reedo-kakao-bot
```

---

## Step 3: 커스텀 커널 빌드 (최초 1회)

Waydroid는 Android Binder IPC, bridge 네트워킹 등 커스텀 커널 설정이 필요합니다.

### 필수 커널 설정 목록

아래 설정이 **전부 `=y` (built-in)**으로 되어야 합니다. `=m` (module)은 안 됩니다!

| 설정 | 용도 |
|------|------|
| `CONFIG_ANDROID` | Android 지원 |
| `CONFIG_ANDROID_BINDER_IPC` | Binder IPC (Waydroid 핵심) |
| `CONFIG_ANDROID_BINDERFS` | Binder 파일시스템 |
| `CONFIG_BRIDGE` | 네트워크 브리지 |
| `CONFIG_VETH` | 가상 이더넷 |
| `CONFIG_NF_NAT` | NAT |
| `CONFIG_NF_TABLES` | nftables |
| `CONFIG_NFT_NAT` | nftables NAT |
| `CONFIG_NFT_MASQ` | nftables masquerade |
| `CONFIG_NF_CONNTRACK` | 연결 추적 |
| `CONFIG_NETFILTER_XTABLES` | xtables |
| `CONFIG_IP_NF_IPTABLES` | iptables |
| `CONFIG_IP_NF_NAT` | iptables NAT |
| `CONFIG_IP_NF_FILTER` | iptables 필터 |
| `CONFIG_BRIDGE_NETFILTER` | 브리지 netfilter |

### 자동 빌드

```bash
bash kernel/build-kernel.sh
```

빌드에 30-40분 소요됩니다.

### 빌드 후 설정

빌드 완료 후 Windows PowerShell에서:

```powershell
# .wslconfig 생성
$wslconfig = @"
[wsl2]
kernel=C:\\Users\\<USERNAME>\\wsl-kernel-waydroid
"@
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value $wslconfig

# WSL 재시작
wsl --shutdown
```

WSL을 다시 열고 확인:

```bash
uname -r                    # 커널 버전
cat /proc/filesystems       # binder 확인
sudo ip link add br0 type bridge && sudo ip link del br0  # bridge 테스트
```

### 빌드 중 알려진 문제

**`cpio` 패키지 없음 -> 빌드 실패**

```bash
sudo apt-get install cpio
```

빌드 스크립트가 자동으로 설치하지만, 수동 빌드 시 잊기 쉽습니다.

**iproute2 버전 불일치**

Ubuntu 24.04의 iproute2 6.1은 커널 6.6과 호환 안 됩니다.
소스에서 빌드해야 합니다:

```bash
git clone https://github.com/iproute2/iproute2.git /tmp/iproute2
cd /tmp/iproute2
make -j$(nproc)
sudo make install
```

커널 빌드 스크립트가 자동으로 처리합니다.

---

## Step 4: 봇 설치

```bash
bash install-windows.sh
```

봇 이름, 말투를 물어봅니다. 원하는 대로 입력하세요.

설치되는 것들:
- 필수 패키지 (build-essential, python3, sqlite3, etc.)
- kakaodecrypt (카카오톡 DB 복호화)
- Waydroid (Android 에뮬레이터)
- ARM 호환 레이어 (libhoudini)
- ADB Keyboard (한글 입력)

---

## Step 5: 카카오톡 설치

```bash
bash setup-kakao.sh
```

Waydroid 안드로이드 화면에서:
1. Play Store 열기
2. Google 계정 로그인
3. "KakaoTalk" 검색 -> 설치
4. 카카오톡 열기 -> 로그인

**주의: 로그인하면 기존 폰에서 카카오톡이 로그아웃됩니다!**

### 한글 전송 테스트

카카오톡 채팅방을 열고:

```bash
# 한글 입력 테스트
sudo waydroid shell -- am broadcast -a ADB_INPUT_TEXT --es msg "테스트 한글 입력"
# 전송 (Shift+Enter)
sudo waydroid shell -- input keycombination 59 66
```

채팅방에 "테스트 한글 입력"이 전송되면 성공!

---

## Step 6: OpenClaw 설정

```bash
bash setup-openclaw.sh
```

OpenClaw이 설치되어 있어야 합니다:

```bash
npm install -g openclaw
openclaw onboard
```

---

## Step 7: 봇 시작!

```bash
bash start-windows.sh
```

끝! 카카오톡에서 봇 이름을 부르면 AI가 자동으로 답장합니다.

---

## 매일 사용법

### 컴퓨터 껐다 켰을 때

```bash
bash ~/reedo-kakao-bot/start-windows.sh
```

이것만 하면 됩니다. 자동으로:
1. binder 마운트
2. 심볼릭 링크 생성
3. nftables 모드 설정
4. Waydroid 시작
5. ADB Keyboard 활성화
6. 데몬 실행

### 봇 종료

```bash
bash ~/reedo-kakao-bot/stop.sh
```

또는 `Ctrl+C`

---

## 주요 pitfall 정리

### Binder 마운트 (매 부팅마다!)

```bash
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs
sudo ln -sf /dev/binderfs/anbox-binder /dev/anbox-binder
sudo ln -sf /dev/binderfs/anbox-hwbinder /dev/anbox-hwbinder
sudo ln -sf /dev/binderfs/anbox-vndbinder /dev/anbox-vndbinder
```

`start-windows.sh`가 자동 처리합니다.

### nftables 모드

```bash
sudo sed -i 's/LXC_USE_NFT="false"/LXC_USE_NFT="true"/' \
    /usr/lib/waydroid/data/scripts/waydroid-net.sh
```

이걸 안 하면 Waydroid 네트워크가 안 됩니다.

### sudo HOME 문제

데몬은 반드시 이렇게 실행:

```bash
sudo HOME=$HOME python3 reedo-daemon.py
```

`sudo`는 HOME을 `/root`로 바꾸므로, `HOME=$HOME`을 명시해야 합니다.

### 클립보드 방식이 안 되는 이유

백그라운드에서 클립보드 접근하면 포커스를 뺏김 -> ADB Keyboard broadcast 방식 사용.

### 파일 권한

sudo로 데몬 실행 시 OpenClaw 파일 권한이 root로 바뀔 수 있음:

```bash
sudo chown -R $USER:$USER ~/.openclaw
```

---

## 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| "binder not found" | 커스텀 커널 미적용 | Step 3 다시 |
| 카카오톡 호환 안 됨 | libhoudini 미설치 | `install-windows.sh` 다시 |
| 한글 전송 안 됨 | ADB Keyboard 미활성 | `setup-kakao.sh` 다시 |
| AI 응답 느림 (20초+) | 모델 문제 | config.json에서 model 변경 |
| 메시지 감지 안 됨 | 카카오톡 미실행 | 채팅방 열어두기 |
| Permission denied | sudo 없이 실행 | `sudo HOME=$HOME python3 ...` |
| OpenClaw 파일 에러 | 권한 문제 | `chown -R $USER ~/.openclaw` |
| bridge 실패 | 커널 설정 =m | 커널 재빌드 (=y로) |
