# reedo-kakao-bot

카카오톡에서 메시지가 오면 AI가 자동으로 답장해주는 봇입니다.

## 어떻게 동작하나요?

```
카카오톡 메시지 수신
  -> Android 에뮬레이터에서 카카오톡 실행 (Waydroid 또는 ReDroid)
    -> 카카오톡 DB를 복호화해서 새 메시지 감지 (백그라운드, 화면 안 뺏김!)
      -> OpenClaw AI가 답장 생성
        -> ADB Keyboard로 한글 입력 + Shift+Enter로 자동 전송
```

**두 가지 환경을 지원합니다:**

| 환경 | 에뮬레이터 | 용도 |
|------|-----------|------|
| **Windows WSL2** | Waydroid | 개인 PC에서 실행 |
| **VPS (Linux)** | ReDroid (Docker) | 서버에서 24시간 실행 |

## 빠른 시작

### Windows WSL2

```bash
git clone https://github.com/<username>/reedo-kakao-bot.git ~/reedo-kakao-bot
cd ~/reedo-kakao-bot

# 1. 커널 빌드 (최초 1회, 30-40분)
bash kernel/build-kernel.sh
# -> PowerShell에서 .wslconfig 설정 후 wsl --shutdown

# 2. 설치
bash install-windows.sh

# 3. 카카오톡 설치 (Waydroid 화면에서)
bash setup-kakao.sh

# 4. OpenClaw 설정
bash setup-openclaw.sh

# 5. 시작!
bash start-windows.sh
```

### VPS (Linux)

```bash
git clone https://github.com/<username>/reedo-kakao-bot.git ~/reedo-kakao-bot
cd ~/reedo-kakao-bot

# 1. 설치 (Docker + ReDroid + 의존성)
bash install-vps.sh

# 2. 카카오톡 설치 (scrcpy 또는 split APK)
bash setup-kakao.sh

# 3. OpenClaw 설정
bash setup-openclaw.sh

# 4. 시작!
bash start-vps.sh
```

## 상세 설치 가이드

- [Windows WSL2 설치 가이드](docs/INSTALL-WINDOWS.md) - 커널 빌드부터 실행까지 전체 과정
- [VPS (Linux) 설치 가이드](docs/INSTALL-VPS.md) - ReDroid Docker 기반 서버 설치

## 사용법

### 봇 시작

```bash
# Windows
bash ~/reedo-kakao-bot/start-windows.sh

# VPS
bash ~/reedo-kakao-bot/start-vps.sh
```

### 봇 종료

```bash
bash ~/reedo-kakao-bot/stop.sh
```

또는 `Ctrl+C`

### 컴퓨터 껐다 켰을 때

시작 스크립트만 다시 실행하면 됩니다.
binder 마운트, 에뮬레이터 시작, ADB Keyboard 활성화, 데몬 실행까지 전부 자동.

## 프로젝트 구조

```
reedo-kakao-bot/
├── README.md                   # 이 파일
├── config.json                 # 봇 설정 (이름, 말투, 모델 등)
├── reedo-daemon.py             # 메인 데몬 (Windows/Waydroid)
├── reedo-daemon-vps.py         # 메인 데몬 (VPS/ReDroid)
├── install-windows.sh          # 자동 설치 (Windows WSL2)
├── install-vps.sh              # 자동 설치 (VPS/Linux)
├── start-windows.sh            # 시작 스크립트 (Windows)
├── start-vps.sh                # 시작 스크립트 (VPS)
├── stop.sh                     # 종료 스크립트
├── setup-kakao.sh              # 카카오톡 설치 헬퍼
├── setup-openclaw.sh           # OpenClaw 에이전트 설정
├── kernel/
│   └── build-kernel.sh         # WSL2 커스텀 커널 빌드
├── workspace/                  # OpenClaw workspace 템플릿
│   ├── SOUL.md                 # AI 성격/규칙
│   ├── IDENTITY.md             # AI 정체성
│   ├── HEARTBEAT.md            # 하트비트 (daemon이 처리)
│   ├── TOOLS.md                # 도구 설명
│   └── USER.md                 # 사용자 정보
├── docs/
│   ├── INSTALL-WINDOWS.md      # Windows 상세 설치 가이드
│   └── INSTALL-VPS.md          # VPS 상세 설치 가이드
└── install.sh                  # (레거시, install-windows.sh 사용)
```

