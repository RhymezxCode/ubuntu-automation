#!/bin/bash

set -u

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ubuntu-automation"
TERMINAL_FILE="$CONFIG_DIR/terminal"
TARGET_SCRIPT=""

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

is_command_available() {
    local cmd="$1"
    if [[ "$cmd" == */* ]]; then
        [ -x "$cmd" ]
    else
        command -v "$cmd" >/dev/null 2>&1
    fi
}

discover_desktop_terminals() {
    local -a app_dirs=(
        "/usr/share/applications"
        "$HOME/.local/share/applications"
    )
    local app_dir desktop exec_line exec_bin

    for app_dir in "${app_dirs[@]}"; do
        [ -d "$app_dir" ] || continue
        while IFS= read -r desktop; do
            grep -qE '^Categories=.*TerminalEmulator' "$desktop" || continue
            exec_line="$(grep -m1 '^Exec=' "$desktop" || true)"
            [ -n "$exec_line" ] || continue
            exec_line="${exec_line#Exec=}"
            exec_bin="${exec_line%% *}"
            exec_bin="${exec_bin%%;*}"
            exec_bin="${exec_bin#\"}"
            exec_bin="${exec_bin%\"}"
            [ -n "$exec_bin" ] || continue
            [ "$exec_bin" = "env" ] && continue
            printf '%s\n' "$exec_bin"
        done < <(find "$app_dir" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null)
    done
}

list_available_terminals() {
    local -a candidates=(
        "${UBUNTU_AUTOMATION_TERMINAL:-}"
        x-terminal-emulator
        ptyxis
        gnome-terminal
        kgx
        gnome-console
        ghostty
        konsole
        xfce4-terminal
        mate-terminal
        tilix
        alacritty
        kitty
        wezterm
        terminator
        lxterminal
        urxvt
        xterm
    )
    local -a found=()
    local term

    while IFS= read -r term; do
        [ -n "$term" ] && candidates+=("$term")
    done < <(discover_desktop_terminals)

    for term in "${candidates[@]}"; do
        [ -z "$term" ] && continue
        if is_command_available "$term"; then
            case " ${found[*]} " in
                *" $term "*) ;;
                *) found+=("$term") ;;
            esac
        fi
    done

    printf '%s\n' "${found[@]}"
}

save_terminal_preference() {
    local terminal="$1"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$terminal" > "$TERMINAL_FILE"
}

load_terminal_preference() {
    if [ -f "$TERMINAL_FILE" ]; then
        head -n 1 "$TERMINAL_FILE"
    fi
}

launch_detached() {
    local log_file="$CONFIG_DIR/terminal-launch.log"
    local pid
    local rc

    mkdir -p "$CONFIG_DIR"
    "$@" >>"$log_file" 2>&1 < /dev/null &
    pid=$!

    # If the launcher dies immediately with non-zero, treat it as failure so
    # we can fall back to the next available terminal.
    sleep 0.30
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    wait "$pid" 2>/dev/null
    rc=$?
    [ "$rc" -eq 0 ]
}

run_in_terminal() {
    local terminal="$1"
    local key="${terminal##*/}"
    local run_cmd

    hydrate_gui_env
    run_cmd="bash \"$TARGET_SCRIPT\"; echo \"\"; read -r -p \"Press Enter to close...\""

    case "$key" in
        x-terminal-emulator) launch_detached "$terminal" -e bash -lc "$run_cmd" ;;
        gnome-terminal) launch_detached "$terminal" -- bash -lc "$run_cmd" ;;
        ptyxis) launch_detached "$terminal" --new-window -- bash -lc "$run_cmd" || \
                launch_detached "$terminal" -- bash -lc "$run_cmd" ;;
        kgx|gnome-console) launch_detached "$terminal" -- bash -lc "$run_cmd" ;;
        konsole) launch_detached "$terminal" -e bash -lc "$run_cmd" ;;
        xfce4-terminal|terminator) launch_detached "$terminal" -x bash -lc "$run_cmd" ;;
        mate-terminal) launch_detached "$terminal" -- bash -lc "$run_cmd" ;;
        tilix) launch_detached "$terminal" -- bash -lc "$run_cmd" ;;
        alacritty|xterm|urxvt|lxterminal) launch_detached "$terminal" -e bash -lc "$run_cmd" ;;
        kitty) launch_detached "$terminal" bash -lc "$run_cmd" ;;
        ghostty)
            launch_detached "$terminal" --gtk-single-instance=false -e bash -lc "$run_cmd" || \
            launch_detached "$terminal" -e bash -lc "$run_cmd"
            ;;
        wezterm) launch_detached "$terminal" start -- bash -lc "$run_cmd" ;;
        *) launch_detached "$terminal" -e bash -lc "$run_cmd" || launch_detached "$terminal" -- bash -lc "$run_cmd" ;;
    esac
}

