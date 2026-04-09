# reedo-kakao-bot

## 카카오톡 AI 자동응답 봇

카카오톡에서 누군가 메시지를 보내면, AI가 자동으로 읽고 답장해주는 봇입니다.

> **"뽀리야"** 라고 부르면 AI 비서가 자동으로 답장합니다.

---

## 이게 뭔가요?

평소에 카카오톡으로 메시지가 오면 직접 읽고 답장해야 하잖아요?
이 봇은 **AI가 대신** 해줍니다.

- 누군가 카톡으로 "뽀리야 오늘 뭐해?" → AI가 자동으로 "안녕하세요~! 뭐 도와드릴까요? 😊"
- 그룹방에서 "뽀리야 회의 일정 알려줘" → AI가 맥락 파악하고 답장
- 개인 채팅은 자동 답장, 그룹방은 이름 부를 때만 답장

### 핵심 특징

- **화면 안 뺏김** — DB 복호화 방식이라 백그라운드에서 조용히 동작
- **한글 완벽 지원** — ADB Keyboard로 한글 입력+전송
- **AI 답장** — OpenClaw (GPT-5.4 등) 연동으로 똑똑한 답변
- **대화 맥락 이해** — 최근 10개 메시지를 보고 상황에 맞는 답장
- **커스터마이징** — 봇 이름, 말투, AI 모델 자유롭게 변경

---

## 어떻게 동작하나요?

```
1. Android 에뮬레이터에서 카카오톡 실행 (Waydroid 또는 ReDroid)
2. 카카오톡 DB를 복호화해서 새 메시지 감지 (백그라운드, 화면 안 뺏김!)
3. OpenClaw AI가 답장 생성
4. ADB Keyboard로 한글 입력 + Shift+Enter로 자동 전송
```

### 왜 이 방식인가요?

카카오톡은 외부에서 메시지를 읽을 수 있는 공식 API가 없습니다.

| 시도한 방법 | 결과 |
|------------|------|
| Windows UI 자동화 (Ctrl+A, Ctrl+C) | 화면 포커스를 뺏어서 사용 불가 |
| Windows 카카오톡 DB (.edb) | 암호화 키가 비공개라 복호화 불가 |
| Windows 알림 캡처 | 카카오톡이 Windows 알림 시스템 미사용 |
| **Android DB 복호화** | **성공! 키가 공개되어 있음** |

그래서 Android 에뮬레이터에서 카카오톡을 돌리고, DB를 복호화해서 메시지를 읽는 방식을 사용합니다.

---

## 두 가지 환경 지원

| 환경 | 에뮬레이터 | 장점 | 단점 |
|------|-----------|------|------|
| **Windows WSL2** | Waydroid | 무료, 내 PC에서 바로 | PC 켜놔야 함, 커널 빌드 필요 |
| **VPS (Linux)** | ReDroid (Docker) | 24시간 자동, 서버에서 동작 | VPS 비용, 초기 설정 복잡 |

---

## 필수 조건

### 공통
- **카카오톡 계정** (에뮬레이터에 로그인하면 **폰에서 로그아웃**됩니다!)
- **OpenClaw** 설치 + API 키 설정 완료 (`npm install -g openclaw && openclaw onboard`)

### Windows WSL2
- Windows 11 (WSL2 지원)
- RAM 16GB 이상
- 디스크 20GB+ 여유

### VPS (Linux)
- Ubuntu 22.04/24.04
- RAM 4GB 이상
- Docker 설치 가능
- `binder_linux` 커널 모듈 로드 가능 (`sudo modprobe binder_linux`)

### VPS 호환성

| VPS | 호환 | 이유 |
|-----|------|------|
| Hostinger VPS | **O** | `linux-modules-extra`로 binder 로드 가능 |
| Oracle Cloud ARM | **X** | ARM + KVM 미지원 |
| Hetzner | **O** | KVM 기본 지원 |
| 저가 OpenVZ/LXC VPS | **X** | 커널 모듈 로드 불가 |

---

## 빠른 시작

### Windows WSL2