## config.json 설정

```json
{
  "bot_name": "뽀리",
  "style": "존댓말로 친근하고 귀엽게. 이모티콘 적당히.",
  "model": "openai-codex/gpt-5.4",
  "interval": 5,
  "reply_all_dm": true,
  "group_trigger": "뽀리",
  "max_reply_length": 1000,
  "openclaw_agent_id": "kakao",
  "quiet_hours_start": 23,
  "quiet_hours_end": 8
}
```

| 항목 | 설명 | 기본값 |
|------|------|--------|
| `bot_name` | 봇 이름 | "뽀리" |
| `style` | AI 말투/성격 프롬프트 | "존댓말로 친근하고 귀엽게" |
| `model` | AI 모델 (OpenClaw) | "openai-codex/gpt-5.4" |
| `interval` | 메시지 확인 주기 (초) | 5 |
| `reply_all_dm` | 개인 채팅 전부 자동 답장 | true |
| `group_trigger` | 그룹방에서 이 단어 포함 시 답장 | "뽀리" |
| `max_reply_length` | 최대 답장 길이 (자) | 1000 |
| `openclaw_agent_id` | OpenClaw 에이전트 ID | "kakao" |
| `quiet_hours_start` | 조용한 시간 시작 (시) | 23 |
| `quiet_hours_end` | 조용한 시간 끝 (시) | 8 |

변경 후 봇 재시작하면 즉시 반영됩니다.

## 기술 구조

### Windows WSL2

```
WSL2 (Ubuntu) + 커스텀 커널 (binder + bridge + netfilter)
├── Waydroid (Android 에뮬레이터)
│   ├── KakaoTalk (안드로이드 앱)
│   └── ADB Keyboard (한글 입력)
├── kakaodecrypt (DB 복호화)
├── OpenClaw (AI 에이전트)
└── reedo-daemon.py (메시지 감시 + 응답 + 전송)
```

### VPS (Linux)

```
Linux VPS (Ubuntu)
├── Docker
│   └── ReDroid (Android in Docker)
│       ├── KakaoTalk
│       └── ADB Keyboard
├── ADB (localhost:5555)
├── kakaodecrypt (DB 복호화)
├── OpenClaw (AI 에이전트)
└── reedo-daemon-vps.py (메시지 감시 + 응답 + 전송)
```

## 핵심 컴포넌트 설명

### kakaodecrypt

