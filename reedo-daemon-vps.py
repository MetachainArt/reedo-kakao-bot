#!/usr/bin/env python3
"""
reedo-daemon-vps.py - KakaoTalk Auto-Respond Daemon (VPS + ReDroid/Docker)

Reads messages from ReDroid's KakaoTalk DB (docker cp + WAL checkpoint + decrypt).
Sends replies via ADB shell + ADB Keyboard broadcast + Shift+Enter.
Connects to OpenClaw for AI responses.

IMPORTANT:
  - MUST copy WAL files (KakaoTalk.db-wal, KakaoTalk.db-shm) alongside main DB
  - MUST run sqlite3 PRAGMA wal_checkpoint(TRUNCATE) before decryption
  - MUST use shlex.quote() for message text in subprocess calls
  - OpenClaw path must be absolute (e.g., /home/reedo/.npm-global/bin/openclaw)
  - Cannot use 'am start' for KakaoTalk (Permission Denial) - use monkey or keep chat open
  - Tap coordinates depend on resolution (720x1280: tap 360 1150 for input field)
  - sudo permissions needed: add to /etc/sudoers.d/ for docker and chmod

Usage: python3 reedo-daemon-vps.py [--config config.json]
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
KAKAO_DB_WORK = "/tmp/reedo_kakao.db"
KAKAO_DB2_WORK = "/tmp/reedo_kakao2.db"
STATE_FILE = os.path.expanduser("~/.reedo-daemon-state.json")
ADB_TARGET = "localhost:5555"

# Docker container name for ReDroid
REDROID_CONTAINER = "redroid"

# OpenClaw absolute path (adjust per user!)
# Use: which openclaw  -- to find your path
OPENCLAW_BIN = os.environ.get(
    "OPENCLAW_BIN",
    os.path.expanduser("~/.npm-global/bin/openclaw")
)


def load_config(path):
    """Load config.json with UTF-8 encoding."""
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def discover_user_id():
    """Auto-discover KakaoTalk user ID from ReDroid container."""
    try:
        subprocess.run(
            ["sudo", "docker", "cp",
             f"{REDROID_CONTAINER}:/data/data/com.kakao.talk/databases/KakaoTalk.db",
             KAKAO_DB_WORK],
            capture_output=True, timeout=10
        )
        subprocess.run(
            ["sudo", "chmod", "666", KAKAO_DB_WORK],
            capture_output=True, timeout=5
        )
        result = subprocess.run(
            ["python3", os.path.join(KAKAODECRYPT_DIR, "guess_user_id.py"), KAKAO_DB_WORK],
            capture_output=True, text=True, timeout=30
        )
        for line in result.stdout.splitlines():
            if "prob" in line and "100" in line:
                return line.strip().split()[0]
    except Exception as e:
        print(f"[WARN] User ID discovery failed: {e}")
    return None


def copy_and_decrypt_db(user_id):
    """Copy KakaoTalk DB from ReDroid container and decrypt.

    PITFALL: MUST also copy WAL files (KakaoTalk.db-wal, KakaoTalk.db-shm)
             otherwise you lose recent messages that haven't been checkpointed.
    PITFALL: MUST run sqlite3 PRAGMA wal_checkpoint(TRUNCATE) before decryption
             to merge WAL data into main DB file.
    """
    try:
        # Remove old work DB files
        for ext in ["", "-wal", "-shm"]:
            p = KAKAO_DB_WORK + ext
            if os.path.exists(p):
                os.remove(p)

        # Copy DB + WAL + SHM from Docker container
        for ext in ["", "-wal", "-shm"]:
            src = f"{REDROID_CONTAINER}:/data/data/com.kakao.talk/databases/KakaoTalk.db{ext}"
            dst = KAKAO_DB_WORK + ext
            subprocess.run(
                ["sudo", "docker", "cp", src, dst],
                capture_output=True, timeout=10
            )
            subprocess.run(
                ["sudo", "chmod", "666", dst],
                capture_output=True, timeout=5
            )

        # CRITICAL: Checkpoint WAL before decryption!
        subprocess.run(
            ["sqlite3", KAKAO_DB_WORK, "PRAGMA wal_checkpoint(TRUNCATE);"],
            capture_output=True, timeout=5
        )

        # Decrypt using kakaodecrypt
        subprocess.run(
            ["python3", os.path.join(KAKAODECRYPT_DIR, "kakaodecrypt.py"),
             "-u", user_id, KAKAO_DB_WORK],
            capture_output=True, text=True, timeout=15
        )

        # Copy and decrypt KakaoTalk2.db (friends/contacts)
        for ext in ["", "-wal", "-shm"]:
            src = f"{REDROID_CONTAINER}:/data/data/com.kakao.talk/databases/KakaoTalk2.db{ext}"
            dst = KAKAO_DB2_WORK + ext
            subprocess.run(
                ["sudo", "docker", "cp", src, dst],
                capture_output=True, timeout=10
            )
            subprocess.run(
                ["sudo", "chmod", "666", dst],
                capture_output=True, timeout=5
            )
        subprocess.run(
            ["sqlite3", KAKAO_DB2_WORK, "PRAGMA wal_checkpoint(TRUNCATE);"],
            capture_output=True, timeout=5
        )
        subprocess.run(
            ["python3", os.path.join(KAKAODECRYPT_DIR, "kakaodecrypt.py"),
             "-u", user_id, KAKAO_DB2_WORK],
            capture_output=True, text=True, timeout=15
        )

        return True
    except Exception as e:
        print(f"[ERROR] DB copy/decrypt failed: {e}")
        return False


def read_new_messages(last_id, my_user_id):
    """Read messages newer than last_id from decrypted DB."""
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
    """Get display name for a user_id from friends_dec table (KakaoTalk2.db)."""
    try:
        conn = sqlite3.connect(KAKAO_DB2_WORK)
        cur = conn.cursor()
        cur.execute("SELECT name FROM friends_dec WHERE id = ?", (user_id,))
        row = cur.fetchone()
        conn.close()
        if row and row[0]:
            return row[0]
    except:
        pass
    return str(user_id)


def get_chat_name(chat_id):
    """Get chat room name.

    - DirectChat: returns the friend's name from friends_dec
    - Open/Group chat: looks up name in open_link table (KakaoTalk2.db)
    """
    try:
        conn = sqlite3.connect(KAKAO_DB_WORK)
        cur = conn.cursor()
        cur.execute("SELECT type, members, link_id FROM chat_rooms_dec WHERE id = ?", (chat_id,))
        row = cur.fetchone()
        if not row:
            conn.close()
            return str(chat_id)

        room_type, members, link_id = row
        conn.close()

        # DirectChat: use friend name
        if room_type == "DirectChat" and members:
            member_ids = json.loads(members)
            if member_ids:
                name = get_user_name(member_ids[0])
                if not name.isdigit():
                    return name

        # Open/Group chat: look up name in open_link table (KakaoTalk2.db)
        if link_id:
            try:
                conn2 = sqlite3.connect(KAKAO_DB2_WORK)
                cur2 = conn2.cursor()
                cur2.execute("SELECT name FROM open_link WHERE id = ?", (link_id,))
                r = cur2.fetchone()
                conn2.close()
                if r and r[0]:
                    return r[0]
            except:
                pass

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
    """Get AI reply from OpenClaw agent.

    Uses a minimal prompt — bot personality is defined in SOUL.md of the
    OpenClaw workspace, so the daemon prompt only provides conversation context.
    """
    try:
        bot_name = config["bot_name"]
        agent_id = config.get("openclaw_agent_id", "kakao")
        context = get_recent_context(chat_id, my_user_id, bot_name, 5)
        context_part = f"\n최근대화:\n{context}\n" if context else ""

        prompt = f"""[{chat_name}] {sender}: "{message}"{context_part}