```bash
# WSL 터미널에서
git clone https://github.com/MetachainArt/reedo-kakao-bot.git ~/reedo-kakao-bot
cd ~/reedo-kakao-bot

# 1. 커널 빌드 (최초 1회, 30-40분 소요)
bash kernel/build-kernel.sh
# → 빌드 완료 후 화면에 나오는 안내대로 PowerShell에서 .wslconfig 설정
# → wsl --shutdown 후 WSL 다시 열기

# 2. 설치 (패키지 + Waydroid + ADB Keyboard)
bash install-windows.sh

# 3. 카카오톡 설치 + 로그인 (Waydroid 안드로이드 화면에서)
bash setup-kakao.sh

# 4. OpenClaw AI 에이전트 설정
bash setup-openclaw.sh

# 5. 봇 시작!
bash start-windows.sh
```

### VPS (Linux)

```bash
# VPS SSH 접속 후
git clone https://github.com/MetachainArt/reedo-kakao-bot.git ~/reedo-kakao-bot
cd ~/reedo-kakao-bot

# 1. 설치 (Docker + ReDroid + 의존성)
bash install-vps.sh

# 2. 카카오톡 설치 (scrcpy로 화면 보면서)
#    로컬 PC에서: scrcpy --tcpip=<VPS_IP>:5555 --no-audio
bash setup-kakao.sh

# 3. OpenClaw AI 에이전트 설정
bash setup-openclaw.sh

# 4. 봇 시작!
bash start-vps.sh
```

---

## 상세 설치 가이드

처음 설치하는 분은 반드시 상세 가이드를 따라해주세요:

- **[Windows WSL2 설치 가이드](docs/INSTALL-WINDOWS.md)** — 커널 빌드부터 실행까지 전체 과정
- **[VPS (Linux) 설치 가이드](docs/INSTALL-VPS.md)** — ReDroid Docker 기반 서버 설치

---

## 사용법

### 봇 시작

```bash
# Windows
bash ~/reedo-kakao-bot/start-windows.sh

# VPS
bash ~/reedo-kakao-bot/start-vps.sh
```

시작하면 이런 화면이 나옵니다:

```
=== 뽀리 KakaoTalk Bot ===
Model: openai-codex/gpt-5.4
Interval: 5s | Trigger: 뽀리

Discovering user ID...
User ID: 409661282
Last seen: 303
Listening...

[10:50:11] 박종선 > 박종선: 뽀리야
[10:50:33] 뽀리 -> 박종선: 네~! 뭐 도와드릴까요? 😊
```

### 봇 종료

```bash
bash ~/reedo-kakao-bot/stop.sh
```

또는 터미널에서 `Ctrl+C`

### 컴퓨터 껐다 켰을 때

시작 스크립트만 다시 실행하면 됩니다:

```bash
# Windows
bash ~/reedo-kakao-bot/start-windows.sh

# VPS
bash ~/reedo-kakao-bot/start-vps.sh
```

binder 마운트, 에뮬레이터 시작, ADB Keyboard 활성화, 데몬 실행까지 전부 자동.

---

## 봇 커스터마이징

### config.json 수정

`config.json`을 수정하면 봇 이름, 말투, 모델 등을 변경할 수 있습니다.

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

### 설정 항목 설명

| 항목 | 설명 | 기본값 | 예시 |
|------|------|--------|------|
| `bot_name` | 봇 이름 | "뽀리" | "비서봇", "AI 도우미" |
| `style` | AI 말투/성격 | "존댓말로 친근하고 귀엽게" | "전문적이고 간결하게", "냥 말투로 귀엽게" |
| `model` | AI 모델 | "openai-codex/gpt-5.4" | "openai-codex/gpt-5.3-spark" (더 빠름) |
| `interval` | 메시지 확인 주기 (초) | 5 | 3 (더 빠르게), 10 (서버 부하 줄임) |
| `reply_all_dm` | 개인 채팅 전부 자동 답장 | true | false (이름 불러야만 답장) |
| `group_trigger` | 그룹방에서 이 단어 포함 시 답장 | "뽀리" | "봇아", "AI야" |
| `max_reply_length` | 최대 답장 길이 (자) | 1000 | 500 (짧게), 2000 (길게) |
| `openclaw_agent_id` | OpenClaw 에이전트 ID | "kakao" | 변경 불필요 |
| `quiet_hours_start` | 조용한 시간 시작 (시) | 23 | 0 (비활성화) |
| `quiet_hours_end` | 조용한 시간 끝 (시) | 8 | 0 (비활성화) |

