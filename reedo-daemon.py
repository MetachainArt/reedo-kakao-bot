#!/usr/bin/env python3
"""
reedo-daemon.py - KakaoTalk Auto-Respond Daemon (Windows WSL2 + Waydroid)

Reads messages from Waydroid's KakaoTalk DB (decrypted, background - no focus stealing).
Sends replies via ADB Keyboard broadcast + Shift+Enter.
Connects to OpenClaw for AI responses.

IMPORTANT:
  - Must run with: sudo HOME=/home/$USER python3 reedo-daemon.py
  - Clipboard approach does NOT work in background (steals focus)
  - DB must be copied with sudo (Waydroid DB owned by root)

Usage: python3 reedo-daemon.py [--config config.json]
"""

import argparse
import json
import os
import shlex
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

# === Paths ===
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.join(SCRIPT_DIR, "config.json")
KAKAODECRYPT_DIR = os.path.expanduser("~/kakaodecrypt")
KAKAO_DB_SRC = os.path.expanduser(
    "~/.local/share/waydroid/data/data/com.kakao.talk/databases/KakaoTalk.db"
)
KAKAO_DB_WORK = "/tmp/reedo_kakao.db"
STATE_FILE = os.path.expanduser("~/.reedo-daemon-state.json")


def load_config(path):
    """Load config.json with UTF-8 encoding."""
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def discover_user_id():
    """Auto-discover KakaoTalk user ID using guess_user_id.py from kakaodecrypt."""
    guess_script = os.path.join(KAKAODECRYPT_DIR, "guess_user_id.py")
    if not os.path.exists(guess_script):
        print("[WARN] guess_user_id.py not found. Install kakaodecrypt first.")
        return None
    try:
        # Copy DB for guess (need sudo because Waydroid DB is root-owned)
        subprocess.run(
            ["sudo", "cp", KAKAO_DB_SRC, KAKAO_DB_WORK],
            capture_output=True, timeout=5
        )
        subprocess.run(
            ["sudo", "chmod", "666", KAKAO_DB_WORK],
            capture_output=True, timeout=5
        )
        result = subprocess.run(
            ["python3", guess_script, KAKAO_DB_WORK],
            capture_output=True, text=True, timeout=30
        )
        for line in result.stdout.splitlines():
            if "prob" in line and "100" in line:
                uid = line.strip().split()[0]
                return uid
    except Exception as e:
        print(f"[WARN] User ID discovery failed: {e}")
    return None


def copy_and_decrypt_db(user_id):
    """Copy KakaoTalk DB from Waydroid and decrypt it.

    PITFALL: Waydroid DB is owned by root, so sudo cp is required.
    We also copy WAL/SHM files to ensure consistency.
    """
    try:
        # Remove old work DB files
        for ext in ["", "-wal", "-shm"]:
            dst = KAKAO_DB_WORK + ext
            if os.path.exists(dst):
                os.remove(dst)

        # Copy with sudo (Waydroid DB is owned by root!)
        for ext in ["", "-wal", "-shm"]:
            src = KAKAO_DB_SRC + ext
            dst = KAKAO_DB_WORK + ext
            subprocess.run(["sudo", "cp", src, dst], capture_output=True, timeout=5)
            subprocess.run(["sudo", "chmod", "666", dst], capture_output=True, timeout=5)

        # Checkpoint WAL to merge pending writes into main DB
        subprocess.run(
            ["sqlite3", KAKAO_DB_WORK, "PRAGMA wal_checkpoint(TRUNCATE);"],
            capture_output=True, timeout=5
        )

        # Decrypt using kakaodecrypt
        result = subprocess.run(
            ["python3", os.path.join(KAKAODECRYPT_DIR, "kakaodecrypt.py"),
             "-u", user_id, KAKAO_DB_WORK],
            capture_output=True, text=True, timeout=15
        )
        return True
    except Exception as e:
        print(f"[ERROR] DB copy/decrypt failed: {e}")
        return False


def read_new_messages(last_id, my_user_id):
    """Read messages newer than last_id from decrypted DB.

    type=1 means text message. We skip our own messages.
    """
    try:
        conn = sqlite3.connect(KAKAO_DB_WORK)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("""
            SELECT cl._id, cl.id as msg_id, cl.chat_id, cl.user_id,
                   cl.message, cl.created_at, cl.type,
                   cr.type as room_type
            FROM chat_logs_dec cl
            LEFT JOIN chat_rooms_dec cr ON cl.chat_id = cr.id
            WHERE cl._id > ? AND cl.type = 1 AND cl.user_id != ?
            ORDER BY cl._id ASC
        """, (last_id, my_user_id))
        messages = [dict(row) for row in cur.fetchall()]
        conn.close()
        return messages
    except Exception as e:
        print(f"[ERROR] Read messages failed: {e}")
        return []


