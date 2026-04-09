# VPS (Linux) 설치 가이드

카카오톡 자동응답 봇을 VPS (Hostinger, AWS, etc.) + ReDroid Docker 환경에서 설치하는 상세 가이드입니다.

## 필수 조건

- **Linux VPS** (Ubuntu 22.04+ 권장)
- **RAM 4GB 이상** 권장
- **binder 지원 커널** (linux-modules-extra 필요)
- **Docker** 설치
- **카카오톡 계정**
- **OpenClaw** 설치 + API 키 설정 완료
- **로컬 PC에 scrcpy** (화면 접근용, 선택)

## 전체 흐름

```
1. 서버 패키지 설치
2. Docker + binder 모듈 설정
3. ReDroid 컨테이너 생성
4. 카카오톡 설치 (split APK 또는 scrcpy)
5. OpenClaw 설정
6. 봇 시작
```

---

## Step 1: 자동 설치

```bash
cd ~
git clone https://github.com/<username>/reedo-kakao-bot.git
cd reedo-kakao-bot
bash install-vps.sh
```

또는 아래 수동 단계를 따르세요.

---

## Step 2: 커널 모듈 설정

ReDroid는 binder_linux 커널 모듈이 필요합니다.

```bash
# linux-modules-extra 설치 (binder_linux 포함)
sudo apt install linux-modules-extra-$(uname -r)

# 모듈 로드
sudo modprobe binder_linux

# 부팅 시 자동 로드
echo "binder_linux" | sudo tee /etc/modules-load.d/binder.conf

# binderfs 마운트
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs
```

확인:
```bash
lsmod | grep binder    # binder_linux 보여야 함
ls /dev/binderfs/       # 파일이 있어야 함
```

---

## Step 3: ReDroid Docker 컨테이너

```bash
# Docker 설치 (없으면)
curl -fsSL https://get.docker.com | sudo sh

# ReDroid 실행
# PITFALL: -v redroid-data:/data 는 Docker volume으로 데이터 영속성 보장
# PITFALL: -v /dev/binderfs:/dev/binderfs 필수 (binder IPC)
sudo docker run -d \
    --name redroid \
    --privileged \
    -v /dev/binderfs:/dev/binderfs \
    -v redroid-data:/data \
    -p 5555:5555 \
    redroid/redroid:13.0.0-latest \
    androidboot.use_memfd=true \
    redroid.gpu.mode=guest
```

시작까지 30-60초 대기 후:

```bash
# ADB 연결
adb connect localhost:5555
adb -s localhost:5555 shell echo ok    # "ok" 출력되면 성공
```

---

## Step 4: 카카오톡 설치

### 방법 1: scrcpy로 화면 접근 (권장)

로컬 PC에서:
```bash
# scrcpy 설치 후
scrcpy --tcpip=<VPS_IP>:5555 --no-audio
```

화면에서 브라우저 열고 카카오톡 APK 다운로드, 설치.

### 방법 2: Split APK로 설치

카카오톡은 Google Play의 split APK 형태입니다.

```bash
# PC에서 카카오톡 APK를 추출하여 VPS로 전송
scp base.apk split_config.arm64_v8a.apk split_config.xxhdpi.apk split_config.ko.apk user@vps:~/

# VPS에서 설치
adb -s localhost:5555 install-multiple \
    base.apk \
    split_config.arm64_v8a.apk \
    split_config.xxhdpi.apk \
    split_config.ko.apk
```

### ADB Keyboard 설치

```bash
# 다운로드
wget "https://github.com/senzhk/ADBKeyBoard/releases/download/v2.4-dev/keyboardservice-debug.apk" \
    -O ~/ADBKeyBoard.apk

# 설치
adb -s localhost:5555 install ~/ADBKeyBoard.apk

# 활성화 (순서 중요!)
adb -s localhost:5555 shell settings put secure enabled_input_methods \
    "com.android.adbkeyboard/.AdbIME:com.android.inputmethod.latin/.LatinIME"
adb -s localhost:5555 shell ime enable com.android.adbkeyboard/.AdbIME
adb -s localhost:5555 shell ime set com.android.adbkeyboard/.AdbIME
```

### 카카오톡 실행

```bash
# PITFALL: am start로는 Permission Denial 발생!
# monkey 명령 사용:
adb -s localhost:5555 shell monkey -p com.kakao.talk 1
```

**주의: 로그인하면 기존 폰에서 카카오톡이 로그아웃됩니다!**

---

## Step 5: kakaodecrypt 설치

```bash
git clone https://github.com/jiru/kakaodecrypt.git ~/kakaodecrypt
pip3 install pycryptodome
```

### User ID 확인