**변경 후 봇을 재시작하면 즉시 반영됩니다.**

### AI 성격 변경 (SOUL.md)

더 세밀한 성격 조정은 `workspace/SOUL.md`를 수정하세요:

```markdown
# SOUL.md - 뽀리 (카카오톡 AI 비서)

나는 **뽀리**! 카카오톡 AI 비서예요!

## 말투
- 존댓말 사용
- 이모티콘 많이 쓰기!
- 짧고 간결하게

## 예시
- "안녕!" → "안녕하세요~! 😊 반가워요!"
- "뽀리야" → "네~! 뭐 도와드릴까요? 😺"
```

수정 후 OpenClaw 세션 리셋:

```bash
rm -rf ~/.openclaw/agents/kakao/sessions/*
```

---

## 프로젝트 구조

```
reedo-kakao-bot/
├── README.md                    # 이 파일
├── config.json                  # 봇 설정 (이름, 말투, 모델 등)
│
├── reedo-daemon.py              # 메인 데몬 (Windows/Waydroid 용)
├── reedo-daemon-vps.py          # 메인 데몬 (VPS/ReDroid 용)
│
├── install-windows.sh           # 자동 설치 (Windows WSL2)
├── install-vps.sh               # 자동 설치 (VPS/Linux)
├── start-windows.sh             # 시작 스크립트 (Windows)
├── start-vps.sh                 # 시작 스크립트 (VPS)
├── stop.sh                      # 종료 스크립트
│
├── setup-kakao.sh               # 카카오톡 설치 헬퍼
├── setup-openclaw.sh            # OpenClaw 에이전트 설정
│
├── kernel/
│   └── build-kernel.sh          # WSL2 커스텀 커널 빌드
│
├── workspace/                   # OpenClaw workspace 템플릿
│   ├── SOUL.md                  # AI 성격/규칙
│   ├── IDENTITY.md              # AI 정체성
│   ├── HEARTBEAT.md             # 하트비트 설정
│   ├── TOOLS.md                 # 도구 설명
│   └── USER.md                  # 사용자 정보
│
├── docs/
│   ├── INSTALL-WINDOWS.md       # Windows 상세 설치 가이드
│   └── INSTALL-VPS.md           # VPS 상세 설치 가이드
│
├── install.sh                   # (레거시, 자동 감지 → 리다이렉트)
└── start.sh                     # (레거시, 자동 감지 → 리다이렉트)
```

---

## 기술 구조

### Windows WSL2

```
WSL2 (Ubuntu) + 커스텀 커널 (binder + bridge + netfilter)
├── Waydroid (Android 에뮬레이터)
│   ├── KakaoTalk (안드로이드 앱)
│   └── ADB Keyboard (한글 입력)
├── kakaodecrypt (DB 복호화)
├── OpenClaw (AI 에이전트)
└── reedo-daemon.py (5초마다: DB 복사 → 복호화 → 새 메시지 감지 → AI 답장 → 전송)
```

### VPS (Linux)

```
Linux VPS (Ubuntu)
├── Docker
│   └── ReDroid (Android in Docker, KVM 불필요!)
│       ├── KakaoTalk
│       └── ADB Keyboard
├── ADB (localhost:5555)
├── kakaodecrypt (DB 복호화)
├── OpenClaw (AI 에이전트)
└── reedo-daemon-vps.py (5초마다: docker cp → WAL 병합 → 복호화 → 감지 → AI → 전송)
```

---

## 핵심 컴포넌트

### kakaodecrypt