def get_user_name(user_id):
    """Get display name for a user_id from friends table."""
    try:
        conn = sqlite3.connect(KAKAO_DB_WORK)
        cur = conn.cursor()
        cur.execute("SELECT name FROM friends WHERE id = ?", (user_id,))
        row = cur.fetchone()
        conn.close()
        return row[0] if row else str(user_id)
    except:
        return str(user_id)


def get_chat_name(chat_id):
    """Get chat room name. For DirectChat, returns the friend's name."""
    try:
        conn = sqlite3.connect(KAKAO_DB_WORK)
        cur = conn.cursor()
        cur.execute("SELECT type, members FROM chat_rooms_dec WHERE id = ?", (chat_id,))
        row = cur.fetchone()
        if row and row[0] == "DirectChat" and row[1]:
            member_ids = json.loads(row[1])
            if member_ids:
                conn.close()
                return get_user_name(member_ids[0])
        conn.close()
        return str(chat_id)
    except:
        return str(chat_id)


def get_recent_context(chat_id, my_user_id, bot_name, limit=10):
    """Get recent messages for AI context."""
    try:
        conn = sqlite3.connect(KAKAO_DB_WORK)
        cur = conn.cursor()
        cur.execute("""
            SELECT user_id, message FROM chat_logs_dec
            WHERE chat_id = ? AND type = 1 AND message IS NOT NULL
            ORDER BY _id DESC LIMIT ?
        """, (chat_id, limit))
        rows = cur.fetchall()
        conn.close()
        lines = []
        for uid, msg in reversed(rows):
            name = get_user_name(uid) if uid != my_user_id else bot_name
            lines.append(f"{name}: {msg}")
        return "\n".join(lines)
    except:
        return ""


def get_ai_reply(config, chat_name, sender, message, chat_id, my_user_id):
    """Get AI reply from OpenClaw agent."""
    try:
        bot_name = config["bot_name"]
        style = config["style"]
        agent_id = config.get("openclaw_agent_id", "kakao")
        context = get_recent_context(chat_id, my_user_id, bot_name, 10)
        context_part = f"\n\n최근 대화:\n{context}\n\n" if context else ""

        prompt = f"""카카오톡 '{chat_name}' 채팅방.{context_part}{sender}의 마지막 메시지: \"{message}\"

너는 {bot_name}(똑똑한 AI 비서). 규칙:
- {style}
- 질문에 정확하고 구체적으로 답해. 요청한 만큼 길게 써.
- 분석, 목록, 계획 등을 요청하면 상세하게 작성해.
- 간단한 인사나 잡담에만 짧게 답해.
- 답장 텍스트만 출력."""

        result = subprocess.run(
            ["openclaw", "agent", "--agent", agent_id, "-m", prompt],
            capture_output=True, text=True, timeout=120
        )
        reply = result.stdout.strip()
        max_len = config.get("max_reply_length", 1000)
        if len(reply) > max_len:
            reply = reply[:max_len]
        if not reply:
            reply = f"안녕하세요~! {bot_name}예요! 😊"
        return reply
    except Exception as e:
        print(f"[ERROR] AI reply failed: {e}")
        return f"안녕하세요~! 😊"


def send_message(message):
    """Send message via ADB Keyboard broadcast + Shift+Enter.

    PITFALL: Korean text must be sent via ADB_INPUT_TEXT broadcast, not 'input text'.
    PITFALL: shlex.quote() is needed for shell-safe message passing.
    PITFALL: Shift+Enter (keycombination 59 66) sends the message in KakaoTalk.
    """
    try:
        # Tap chat input area to ensure focus (Waydroid default resolution)
        subprocess.run(
            ["sudo", "waydroid", "shell", "--", "input", "tap", "960", "1100"],
            capture_output=True, timeout=10
        )
        time.sleep(0.5)

        # Split long messages (ADB Keyboard has ~300 char limit per broadcast)
        chunks = []
        if len(message) <= 300:
            chunks = [message]
        else:
            lines = message.split("\n")
            current = ""
            for line in lines:
                if len(current) + len(line) + 1 > 300:
                    if current:
                        chunks.append(current)
                    current = line
                else:
                    current = (current + "\n" + line) if current else line
            if current:
                chunks.append(current)

        # Send each chunk via ADB Keyboard broadcast
        for i, chunk in enumerate(chunks):
            # Use shlex.quote for shell safety
            safe_chunk = shlex.quote(chunk)
            subprocess.run(
                ["sudo", "waydroid", "shell", "--", "am", "broadcast",
                 "-a", "ADB_INPUT_TEXT", "--es", "msg", chunk],
                capture_output=True, timeout=10
            )
            time.sleep(0.3)

            if i < len(chunks) - 1:
                # Newline between chunks (Enter without Shift = newline in input)
                subprocess.run(
                    ["sudo", "waydroid", "shell", "--", "input", "keyevent", "66"],
                    capture_output=True, timeout=5
                )
                time.sleep(0.2)

        time.sleep(0.3)

        # Send with Shift+Enter (keycombination 59=Shift, 66=Enter)
        subprocess.run(
            ["sudo", "waydroid", "shell", "--", "input", "keycombination", "59", "66"],
            capture_output=True, timeout=10
        )
        time.sleep(0.5)
        return True
    except Exception as e:
        print(f"[ERROR] Send failed: {e}")
        return False


