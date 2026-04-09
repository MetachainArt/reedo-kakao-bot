#!/bin/bash
echo "============================================"
echo "  카카오톡 설치 가이드"
echo "============================================"
echo ""

# Detect environment
if command -v waydroid &>/dev/null; then
    MODE="windows"
else
    MODE="vps"
fi

if [ "$MODE" = "windows" ]; then
    echo "=== Windows WSL2 (Waydroid) 모드 ==="
    echo ""
    echo "Waydroid 안드로이드 화면이 보여야 합니다."
    echo "안 보이면 먼저: bash start-windows.sh"
    echo ""
    echo "=== 수동 설치 순서 ==="
    echo ""
    echo "1. 안드로이드 화면에서 Play Store 열기"
    echo "2. Google 계정 로그인"
    echo "3. 'KakaoTalk' 검색 -> 설치"
    echo "4. 카카오톡 열기 -> 로그인"
    echo ""
    echo "!!! 주의: 로그인하면 기존 폰에서 로그아웃됩니다 !!!"
    echo ""

    # ADB Keyboard 설치
    echo "=== ADB Keyboard 설치 ==="
    ADB_APK="$HOME/ADBKeyBoard.apk"
    if [ -f "$ADB_APK" ] && [ -s "$ADB_APK" ]; then
        echo "ADB Keyboard APK 발견. 설치 중..."
        waydroid app install "$ADB_APK" 2>/dev/null || true

        # PITFALL: settings put secure / ime enable / ime set 순서로 해야 함
        sudo waydroid shell -- settings put secure enabled_input_methods \
            "com.android.adbkeyboard/.AdbIME:com.android.inputmethod.latin/.LatinIME" 2>/dev/null
        sudo waydroid shell -- ime enable com.android.adbkeyboard/.AdbIME 2>/dev/null
        sudo waydroid shell -- ime set com.android.adbkeyboard/.AdbIME 2>/dev/null
        echo "[OK] ADB Keyboard 설치 + 활성화 완료"
    else
        echo "[!] ADB Keyboard APK가 없습니다. install-windows.sh를 먼저 실행하세요."
    fi

else
    echo "=== VPS (ReDroid) 모드 ==="
    echo ""
    echo "=== 방법 1: scrcpy로 화면 보면서 설치 (권장) ==="
    echo ""
    echo "로컬 PC에서:"
    echo "  scrcpy --tcpip=<VPS_IP>:5555 --no-audio"
    echo ""
    echo "화면에서 브라우저 열고 카카오톡 APK 다운로드 후 설치"
    echo ""
    echo "=== 방법 2: Split APK로 설치 ==="
    echo ""
    echo "카카오톡 APK를 PC에서 추출 후 VPS로 전송:"
    echo "  scp base.apk split_config.*.apk user@vps:~/"
    echo ""
    echo "VPS에서 설치:"
    echo "  adb -s localhost:5555 install-multiple base.apk split_config.arm64_v8a.apk split_config.xxhdpi.apk split_config.ko.apk"
    echo ""
    echo "!!! 주의: 로그인하면 기존 폰에서 로그아웃됩니다 !!!"
    echo ""

    # ADB Keyboard 설치
    echo "=== ADB Keyboard 설치 ==="
    ADB_APK="$HOME/ADBKeyBoard.apk"
    if [ -f "$ADB_APK" ] && [ -s "$ADB_APK" ]; then
        echo "ADB Keyboard APK 발견. 설치 중..."
        adb -s localhost:5555 install "$ADB_APK" 2>/dev/null || true
        adb -s localhost:5555 shell settings put secure enabled_input_methods \
            "com.android.adbkeyboard/.AdbIME:com.android.inputmethod.latin/.LatinIME" 2>/dev/null
        adb -s localhost:5555 shell ime enable com.android.adbkeyboard/.AdbIME 2>/dev/null
        adb -s localhost:5555 shell ime set com.android.adbkeyboard/.AdbIME 2>/dev/null
        echo "[OK] ADB Keyboard 설치 + 활성화 완료"
    else
        echo "[!] ADB Keyboard APK가 없습니다. install-vps.sh를 먼저 실행하세요."
    fi

    echo ""
    echo "=== 카카오톡 실행 ==="
    echo ""
    echo "PITFALL: am start로는 Permission Denial 발생!"
    echo "대신 monkey 명령 사용:"
    echo "  adb -s localhost:5555 shell monkey -p com.kakao.talk 1"
    echo ""
    echo "또는 카카오톡 채팅방을 열어둔 상태로 유지하세요."
fi

echo ""
echo "카카오톡 로그인 완료 후, setup-openclaw.sh를 실행하세요."
echo ""

# 한글 전송 테스트
echo "=== 한글 전송 테스트 ==="
echo "카카오톡 채팅방을 열고 다음 명령 실행:"
echo ""
if [ "$MODE" = "windows" ]; then
    echo '  sudo waydroid shell -- am broadcast -a ADB_INPUT_TEXT --es msg "테스트 한글 입력"'
    echo '  sudo waydroid shell -- input keycombination 59 66'
else
    echo '  adb -s localhost:5555 shell "am broadcast -a ADB_INPUT_TEXT --es msg '\''테스트 한글 입력'\''"'
    echo '  adb -s localhost:5555 shell input keycombination 59 66'
fi
echo ""
echo "채팅방에 '테스트 한글 입력'이 전송되면 성공!"
echo ""