카카오톡 Android 앱은 로컬 SQLite DB에 메시지를 암호화하여 저장합니다.
[kakaodecrypt](https://github.com/jiru/kakaodecrypt)는 이 DB를 복호화해서 메시지를 읽을 수 있게 해줍니다.

- `guess_user_id.py` — 카카오톡 계정의 user_id를 자동 탐지
- `kakaodecrypt.py` — DB 복호화 (`chat_logs` → `chat_logs_dec` 테이블 생성)

### ADB Keyboard

Android의 `input text` 명령은 **한글을 지원하지 않습니다**.
[ADB Keyboard](https://github.com/senzhk/ADBKeyBoard)는 broadcast intent를 통해 유니코드 텍스트를 입력합니다.

```bash
# 한글 입력
am broadcast -a ADB_INPUT_TEXT --es msg "안녕하세요"
# 전송 (Shift + Enter)
input keycombination 59 66
```

### OpenClaw

AI 에이전트 프레임워크. `SOUL.md`에 정의된 성격대로 카카오톡 메시지에 답장을 생성합니다.

```bash
openclaw agent --agent kakao -m "카카오톡에서 메시지: '안녕' - 답장해줘"
# → "안녕하세요~! 뭐 도와드릴까요? 😊"
```

---

## 알려진 문제 및 해결법 (Pitfall 총정리)

이 프로젝트를 만들면서 겪은 **모든 삽질**을 정리했습니다.

### 공통

| 문제 | 원인 | 해결 |
|------|------|------|
| 화면이 깜빡거림 | 클립보드(Ctrl+A+C) 방식 사용 | DB 복호화 방식으로 변경 (이 프로젝트) |
| 한글 전송 안 됨 | `input text`가 한글 미지원 | ADB Keyboard 설치 + broadcast 방식 |
| AI 답장이 엉뚱함 | 이전 세션 맥락이 남아있음 | `rm -rf ~/.openclaw/agents/kakao/sessions/*` |
| 조용한 시간에 답장 | quiet_hours 미설정 | config.json에서 설정 |
| 같은 메시지 반복 답장 | last_id 초기화 안 됨 | state 파일 삭제 후 재시작 |

### Windows WSL2 전용

| 문제 | 원인 | 해결 |
|------|------|------|
| `Module binder_linux not found` | WSL2 기본 커널에 binder 없음 | 커스텀 커널 빌드 (`build-kernel.sh`) |
| `Error: Unknown device type` (bridge) | CONFIG_BRIDGE=m (모듈) | **반드시 =y (built-in)**으로 커널 재빌드 |
| 커널 빌드 실패 (`cpio not found`) | cpio 패키지 누락 | `sudo apt install cpio` |
| `Error: Unknown device type` (iproute2) | iproute2 6.1 + 커널 6.6 비호환 | iproute2 소스에서 빌드 |
| binder 마운트 안 됨 | 매 부팅마다 초기화 | `start-windows.sh`가 자동 처리 |
| `anbox-binder not found` | 심볼릭 링크 없음 | `start-windows.sh`가 자동 처리 |
| Waydroid 네트워크 안 됨 | iptables 모듈 없음 | nftables 모드로 전환 (`LXC_USE_NFT="true"`) |
| 카카오톡 Play Store 호환 안 됨 | ARM 앱인데 x86 에뮬레이터 | libhoudini (ARM 변환 레이어) 설치 |
| `Permission denied` (DB 복사) | Waydroid DB가 root 소유 | `sudo cp` 필수 |
| OpenClaw 파일 권한 꼬임 | daemon을 sudo로 실행 | `sudo HOME=$HOME python3 ...` + chown 복구 |
| HOME이 /root로 바뀜 | sudo가 환경변수 리셋 | `sudo HOME=/home/$USER python3 ...` |

### VPS 전용

| 문제 | 원인 | 해결 |
|------|------|------|
| 최근 메시지가 안 보임 | WAL 파일 미복사 | DB + WAL + SHM 전부 `docker cp` |
| 복호화 후 메시지 누락 | WAL 체크포인트 안 함 | `sqlite3 DB "PRAGMA wal_checkpoint(TRUNCATE)"` |
| 메시지 첫 단어만 전송 | subprocess에서 공백 처리 | `shlex.quote()` 사용 |
| `Permission Denial` (am start) | 카카오톡 Activity 비공개 | `monkey -p com.kakao.talk 1` 사용 |
| `openclaw: command not found` | sudo 환경에서 PATH 없음 | 절대 경로 사용 (예: `/home/user/.npm-global/bin/openclaw`) |
| 입력창에 텍스트 안 들어감 | tap 좌표가 안 맞음 | 해상도별 조정 (720x1280: tap 360 1150) |
| 컨테이너 재시작 시 데이터 손실 | Docker volume 미설정 | `-v redroid-data:/data` 옵션 |
| `docker cp` 권한 없음 | sudo 필요 | `/etc/sudoers.d/`에 NOPASSWD 설정 |
| `binder_linux` 모듈 없음 | VPS 커널에 포함 안 됨 | `sudo apt install linux-modules-extra-$(uname -r)` |
| scrcpy 오디오 에러 | ReDroid 오디오 코덱 없음 | `scrcpy --no-audio` |

---

## 문제 해결 빠른 참조

```bash
# === 커널/binder 확인 ===
uname -r                            # 커널 버전
cat /proc/filesystems | grep binder  # binder 지원 확인
lsmod | grep binder                  # binder 모듈 (VPS)

# === Waydroid 확인 (Windows) ===
sudo waydroid container start
waydroid session start
waydroid show-full-ui

# === ReDroid 확인 (VPS) ===
sudo docker ps | grep redroid
adb connect localhost:5555
adb -s localhost:5555 shell echo "connected"

# === ADB Keyboard 확인 ===
# Windows:
sudo waydroid shell -- ime list -s
# VPS:
adb -s localhost:5555 shell ime list -s
# → "com.android.adbkeyboard/.AdbIME" 가 보여야 함

# === 카카오톡 DB 확인 ===
# Windows:
sudo ls ~/.local/share/waydroid/data/data/com.kakao.talk/databases/
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

# === OpenClaw 테스트 ===
openclaw agent --agent kakao -m "안녕"

# === 세션 리셋 (AI가 이상하게 답할 때) ===
rm -rf ~/.openclaw/agents/kakao/sessions/*

# === 파일 권한 복구 ===
sudo chown -R $(whoami):$(whoami) ~/.openclaw/
```

---

## FAQ

### Q: 폰 카카오톡은 어떻게 되나요?
**A: 에뮬레이터에 로그인하면 폰에서 로그아웃됩니다.** 카카오톡은 한 기기에서만 로그인 가능합니다.

### Q: 봇이 답장하는 데 얼마나 걸리나요?
**A: 약 15-20초.** DB 복사(2초) + 복호화(2초) + AI 생성(10-15초) + 전송(1초).

### Q: 그룹방에서 모든 메시지에 답장하나요?
**A: 아니요.** `config.json`의 `group_trigger`에 설정한 이름이 포함된 메시지에만 답장합니다. 개인 채팅은 `reply_all_dm: true`이면 전부 답장.

### Q: VPS에서 24시간 돌릴 수 있나요?
**A: 네.** VPS에 ReDroid + daemon을 설치하면 PC 꺼도 24시간 동작합니다.

### Q: 이미지도 보낼 수 있나요?
**A: 현재는 텍스트만 지원합니다.**

### Q: 비용이 드나요?
**A: OpenClaw의 AI 모델 사용료만 발생합니다.** 봇 자체는 무료. VPS를 쓰면 VPS 비용 추가.

### Q: 카카오톡 계정이 차단될 수 있나요?
**A: 비공식 방법이므로 가능성이 있습니다.** 과도한 사용을 피하고, interval을 5초 이상으로 설정하세요.

---

## 참고 프로젝트

- [kakaodecrypt](https://github.com/jiru/kakaodecrypt) — 카카오톡 Android DB 복호화
- [ADB Keyboard](https://github.com/senzhk/ADBKeyBoard) — ADB를 통한 유니코드 텍스트 입력
- [OpenClaw](https://github.com/openclaw/openclaw) — AI 에이전트 프레임워크
- [Waydroid](https://waydroid.org/) — Linux에서 Android 실행
- [ReDroid](https://github.com/remote-android/redroid-doc) — Docker에서 Android 실행 (KVM 불필요)
- [openclaw-kakao](https://github.com/jkf87/openclaw-kakao) — macOS 카카오톡 자동화 (이 프로젝트의 원본 영감)

---

## 라이선스

MIT