답장만 출력."""

        # Use absolute path for OpenClaw on VPS
        openclaw_bin = OPENCLAW_BIN
        if not os.path.exists(openclaw_bin):
            openclaw_bin = "openclaw"

        result = subprocess.run(
            [openclaw_bin, "agent", "--agent", agent_id, "-m", prompt],
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
    """Send message via adb shell + ADB Keyboard broadcast + Shift+Enter.

    PITFALL: shlex.quote() is REQUIRED for message text in subprocess calls
             to prevent shell injection with special characters.
    PITFALL: Cannot use 'am start' for KakaoTalk (Permission Denial).
             Use monkey command or just keep the chat open.
    PITFALL: Tap coordinates depend on resolution:
             - 720x1280: tap 360 1150 for input field
             - Adjust if using different resolution.
    """
    try:
        time.sleep(0.5)

        # Split long messages (ADB Keyboard has ~300 char limit)
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
            # CRITICAL: shlex.quote() for shell-safe message passing
            safe_msg = shlex.quote(chunk)
            subprocess.run(
                ["adb", "-s", ADB_TARGET, "shell",
                 f"am broadcast -a ADB_INPUT_TEXT --es msg {safe_msg}"],
                capture_output=True, timeout=10
            )
            time.sleep(0.3)

            if i < len(chunks) - 1:
                subprocess.run(
                    ["adb", "-s", ADB_TARGET, "shell", "input", "keyevent", "66"],
                    capture_output=True, timeout=5
                )
                time.sleep(0.2)

        time.sleep(0.3)

        # Send with Shift+Enter (keycombination 59=Shift, 66=Enter)
        subprocess.run(
            ["adb", "-s", ADB_TARGET, "shell", "input", "keycombination", "59", "66"],
            capture_output=True, timeout=10
        )
        time.sleep(0.5)
        return True
    except Exception as e:
        print(f"[ERROR] Send failed: {e}")
        return False


def load_state():
    """Load last seen message ID."""
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except:
        return {"last_id": 0}


def save_state(state):
    """Save state."""
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def main():
    parser = argparse.ArgumentParser(description="KakaoTalk Auto-Respond Bot (VPS/ReDroid)")
    parser.add_argument("--config", default=DEFAULT_CONFIG, help="Config file path")
    args = parser.parse_args()

    # Load config
    if os.path.exists(args.config):
        config = load_config(args.config)
    else:
        print(f"[ERROR] Config not found: {args.config}")
        print("        Copy config.json.example to config.json and edit it.")
        return

    bot_name = config["bot_name"]
    interval = config.get("interval", 5)
    trigger = config.get("group_trigger", bot_name)

    print(f"=== {bot_name} KakaoTalk Bot (VPS/ReDroid) ===")
    print(f"Model: {config.get('model', 'default')}")
    print(f"Interval: {interval}s | Trigger: {trigger}")
    print(f"ADB target: {ADB_TARGET}")
    print(f"OpenClaw: {OPENCLAW_BIN}")
    print(f"Quiet hours: {config.get('quiet_hours_start', 23)}:00 ~ {config.get('quiet_hours_end', 8)}:00")
    print()

    # Check ADB connection
    adb_check = subprocess.run(
        ["adb", "-s", ADB_TARGET, "shell", "echo", "ok"],
        capture_output=True, text=True, timeout=5
    )
    if "ok" not in adb_check.stdout:
        print("[ERROR] ADB not connected. Run: adb connect localhost:5555")
        return
    print("[OK] ADB connected")

    # Discover user ID
    print("Discovering user ID...")
    user_id = discover_user_id()
    if not user_id:
        print("[ERROR] Could not find user ID.")
        print("        Run: python3 ~/kakaodecrypt/guess_user_id.py /tmp/reedo_kakao.db")
        return
    my_user_id = int(user_id)
    print(f"User ID: {user_id}")

    state = load_state()
    print(f"Last seen: {state['last_id']}")
    print("Listening for messages...\n")

    while True:
        try:
            if not copy_and_decrypt_db(user_id):
                time.sleep(interval)
                continue

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
                if qs > qe:
                    if hour >= qs or hour < qe:
                        continue
                elif qs <= hour < qe:
                    continue

                # Trigger check
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