pick_terminal_interactively() {
    local -a terminals=("$@")
    local choice

    hydrate_gui_env

    if [ "${#terminals[@]}" -eq 0 ]; then
        return 1
    fi

    if command -v zenity >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
        choice="$(zenity --list \
            --title="Ubuntu Automation" \
            --text="Choose terminal to run automation jobs" \
            --column="Terminal" \
            "${terminals[@]}" \
            --timeout=20 \
            --height=360 \
            --width=420 2>/dev/null || true)"
        if [ -n "$choice" ]; then
            printf '%s\n' "$choice"
            return 0
        fi
    fi

    if [ -t 0 ]; then
        local i=1
        echo "Choose terminal for Ubuntu Automation:"
        for choice in "${terminals[@]}"; do
            echo "  $i) $choice"
            i=$((i + 1))
        done
        printf "Enter number (1-%d): " "${#terminals[@]}"
        read -r i
        if [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le "${#terminals[@]}" ]; then
            printf '%s\n' "${terminals[$((i - 1))]}"
            return 0
        fi
    fi

    return 1
}

choose_terminal_for_run() {
    local -a terminals=("$@")
    local preferred="${UBUNTU_AUTOMATION_TERMINAL:-}"
    local choice

    if [ -z "$preferred" ] && [ -f "$TERMINAL_FILE" ]; then
        preferred="$(load_terminal_preference)"
    fi

    if [ -n "$preferred" ] && is_command_available "$preferred"; then
        printf '%s\n' "$preferred"
        return 0
    fi

    if [ "${#terminals[@]}" -gt 1 ] && choice="$(pick_terminal_interactively "${terminals[@]}")"; then
        save_terminal_preference "$choice"
        printf '%s\n' "$choice"
        return 0
    fi

    save_terminal_preference "${terminals[0]}"
    printf '%s\n' "${terminals[0]}"
}

print_usage() {
    echo "Usage:"
    echo "  $0 /absolute/path/to/script.sh"
    echo "  $0 --list-terminals"
    echo "  $0 --choose-terminal"
    echo "  $0 --set-terminal <terminal-binary>"
    echo "  $0 --current-terminal"
}

# Skip slow desktop-file scan when a valid saved preference exists and
# no terminal-management flag is requested (the common fast path).
_FAST_PATH=0
_ARG1="${1:-}"
if [[ "$_ARG1" != --list-terminals && "$_ARG1" != --choose-terminal && \
      "$_ARG1" != --set-terminal && "$_ARG1" != --current-terminal ]]; then
    _SAVED="$(load_terminal_preference)"
    if [ -n "$_SAVED" ] && is_command_available "$_SAVED"; then
        AVAILABLE_TERMINALS=("$_SAVED")
        _FAST_PATH=1
    fi
fi
if [ "$_FAST_PATH" -eq 0 ]; then
    mapfile -t AVAILABLE_TERMINALS < <(list_available_terminals)
fi
hydrate_gui_env

if [ "${1:-}" = "--list-terminals" ]; then
    printf '%s\n' "${AVAILABLE_TERMINALS[@]}"
    exit 0
fi

if [ "${1:-}" = "--set-terminal" ]; then
    if [ $# -lt 2 ]; then
        echo "Missing terminal binary. Example: $0 --set-terminal ptyxis" >&2
        exit 1
    fi
    if ! is_command_available "$2"; then
        echo "Terminal not found: $2" >&2
        exit 1
    fi
    save_terminal_preference "$2"
    echo "Saved terminal preference: $2"
    exit 0
fi

if [ "${1:-}" = "--current-terminal" ]; then
    CURRENT="${UBUNTU_AUTOMATION_TERMINAL:-}"
    if [ -z "$CURRENT" ]; then
        CURRENT="$(load_terminal_preference || true)"
    fi
    if [ -n "$CURRENT" ] && is_command_available "$CURRENT"; then
        echo "$CURRENT"
        exit 0
    fi
    if [ "${#AVAILABLE_TERMINALS[@]}" -gt 0 ]; then
        echo "${AVAILABLE_TERMINALS[0]}"
        exit 0
    fi
    echo "none"
    exit 1
fi

if [ "${1:-}" = "--choose-terminal" ]; then
    if [ "${#AVAILABLE_TERMINALS[@]}" -eq 0 ]; then
        echo "No supported terminal app found." >&2
        exit 1
    fi

    if CHOICE="$(pick_terminal_interactively "${AVAILABLE_TERMINALS[@]}")"; then
        save_terminal_preference "$CHOICE"
        echo "Saved terminal preference: $CHOICE"
        exit 0
    fi

    echo "No terminal selected. Use --set-terminal <binary>." >&2
    exit 1
fi

if [ $# -lt 1 ]; then
    print_usage >&2
    exit 1
fi

TARGET_SCRIPT="$1"

if [ ! -f "$TARGET_SCRIPT" ]; then
    notify-send "Ubuntu Automation" "Script not found: $TARGET_SCRIPT"
    exit 1
fi

if [ "${#AVAILABLE_TERMINALS[@]}" -eq 0 ]; then
    notify-send "Ubuntu Automation" "No supported terminal app found."
    exit 1
fi

SELECTED_TERMINAL="$(choose_terminal_for_run "${AVAILABLE_TERMINALS[@]}")"

if [ -n "$SELECTED_TERMINAL" ] && run_in_terminal "$SELECTED_TERMINAL"; then
    exit 0
fi

for term in "${AVAILABLE_TERMINALS[@]}"; do
    [ "$term" = "$SELECTED_TERMINAL" ] && continue
    if run_in_terminal "$term"; then
        save_terminal_preference "$term"
        exit 0
    fi
done

notify-send "Ubuntu Automation" "Could not open a terminal window."
exit 1