```bash
# DB 복사 (WAL 파일도 반드시!)
sudo docker cp redroid:/data/data/com.kakao.talk/databases/KakaoTalk.db /tmp/reedo_kakao.db
sudo docker cp redroid:/data/data/com.kakao.talk/databases/KakaoTalk.db-wal /tmp/reedo_kakao.db-wal
sudo docker cp redroid:/data/data/com.kakao.talk/databases/KakaoTalk.db-shm /tmp/reedo_kakao.db-shm
sudo chmod 666 /tmp/reedo_kakao.db*

# WAL 체크포인트 (필수!)
sqlite3 /tmp/reedo_kakao.db "PRAGMA wal_checkpoint(TRUNCATE);"

# User ID 추측
python3 ~/kakaodecrypt/guess_user_id.py /tmp/reedo_kakao.db
```

`prob 100%`로 나오는 ID가 내 user_id입니다.

---

## Step 6: OpenClaw 설정

```bash
# OpenClaw 설치 (없으면)
npm install -g openclaw
openclaw onboard

# 에이전트 설정
bash setup-openclaw.sh
```

### OpenClaw 경로 확인 (중요!)

VPS에서는 OpenClaw의 절대 경로가 필요합니다:

```bash
which openclaw
# 예: /home/reedo/.npm-global/bin/openclaw
```

이 경로가 `reedo-daemon-vps.py`의 `OPENCLAW_BIN` 변수와 일치해야 합니다.
또는 환경 변수로 설정:

```bash
export OPENCLAW_BIN=/home/reedo/.npm-global/bin/openclaw
```

---

## Step 7: 봇 시작!

```bash
bash start-vps.sh
```

### 백그라운드 실행

```bash
# tmux 사용 (권장)
tmux new -s kakao-bot
bash start-vps.sh
# Ctrl+B, D 로 분리

# 다시 연결
tmux attach -t kakao-bot
```

또는 nohup:

```bash
nohup bash start-vps.sh > ~/kakao-bot.log 2>&1 &
```

---

## 주요 pitfall 정리

### WAL 파일 복사 필수!

DB만 복사하면 최근 메시지가 누락됩니다:

```bash
# 반드시 3개 파일 모두 복사
sudo docker cp redroid:/data/data/com.kakao.talk/databases/KakaoTalk.db /tmp/
sudo docker cp redroid:/data/data/com.kakao.talk/databases/KakaoTalk.db-wal /tmp/
sudo docker cp redroid:/data/data/com.kakao.talk/databases/KakaoTalk.db-shm /tmp/
```

### WAL 체크포인트 필수!

복호화 전에 WAL을 메인 DB에 병합해야 합니다:

```bash
sqlite3 /tmp/reedo_kakao.db "PRAGMA wal_checkpoint(TRUNCATE);"
```

### shlex.quote() 필수!

메시지 텍스트에 따옴표, 특수문자가 있으면 shell injection 위험:

```python
import shlex
safe_msg = shlex.quote(message)
subprocess.run(["adb", "shell", f"am broadcast -a ADB_INPUT_TEXT --es msg {safe_msg}"])
```

### am start Permission Denial

카카오톡을 `am start`로 실행하면 Permission Denial 발생:

```bash
# 이것은 안 됨:
adb shell am start -n com.kakao.talk/.activity.main.MainActivity

# 대신 monkey 사용:
adb shell monkey -p com.kakao.talk 1
```

### 탭 좌표는 해상도에 따라 다름

- 720x1280: 입력 필드 = tap 360 1150
- 해상도가 다르면 좌표 조정 필요

### Docker volume으로 데이터 보존

`-v redroid-data:/data` 없이 실행하면 컨테이너 재시작 시 카카오톡 데이터 날아감.

### sudo 권한 설정

데몬이 docker cp / chmod을 실행하므로:

```bash
# /etc/sudoers.d/reedo-kakao-bot
username ALL=(ALL) NOPASSWD: /usr/bin/docker cp *
username ALL=(ALL) NOPASSWD: /bin/chmod *
```

---

## 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| binder 모듈 로드 실패 | 커널 미지원 | `linux-modules-extra-$(uname -r)` 설치 |
| ReDroid 시작 안 됨 | binderfs 미마운트 | `sudo mount -t binder binder /dev/binderfs` |
| ADB 연결 실패 | ReDroid 미시작 | 30초 대기 후 재시도 |
| 카카오톡 설치 실패 | split APK 누락 | 모든 split APK 파일 포함 |
| 메시지 누락 | WAL 미복사 | WAL+SHM 파일도 docker cp |
| 복호화 실패 | 체크포인트 안 함 | `PRAGMA wal_checkpoint(TRUNCATE)` |
| 전송 실패 | ADB Keyboard 미활성 | `ime set` 재실행 |
| OpenClaw 못 찾음 | 경로 문제 | `which openclaw` 확인 후 OPENCLAW_BIN 설정 |
| Permission Denial | am start 사용 | monkey 명령 사용 |
