#!/bin/bash

TITLE_FILE=$(mktemp)
BODY_FILE=$(mktemp)
trap 'rm -f "$TITLE_FILE" "$BODY_FILE"' EXIT

python3 - "$TITLE_FILE" "$BODY_FILE" << 'PYEOF'
import subprocess, os, datetime, random, sys

QUOTES = [
    "The only way to do great work is to love what you do. — Steve Jobs",
    "First, solve the problem. Then, write the code. — John Johnson",
    "Code is like humor. When you have to explain it, it's bad. — Cory House",
    "Simplicity is the soul of efficiency. — Austin Freeman",
    "Make it work, make it right, make it fast. — Kent Beck",
    "Talk is cheap. Show me the code. — Linus Torvalds",
    "The best error message is the one that never shows up. — Thomas Fuchs",
    "Any fool can write code that a computer can understand. Good programmers write code that humans can understand. — Martin Fowler",
    "Programs must be written for people to read. — Harold Abelson",
    "Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away. — Antoine de Saint-Exupéry",
    "It does not matter how slowly you go as long as you do not stop. — Confucius",
    "The secret of getting ahead is getting started. — Mark Twain",
    "Your limitation — it's only your imagination.",
    "Push yourself, because no one else is going to do it for you.",
    "Great things never come from comfort zones.",
    "Dream it. Wish it. Do it.",
    "Don't stop when you're tired. Stop when you're done.",
    "Wake up with determination. Go to bed with satisfaction.",
    "Little things make big days.",
    "The hard days are what make you stronger.",
    "Stay focused and never give up.",
    "Discipline is the bridge between goals and accomplishment. — Jim Rohn",
    "Success is the sum of small efforts repeated day in and day out. — Robert Collier",
    "You don't have to be great to start, but you have to start to be great. — Zig Ziglar",
    "Shipping beats perfection.",
    "One commit at a time.",
    "Today's code is tomorrow's legacy. Make it count.",
    "Debug your life the way you debug your code — one breakpoint at a time.",
    "A clean codebase is a happy codebase.",
    "Build, break, learn, repeat.",
]

def get_greeting():
    hour = datetime.datetime.now().hour
    if hour < 12:
        return "Good Morning"
    elif hour < 17:
        return "Good Afternoon"
    else:
        return "Good Evening"

def get_weather():
    try:
        result = subprocess.run(
            ["curl", "-s", "--max-time", "5", "wttr.in/?format=%C|%t|%h|%l"],
            capture_output=True, text=True, timeout=8
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split("|")
            if len(parts) >= 4:
                condition = parts[0].strip()
                temp = parts[1].strip().lstrip("+")
                humidity = parts[2].strip()
                location = parts[3].strip().title()

                weather_icons = {
                    "sunny": "☀️", "clear": "🌙",
                    "partly cloudy": "⛅", "cloudy": "☁️",
                    "overcast": "🌥️",
                    "rain": "🌧️", "light rain": "🌦️",
                    "heavy rain": "⛈️", "drizzle": "🌦️",
                    "thunder": "⛈️", "storm": "⛈️",
                    "snow": "❄️", "fog": "🌫️", "mist": "🌫️",
                    "haze": "🌫️",
                }
                icon = "🌤️"
                for key, emoji in weather_icons.items():
                    if key in condition.lower():
                        icon = emoji
                        break

                return f"{icon}  {condition}, {temp} · {humidity} humidity — {location}"
    except Exception:
        pass
    return None

def get_system_stats():
    lines = []

    try:
        with open("/proc/meminfo") as f:
            mi = {}
            for line in f:
                parts = line.split()
                if parts[0] in ("MemTotal:", "MemAvailable:"):
                    mi[parts[0]] = int(parts[1])
            total = mi.get("MemTotal:", 0)
            avail = mi.get("MemAvailable:", 0)
            used_pct = int(((total - avail) / total) * 100) if total else 0
            total_gb = f"{total / 1048576:.1f}"

        icon = "🟢" if used_pct < 60 else ("🟡" if used_pct <= 85 else "🔴")
        lines.append(f"{icon}  RAM {used_pct}% of {total_gb} GB")
    except Exception:
        pass

    try:
        st = os.statvfs("/")
        disk_total = st.f_blocks * st.f_frsize
        disk_free = st.f_bavail * st.f_frsize
        disk_pct = int(((disk_total - disk_free) / disk_total) * 100)
        disk_free_gb = f"{disk_free / (1024**3):.0f}"

        icon = "🟢" if disk_pct < 70 else ("🟡" if disk_pct <= 85 else "🔴")
        lines.append(f"{icon}  Disk {disk_pct}% used · {disk_free_gb} GB free")
    except Exception:
        pass

    try:
        with open("/sys/class/power_supply/BAT0/capacity") as f:
            bat_pct = int(f.read().strip())
        with open("/sys/class/power_supply/BAT0/status") as f:
            bat_status = f.read().strip().lower()

        if bat_pct > 80:
            bat_icon = "🔋"
        elif bat_pct > 30:
            bat_icon = "🔋"
        else:
            bat_icon = "🪫"

        charge = " ⚡" if bat_status == "charging" else ""
        lines.append(f"{bat_icon}  Battery {bat_pct}%{charge}")
    except Exception:
        pass

    try:
        with open("/proc/loadavg") as f:
            load = f.read().split()[0]
        lines.append(f"📊  Load {load}")
    except Exception:
        pass

    return "\n".join(lines)

title_file = sys.argv[1]
body_file = sys.argv[2]

greeting = get_greeting()
now = datetime.datetime.now()
today = now.strftime("%A, %B %d, %Y")
time_str = now.strftime("%I:%M %p").lstrip("0")
quote = random.choice(QUOTES)
stats = get_system_stats()
weather = get_weather()

title = f"☀️  {greeting}, rhymezxcode!"

body_lines = [
    f"<b>{today} · {time_str}</b>",
    "",
]

if weather:
    body_lines.append(weather)
    body_lines.append("")

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
        --title="Daily Maintenance" \
        --text="Run Morning Script now?" \
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

ACTIONS = ["run", run_label, "choose", "Choose Terminal and Run"]
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
    result["action"] = action if action in {"choose", "run"} else "dismissed"
    loop.quit()

def on_closed(nid, _reason):
    if notification_id["id"] is None or int(nid) != notification_id["id"]:
        return
    if result["action"] in {"run", "choose"}:
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
TARGET="$HOME/daily-startup.sh"

hydrate_gui_env
PREV_NID=0
while true; do
    _RESULT="$(wait_for_notification_action "$TITLE" "$BODY" "Daily Maintenance" "Run Morning Script" "$PREV_NID" 2>/dev/null)"
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
        unsupported)
            mkdir -p "$CONFIG_DIR"
            printf '%s\n' "disabled" > "$NOTIFY_ACTIONS_MODE_FILE"
            notify-send "$TITLE" "$BODY" --icon=computer --app-name="Daily Maintenance"
            fallback_prompt_and_maybe_run "$TARGET"
            break
            ;;
        *)
            # dismissed or timeout — user is done
            break
            ;;
    esac
done
