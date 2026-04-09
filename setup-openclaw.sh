#!/bin/bash
echo "============================================"
echo "  OpenClaw 카카오톡 에이전트 설정"
echo "============================================"
echo ""

INSTALL_DIR="$HOME/reedo-kakao-bot"
CONFIG="$INSTALL_DIR/config.json"

# Read config values
BOT_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG'))['bot_name'])" 2>/dev/null || echo "봇")
STYLE=$(python3 -c "import json; print(json.load(open('$CONFIG'))['style'])" 2>/dev/null || echo "친근하게")
MODEL=$(python3 -c "import json; print(json.load(open('$CONFIG'))['model'])" 2>/dev/null || echo "openai-codex/gpt-5.4")

# ===================================
# 1. OpenClaw 설치 확인
# ===================================
OPENCLAW_BIN=$(which openclaw 2>/dev/null || echo "")
if [ -z "$OPENCLAW_BIN" ]; then
    # Try common npm global paths
    for p in "$HOME/.npm-global/bin/openclaw" "/usr/local/bin/openclaw" "$HOME/.local/bin/openclaw"; do
        if [ -x "$p" ]; then
            OPENCLAW_BIN="$p"
            break
        fi
    done
fi

if [ -z "$OPENCLAW_BIN" ]; then
    echo "[!] OpenClaw이 설치되어 있지 않습니다."
    echo "    먼저 설치하세요:"
    echo "    npm install -g openclaw"
    echo "    openclaw onboard"
    exit 1
fi
echo "[OK] OpenClaw: $OPENCLAW_BIN"
echo "     Version: $($OPENCLAW_BIN --version 2>&1 || echo 'unknown')"

# ===================================
# 2. 에이전트 생성
# ===================================
WORKSPACE="$HOME/.openclaw/workspace-kakao"
if [ -d "$WORKSPACE" ]; then
    echo "[OK] kakao 에이전트 이미 존재"
else
    echo "kakao 에이전트 생성 중..."
    mkdir -p "$WORKSPACE/memory"
    # PITFALL: --non-interactive 필수 (스크립트 자동 실행 시)
    $OPENCLAW_BIN agents add kakao \
        --workspace "$WORKSPACE" \
        --model "$MODEL" \
        --non-interactive 2>/dev/null || true
    echo "[OK] 에이전트 생성"
fi

# ===================================
# 3. Workspace 파일 복사 + 커스터마이즈
# ===================================
echo "Workspace 파일 설정 중..."
mkdir -p "$WORKSPACE"

# SOUL.md - 봇 이름/스타일 반영
if [ -f "$INSTALL_DIR/workspace/SOUL.md" ]; then
    cp "$INSTALL_DIR/workspace/SOUL.md" "$WORKSPACE/SOUL.md"
    sed -i "s/{{BOT_NAME}}/$BOT_NAME/g" "$WORKSPACE/SOUL.md"
    sed -i "s/{{STYLE}}/$STYLE/g" "$WORKSPACE/SOUL.md"
fi

# IDENTITY.md
if [ -f "$INSTALL_DIR/workspace/IDENTITY.md" ]; then
    cp "$INSTALL_DIR/workspace/IDENTITY.md" "$WORKSPACE/IDENTITY.md"
    sed -i "s/{{BOT_NAME}}/$BOT_NAME/g" "$WORKSPACE/IDENTITY.md"
fi

# Other workspace files
for f in HEARTBEAT.md TOOLS.md USER.md; do
    if [ -f "$INSTALL_DIR/workspace/$f" ]; then
        cp "$INSTALL_DIR/workspace/$f" "$WORKSPACE/$f"
    fi
done

echo "[OK] Workspace 설정 완료"

# ===================================
# 4. 모델 설정
# ===================================
echo "모델 설정: $MODEL"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_CONFIG" ]; then
    python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f:
    config = json.load(f)
for agent in config.get('agents', {}).get('list', []):
    if agent.get('id') == 'kakao':
        agent['model'] = '$MODEL'
with open('$OPENCLAW_CONFIG', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print('[OK] 모델 설정 완료')
" 2>/dev/null || echo "[WARN] 모델 설정 실패 - 수동 설정 필요"
fi

# ===================================
# 5. 파일 권한 수정
# ===================================
# PITFALL: daemon이 sudo로 실행되면 openclaw 파일 권한이 root로 바뀜
# 항상 현재 사용자로 chown
echo "파일 권한 확인..."
CURRENT_USER=$(whoami)
if [ -d "$HOME/.openclaw" ]; then
    chown -R "$CURRENT_USER:$CURRENT_USER" "$HOME/.openclaw" 2>/dev/null || \
        sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$HOME/.openclaw" 2>/dev/null || true
fi
echo "[OK]"

# ===================================
# 6. 세션 초기화 (필요시)
# ===================================
echo ""
echo "=== 세션 초기화가 필요하면 ==="
echo "  rm -rf ~/.openclaw/agents/kakao/sessions/*"
echo ""

# ===================================
# 7. 게이트웨이 재시작
# ===================================
echo "게이트웨이 재시작..."
$OPENCLAW_BIN gateway restart 2>/dev/null || echo "[WARN] 게이트웨이 재시작 실패 - 수동 실행 필요"

echo ""
echo "============================================"
echo "  OpenClaw 설정 완료!"
echo "============================================"
echo ""
echo "봇 시작:"
if command -v waydroid &>/dev/null; then
    echo "  bash $INSTALL_DIR/start-windows.sh"
else
    echo "  bash $INSTALL_DIR/start-vps.sh"
fi
echo ""
echo "=== OpenClaw 경로 (VPS에서 중요!) ==="
echo "  $OPENCLAW_BIN"
echo "  이 경로가 reedo-daemon-vps.py의 OPENCLAW_BIN과 일치하는지 확인하세요."
echo ""
