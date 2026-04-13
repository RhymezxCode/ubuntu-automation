#!/bin/bash

TITLE_FILE=$(mktemp)
BODY_FILE=$(mktemp)
trap 'rm -f "$TITLE_FILE" "$BODY_FILE"' EXIT

python3 - "$TITLE_FILE" "$BODY_FILE" << 'PYEOF'
import subprocess, os, datetime, random, re, sys

QUOTES = [
    "A clean machine is a fast machine.",
    "Clutter is the enemy of clarity.",
    "Take care of your tools and they'll take care of you.",
    "Small maintenance today prevents big problems tomorrow.",
    "Clean code, clean cache, clean mind.",
    "Messy disk, messy builds. Keep it clean.",
    "Sunday is for rest — and a quick cleanup.",
    "Free up space, free up speed.",
    "Your SSD will thank you.",
    "Build caches grow like weeds. Time to pull them out.",
    "Old kernels, old snaps, old logs — let them go.",
    "A lean system is a happy system.",
    "Don't let your disk fill up before you act.",
    "Routine maintenance is the secret to longevity.",
    "Your laptop works hard for you. Return the favor.",
]

def get_disk_stats():
    lines = []

    try:
        st = os.statvfs("/")
        disk_total = st.f_blocks * st.f_frsize
        disk_free = st.f_bavail * st.f_frsize
        disk_pct = int(((disk_total - disk_free) / disk_total) * 100)
        disk_free_gb = f"{disk_free / (1024**3):.0f}"
        disk_total_gb = f"{disk_total / (1024**3):.0f}"

        icon = "🟢" if disk_pct < 70 else ("🟡" if disk_pct <= 85 else "🔴")
        lines.append(f"{icon}  Disk: {disk_pct}% used · {disk_free_gb} GB free of {disk_total_gb} GB")
    except Exception:
        pass

    try:
        result = subprocess.run(
            ["du", "-sm", os.path.expanduser("~/.gradle/caches")],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            gradle_mb = int(result.stdout.split()[0])
            if gradle_mb > 100:
                lines.append(f"📦  Gradle cache: {gradle_mb} MB")
    except Exception:
        pass

    try:
        result = subprocess.run(
            ["journalctl", "--disk-usage"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            match = re.search(r'([\d.]+[MG])', result.stdout)
            if match:
                lines.append(f"📜  Journal logs: {match.group(1)}")
    except Exception:
        pass

    try:
        trash_path = os.path.expanduser("~/.local/share/Trash")
        if os.path.exists(trash_path):
            result = subprocess.run(
                ["du", "-sm", trash_path],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                trash_mb = int(result.stdout.split()[0])
                if trash_mb > 10:
                    lines.append(f"🗑️  Trash: {trash_mb} MB")
    except Exception:
        pass

    return "\n".join(lines)

title_file = sys.argv[1]
body_file = sys.argv[2]

now = datetime.datetime.now()
today = now.strftime("%A, %B %d, %Y")
time_str = now.strftime("%I:%M %p").lstrip("0")
quote = random.choice(QUOTES)
stats = get_disk_stats()

title = "🧹  Sunday Deep Clean"

body_lines = [
    f"<b>{today} · {time_str}</b>",
    "",
    "Your system could use a weekly cleanup!",
    "",
]

if stats:
    body_lines.append(stats)
    body_lines.append("")

body_lines.append(f"<i>💬  \"{quote}\"</i>")

body = "\n".join(body_lines)

with open(title_file, "w") as f:
    f.write(title)
with open(body_file, "w") as f:
    f.write(body)
PYEOF

TITLE=$(<"$TITLE_FILE")
BODY=$(<"$BODY_FILE")

launch_script_with_terminal() {
    local target_script="$1"
    local helper="$HOME/.local/bin/ubuntu-automation-launch-in-terminal.sh"

    if [ -x "$helper" ]; then
        "$helper" "$target_script" && return 0
    fi

    notify-send "Ubuntu Automation" "Terminal launcher helper is missing: $helper"
    return 1
}

ACTION=$(notify-send "$TITLE" "$BODY" \
    --icon=computer \
    --app-name="Weekly Maintenance" \
    --action="default=Open Job" \
    --action="run=🧹 Run Deep Clean" \
    --wait)

if [ "$ACTION" = "run" ] || [ "$ACTION" = "default" ]; then
    launch_script_with_terminal "$HOME/deep-clean.sh"
fi