def load_state():
    """Load last seen message ID from state file."""
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except:
        return {"last_id": 0}


def save_state(state):
    """Save state to file."""
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def fix_file_permissions():
    """Fix file permissions that sudo may have messed up.

    PITFALL: Running daemon as sudo can change openclaw file ownership.
    Always chown back to the actual user.
    """
    real_user = os.environ.get("SUDO_USER", os.environ.get("USER", ""))
    if real_user:
        openclaw_dir = os.path.expanduser(f"~{real_user}/.openclaw")
        if os.path.exists(openclaw_dir):
            subprocess.run(
                ["chown", "-R", f"{real_user}:{real_user}", openclaw_dir],
                capture_output=True, timeout=10
            )


def main():
    parser = argparse.ArgumentParser(description="KakaoTalk Auto-Respond Bot (Windows WSL2)")
    parser.add_argument("--config", default=DEFAULT_CONFIG, help="Config file path")
    args = parser.parse_args()

    config = load_config(args.config)
    bot_name = config["bot_name"]
    interval = config.get("interval", 5)
    trigger = config.get("group_trigger", bot_name)

    print(f"=== {bot_name} KakaoTalk Bot (Windows/WSL2) ===")
    print(f"Model: {config.get('model', 'default')}")
    print(f"Interval: {interval}s")
    print(f"Group trigger: {trigger}")
    print(f"Style: {config.get('style', 'default')}")
    print(f"Quiet hours: {config.get('quiet_hours_start', 23)}:00 ~ {config.get('quiet_hours_end', 8)}:00")
    print()

    # Auto-discover user ID
    print("Discovering KakaoTalk user ID...")
    user_id = discover_user_id()
    if not user_id:
        print("[ERROR] Could not discover user ID.")
        print("        Run: python3 ~/kakaodecrypt/guess_user_id.py /tmp/reedo_kakao.db")
        return
    my_user_id = int(user_id)
    print(f"User ID: {user_id}")
    print()

    state = load_state()
    print(f"Last seen ID: {state['last_id']}")
    print("Listening for messages...\n")

    while True:
        try:
            # 1. Copy + Decrypt DB
            if not copy_and_decrypt_db(user_id):
                time.sleep(interval)
                continue

            # 2. Read new messages
            messages = read_new_messages(state["last_id"], my_user_id)

            for msg in messages:
                sender = get_user_name(msg["user_id"])
                chat_name = get_chat_name(msg["chat_id"])
                text = msg["message"] or ""
                state["last_id"] = msg["_id"]

                if not text.strip():
                    continue

                # Quiet hours check
                hour = int(time.strftime("%H"))
                qs = config.get("quiet_hours_start", 23)
                qe = config.get("quiet_hours_end", 8)
                if qs > qe:  # e.g., 23:00 ~ 08:00
                    if hour >= qs or hour < qe:
                        continue
                elif qs <= hour < qe:
                    continue

                # Trigger check: DM = always reply, Group = only on trigger word
                should_reply = (
                    config.get("reply_all_dm", True) and msg["room_type"] == "DirectChat"
                )
                if not should_reply and trigger in text:
                    should_reply = True

                if should_reply:
                    print(f"[{time.strftime('%H:%M:%S')}] {chat_name} > {sender}: {text}")

                    reply = get_ai_reply(
                        config, chat_name, sender, text, msg["chat_id"], my_user_id
                    )
                    print(f"[{time.strftime('%H:%M:%S')}] {bot_name} -> {chat_name}: {reply}")

                    send_message(reply)

                    # Fix permissions after each AI call (sudo may mess them up)
                    fix_file_permissions()

            save_state(state)

        except KeyboardInterrupt:
            print(f"\n{bot_name} stopped.")
            save_state(state)
            break
        except Exception as e:
            print(f"[ERROR] {e}")

        time.sleep(interval)


if __name__ == "__main__":
    main()
