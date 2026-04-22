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
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ubuntu-automation"
NOTIFY_ACTIONS_MODE_FILE="$CONFIG_DIR/notify_actions_mode"

hydrate_gui_env() {
    local key value

    if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        while IFS='=' read -r key value; do
            case "$key" in
                DISPLAY|WAYLAND_DISPLAY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|XAUTHORITY|XDG_SESSION_TYPE)
                    [ -n "$value" ] && export "$key=$value"
                    ;;
            esac
        done < <(
            systemctl --user show-environment 2>/dev/null | \
            grep -E '^(DISPLAY|WAYLAND_DISPLAY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|XAUTHORITY|XDG_SESSION_TYPE)='
        )
    fi

    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    fi
}

launch_script_with_terminal() {
    local target_script="$1"
    local helper="$HOME/.local/bin/ubuntu-automation-launch-in-terminal.sh"

    hydrate_gui_env

    if [ -x "$helper" ]; then
        "$helper" "$target_script" && return 0
    fi

    notify-send "Ubuntu Automation" "Terminal launcher helper is missing: $helper"
    return 1
}

fallback_prompt_and_maybe_run() {
    local target_script="$1"
    local choice
    local rc

    hydrate_gui_env

    if ! command -v zenity >/dev/null 2>&1; then
        return 0
    fi

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi

    choice="$(zenity --question \
        --modal \
        --title="Weekly Maintenance" \
        --text="Run Deep Clean now?" \
        --ok-label="Run Script" \
        --cancel-label="Skip" \
        --extra-button="Choose Terminal and Run" \
        --width=420 \
        --timeout=60 2>/dev/null)"
    rc=$?

    if [ "$choice" = "Choose Terminal and Run" ]; then
        "$HOME/.local/bin/ubuntu-automation-launch-in-terminal.sh" --choose-terminal >/dev/null 2>&1 || true
        launch_script_with_terminal "$target_script"
        return 0
    fi

    if [ "$rc" -eq 0 ]; then
        launch_script_with_terminal "$target_script"
    fi
}

wait_for_notification_action() {
    local title="$1"
    local body="$2"
    local app_name="$3"
    local run_label="$4"
    local prev_nid="${5:-0}"

    # Sends/replaces the notification and waits for exactly ONE action or close.
    # Prints "action:nid" — e.g. "run:42", "choose:42", "dismissed:42", "unsupported:0"
    python3 - "$title" "$body" "$app_name" "$run_label" "$prev_nid" << 'PYEOF'
import sys

try:
    import dbus
    import dbus.mainloop.glib
    from gi.repository import GLib
except Exception:
    print("unsupported:0")
    raise SystemExit(0)

title, body, app_name, run_label = sys.argv[1:5]
prev_nid = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5].isdigit() else 0

try:
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    obj = bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
    iface = dbus.Interface(obj, "org.freedesktop.Notifications")
    capabilities = {str(item) for item in iface.GetCapabilities()}
except Exception:
    print("unsupported:0")
    raise SystemExit(0)

if "actions" not in capabilities:
    print("unsupported:0")
    raise SystemExit(0)

loop = GLib.MainLoop()
result = {"action": "dismissed"}
notification_id = {"id": None}

ACTIONS = ["run", run_label, "choose", "Choose Terminal and Run", "snooze", "Snooze 1h"]
HINTS = {
    "urgency": dbus.Byte(1),
    "resident": dbus.Boolean(True),
    "transient": dbus.Boolean(False),
}

def on_action_invoked(nid, action_key):
    if notification_id["id"] is None or int(nid) != notification_id["id"]:
        return
    action = str(action_key)
    if action == "default":
        action = "run"
    result["action"] = action if action in {"choose", "run", "snooze"} else "dismissed"
    loop.quit()

def on_closed(nid, _reason):
    if notification_id["id"] is None or int(nid) != notification_id["id"]:
        return
    if result["action"] in {"run", "choose", "snooze"}:
        return  # on_action_invoked already handled this; loop is quitting
    result["action"] = "dismissed"
    loop.quit()

def on_timeout():
    result["action"] = "timeout"
    loop.quit()
    return False

bus.add_signal_receiver(on_action_invoked,
    dbus_interface="org.freedesktop.Notifications", signal_name="ActionInvoked")
bus.add_signal_receiver(on_closed,
    dbus_interface="org.freedesktop.Notifications", signal_name="NotificationClosed")

try:
    nid = int(iface.Notify(app_name, prev_nid, "computer", title, body, ACTIONS, HINTS, 45000))
    notification_id["id"] = nid
except Exception:
    print("unsupported:0")
    raise SystemExit(0)

GLib.timeout_add_seconds(45, on_timeout)
loop.run()
print(f"{result['action']}:{notification_id['id'] or 0}")
PYEOF
}

HELPER="$HOME/.local/bin/ubuntu-automation-launch-in-terminal.sh"
TARGET="$HOME/deep-clean.sh"

hydrate_gui_env
PREV_NID=0
while true; do
    _RESULT="$(wait_for_notification_action "$TITLE" "$BODY" "Weekly Maintenance" "Run Deep Clean" "$PREV_NID" 2>/dev/null)"
    [ -n "$_RESULT" ] || _RESULT="unsupported:0"
    ACTION="${_RESULT%%:*}"
    PREV_NID="${_RESULT##*:}"

    case "$ACTION" in
        run)
            # Launch script in background; loop immediately re-sends notification
            "$HELPER" "$TARGET" &
            ;;
        choose)
            # Block until user picks (or cancels) terminal, then launch
            if "$HELPER" --choose-terminal >/dev/null 2>&1; then
                "$HELPER" "$TARGET" &
            fi
            ;;
        snooze)
            # Re-fire this notification after 1 hour
            ( sleep 3600 && bash "$0" ) &
            break
            ;;
        unsupported)
            mkdir -p "$CONFIG_DIR"
            printf '%s\n' "disabled" > "$NOTIFY_ACTIONS_MODE_FILE"
            notify-send "$TITLE" "$BODY" --icon=computer --app-name="Weekly Maintenance"
            fallback_prompt_and_maybe_run "$TARGET"
            break
            ;;
        *)
            # dismissed or timeout — user is done
            break
            ;;
    esac
done
