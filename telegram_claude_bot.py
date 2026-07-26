#!/usr/bin/env python3
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8")

import telebot
import subprocess
import threading
import os
import logging

BOT_TOKEN = "8722030830:AAFVkiupi6tnO6BqvlBgqcljNHGCivH5mBA"
MY_TELEGRAM_ID = 816875295
PROJECT_PATH = r"C:\Users\Doupo\Desktop\Dragons-in-Dungeons"
CLAUDE_PS1 = r"C:\Users\Doupo\AppData\Roaming\npm\claude.ps1"
POWERSHELL = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler("claude_bot.log", encoding="utf-8")]
)
log = logging.getLogger(__name__)

bot = telebot.TeleBot(BOT_TOKEN)
active_task = {"running": False, "process": None}


def is_authorized(message):
    return message.from_user.id == MY_TELEGRAM_ID


def run_claude(chat_id, task):
    active_task["running"] = True
    cmd = [
        POWERSHELL, "-ExecutionPolicy", "Bypass", "-Command",
        f"& '{CLAUDE_PS1}' --dangerously-skip-permissions -p \"$env:CLAUDE_TASK\" --output-format text",
    ]
    log.info(f"Task start: {task[:80]}")
    try:
        env = os.environ.copy()
        env["CLAUDE_TASK"] = task
        process = subprocess.Popen(
            cmd, cwd=PROJECT_PATH, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", env=env,
        )
        active_task["process"] = process
        stdout, stderr = process.communicate()
        rc = process.returncode
        if rc == 0:
            out = stdout.strip() if stdout and stdout.strip() else "(zadny vystup)"
            if len(out) > 3800:
                out = out[:3800] + "\n...(zkraceno, vice v claude_bot.log)"
            bot.send_message(chat_id, f"OK Hotovo!\n\n{out}")
            log.info(f"Done:\n{stdout}")
        else:
            err = stderr.strip() if stderr and stderr.strip() else "(zadna chyba)"
            bot.send_message(chat_id, f"CHYBA (exit {rc})\n\n{err[:1800]}")
            log.error(f"Fail {rc}: {stderr}")
    except Exception as e:
        log.exception("Chyba")
        bot.send_message(chat_id, f"Exception: {e}")
    finally:
        active_task["running"] = False
        active_task["process"] = None


@bot.message_handler(commands=["start", "help"])
def handle_help(message):
    if not is_authorized(message):
        return
    bot.reply_to(message, "Bot bezi. Posli text = task. /status /cancel /git")


@bot.message_handler(commands=["status"])
def handle_status(message):
    if not is_authorized(message):
        return
    bot.reply_to(message, "Bezi." if active_task["running"] else "Volny.")


@bot.message_handler(commands=["cancel"])
def handle_cancel(message):
    if not is_authorized(message):
        return
    if active_task["running"] and active_task["process"]:
        active_task["process"].terminate()
        bot.reply_to(message, "Prerušeno.")
    else:
        bot.reply_to(message, "Nic nebezi.")


@bot.message_handler(commands=["git"])
def handle_git(message):
    if not is_authorized(message):
        return
    try:
        r = subprocess.run(["git", "log", "--oneline", "-10"], cwd=PROJECT_PATH,
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        bot.reply_to(message, f"Commity:\n{r.stdout}")
    except Exception as e:
        bot.reply_to(message, f"Git error: {e}")


@bot.message_handler(func=lambda m: True)
def handle_task(message):
    if not is_authorized(message):
        return
    if active_task["running"]:
        bot.reply_to(message, "Cekej, prave pracuji. /status /cancel")
        return
    task = message.text.strip()
    if not task:
        return
    bot.reply_to(message, f"Spoustim...\n{task[:100]}")
    t = threading.Thread(target=run_claude, args=(message.chat.id, task))
    t.daemon = True
    t.start()


if __name__ == "__main__":
    log.info("Bot spusten.")
    print("Bot bezi. Ctrl+C pro ukonceni.")
    bot.infinity_polling(timeout=30, long_polling_timeout=30)
