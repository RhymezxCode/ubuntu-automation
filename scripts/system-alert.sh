#!/bin/bash

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

hydrate_gui_env

ALERTS=()

# ── Disk check ──────────────────────────────────
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
if [ "$DISK_PCT" -ge 90 ]; then
    ALERTS+=("🔴  Disk ${DISK_PCT}% full — only ${DISK_AVAIL} free! Run deepclean now.")
elif [ "$DISK_PCT" -ge 80 ]; then
    ALERTS+=("🟡  Disk ${DISK_PCT}% used — ${DISK_AVAIL} remaining.")
fi

# ── Battery check ────────────────────────────────
BAT_PATH="/sys/class/power_supply/BAT0"
if [ -f "$BAT_PATH/capacity" ] && [ -f "$BAT_PATH/status" ]; then
    BAT_PCT=$(cat "$BAT_PATH/capacity")
    BAT_STATUS=$(cat "$BAT_PATH/status")
    if [ "$BAT_PCT" -le 10 ] && [ "$BAT_STATUS" != "Charging" ]; then
        ALERTS+=("🪫  Battery critically low: ${BAT_PCT}% — plug in now!")
    elif [ "$BAT_PCT" -le 20 ] && [ "$BAT_STATUS" != "Charging" ]; then
        ALERTS+=("🔋  Battery low: ${BAT_PCT}%")
    fi
fi

# ── Send alerts ──────────────────────────────────
if [ "${#ALERTS[@]}" -gt 0 ]; then
    BODY=$(printf '%s\n' "${ALERTS[@]}")
    notify-send "⚠️  System Alert" "$BODY" \
        --urgency=critical \
        --icon=dialog-warning \
        --app-name="Ubuntu Automation" \
        --expire-time=0 2>/dev/null || true
fi