카카오톡은 로컬 SQLite DB에 메시지를 암호화하여 저장합니다.
[kakaodecrypt](https://github.com/jiru/kakaodecrypt)로 복호화하여 메시지를 읽습니다.

- `guess_user_id.py`: 내 user_id를 자동 탐지
- `kakaodecrypt.py`: DB 복호화 (`chat_logs` -> `chat_logs_dec`)

### ADB Keyboard

일반 `input text` 명령은 한글을 지원하지 않습니다.
[ADB Keyboard](https://github.com/senzhk/ADBKeyBoard)는 broadcast를 통해 한글 텍스트를 입력합니다.

```bash
# 한글 입력
am broadcast -a ADB_INPUT_TEXT --es msg "안녕하세요"
# 전송 (Shift + Enter)
input keycombination 59 66
```

### OpenClaw

AI 에이전트 프레임워크. 카카오톡 메시지를 받아서 AI 답장을 생성합니다.

```bash
openclaw agent --agent kakao -m "메시지 프롬프트"
```

## 알려진 pitfall 총정리

### 공통

| pitfall | 설명 | 해결 |
|---------|------|------|
| 클립보드 방식 불가 | 백그라운드에서 포커스를 뺏음 | DB 복호화 방식 사용 |
| ADB Keyboard 비활성 | 한글 전송 안 됨 | `ime set` 재실행 |
| 조용한 시간 | 밤에 자동응답 방지 | config.json의 quiet_hours 설정 |

### Windows WSL2 전용

| pitfall | 설명 | 해결 |
|---------|------|------|
| 커널 설정 =m | bridge, netfilter가 모듈이면 안 됨 | 전부 =y로 커널 재빌드 |
| cpio 패키지 누락 | 커널 빌드 실패 | `apt install cpio` |
| iproute2 버전 | 6.1은 커널 6.6과 비호환 | 소스에서 빌드 |
| binder 매 부팅 | WSL2는 부팅마다 초기화 | start-windows.sh가 자동 처리 |
| 심볼릭 링크 | anbox-binder 등 매번 생성 | start-windows.sh가 자동 처리 |
| nftables 모드 | LXC_USE_NFT="false" -> 네트워크 안 됨 | waydroid-net.sh에서 "true"로 변경 |
| sudo HOME | sudo가 HOME을 /root로 바꿈 | `sudo HOME=$HOME python3 ...` |
| 파일 권한 | sudo로 실행 시 openclaw 권한 변경 | `chown -R $USER ~/.openclaw` |
| DB 복사 | Waydroid DB는 root 소유 | `sudo cp` 필수 |

### VPS 전용

| pitfall | 설명 | 해결 |
|---------|------|------|
| WAL 파일 | DB만 복사하면 최근 메시지 누락 | WAL+SHM도 docker cp |
| WAL 체크포인트 | 복호화 전 병합 필수 | `PRAGMA wal_checkpoint(TRUNCATE)` |
| shlex.quote() | 특수문자로 shell injection | subprocess에서 shlex.quote 사용 |
| am start | Permission Denial | monkey 명령 사용 |
| OpenClaw 경로 | PATH에 없음 | 절대 경로 사용 |
| 탭 좌표 | 해상도마다 다름 | 720x1280: tap 360 1150 |
| Docker volume | 컨테이너 재시작 시 데이터 손실 | `-v redroid-data:/data` |
| sudo 권한 | docker cp에 sudo 필요 | sudoers.d 설정 |
| binder 모듈 | VPS 커널에 없을 수 있음 | linux-modules-extra 설치 |

## 문제 해결 빠른 참조

```bash
# === 커널/binder 확인 ===
uname -r                           # 커널 버전
cat /proc/filesystems | grep binder # binder 지원
lsmod | grep binder                # binder 모듈 (VPS)

# === Waydroid 확인 (Windows) ===
sudo waydroid container start
waydroid session start
waydroid show-full-ui

# === ReDroid 확인 (VPS) ===
sudo docker ps | grep redroid
adb connect localhost:5555
adb -s localhost:5555 shell echo ok

# === ADB Keyboard 확인 ===
# Windows:
sudo waydroid shell -- ime list -s
# VPS:
adb -s localhost:5555 shell ime list -s
# "com.android.adbkeyboard/.AdbIME" 가 보여야 함

# === 카카오톡 DB 확인 ===
# Windows:
sudo ls -la ~/.local/share/waydroid/data/data/com.kakao.talk/databases/
# VPS:
sudo docker exec redroid ls /data/data/com.kakao.talk/databases/

# === User ID 확인 ===
python3 ~/kakaodecrypt/guess_user_id.py /tmp/reedo_kakao.db

# === 수동 메시지 전송 테스트 ===
# Windows:
sudo waydroid shell -- am broadcast -a ADB_INPUT_TEXT --es msg "테스트"
sudo waydroid shell -- input keycombination 59 66
# VPS:
adb -s localhost:5555 shell "am broadcast -a ADB_INPUT_TEXT --es msg '테스트'"
adb -s localhost:5555 shell input keycombination 59 66

# === OpenClaw 확인 ===
which openclaw
openclaw agents list
openclaw agent --agent kakao -m "테스트"

# === 로그 확인 ===
tail -f ~/kakao-bot.log   # nohup으로 실행한 경우

# === 세션 초기화 ===
rm -rf ~/.openclaw/agents/kakao/sessions/*

# === 파일 권한 복구 ===
sudo chown -R $USER:$USER ~/.openclaw
```

## 라이선스

MIT
