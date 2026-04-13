#!/bin/bash

set -u

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ubuntu-automation"
TERMINAL_FILE="$CONFIG_DIR/terminal"
TARGET_SCRIPT=""

list_available_terminals() {
    local -a candidates=(
        "${UBUNTU_AUTOMATION_TERMINAL:-}"
        x-terminal-emulator
        gnome-terminal
        ptyxis
        kgx
        gnome-console
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

    for term in "${candidates[@]}"; do
        [ -z "$term" ] && continue
        if command -v "$term" >/dev/null 2>&1; then
            case " ${found[*]} " in
                *" $term "*) ;;
                *) found+=("$term") ;;
            esac
        fi
    done

    printf '%s\n' "${found[@]}"
}

run_in_terminal() {
    local terminal="$1"
    local run_cmd
    run_cmd="bash \"$TARGET_SCRIPT\"; echo \"\"; read -r -p \"Press Enter to close...\""

    case "$terminal" in
        x-terminal-emulator) "$terminal" -e bash -lc "$run_cmd" ;;
        gnome-terminal) "$terminal" -- bash -lc "$run_cmd" ;;
        ptyxis) "$terminal" --standalone -- bash -lc "$run_cmd" ;;
        kgx|gnome-console) "$terminal" -- bash -lc "$run_cmd" ;;
        konsole) "$terminal" -e bash -lc "$run_cmd" ;;
        xfce4-terminal|terminator) "$terminal" -x bash -lc "$run_cmd" ;;
        mate-terminal) "$terminal" -- bash -lc "$run_cmd" ;;
        tilix) "$terminal" -- bash -lc "$run_cmd" ;;
        alacritty|xterm|urxvt|lxterminal) "$terminal" -e bash -lc "$run_cmd" ;;
        kitty) "$terminal" bash -lc "$run_cmd" ;;
        wezterm) "$terminal" start -- bash -lc "$run_cmd" ;;
        *) "$terminal" -e bash -lc "$run_cmd" ;;
    esac
}

pick_terminal_interactively() {
    local -a terminals=("$@")
    local choice

    if [ "${#terminals[@]}" -eq 0 ]; then
        return 1
    fi

    if command -v zenity >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
        choice="$(zenity --list \
            --title="Ubuntu Automation" \
            --text="Choose terminal to run automation jobs" \
            --column="Terminal" \
            "${terminals[@]}" \
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

choose_terminal() {
    local -a terminals=("$@")
    local preferred="${UBUNTU_AUTOMATION_TERMINAL:-}"
    local choice

    if [ -z "$preferred" ] && [ -f "$TERMINAL_FILE" ]; then
        preferred="$(head -n 1 "$TERMINAL_FILE")"
    fi

    if [ -n "$preferred" ] && command -v "$preferred" >/dev/null 2>&1; then
        printf '%s\n' "$preferred"
        return 0
    fi

    if [ "${#terminals[@]}" -gt 1 ] && choice="$(pick_terminal_interactively "${terminals[@]}")"; then
        mkdir -p "$CONFIG_DIR"
        printf '%s\n' "$choice" > "$TERMINAL_FILE"
        printf '%s\n' "$choice"
        return 0
    fi

    printf '%s\n' "${terminals[0]}"
}

print_usage() {
    echo "Usage:"
    echo "  $0 /absolute/path/to/script.sh"
    echo "  $0 --list-terminals"
    echo "  $0 --choose-terminal"
}

mapfile -t AVAILABLE_TERMINALS < <(list_available_terminals)

if [ "${1:-}" = "--list-terminals" ]; then
    printf '%s\n' "${AVAILABLE_TERMINALS[@]}"
    exit 0
fi

if [ "${1:-}" = "--choose-terminal" ]; then
    if [ "${#AVAILABLE_TERMINALS[@]}" -eq 0 ]; then
        echo "No supported terminal app found." >&2
        exit 1
    fi

    if CHOICE="$(pick_terminal_interactively "${AVAILABLE_TERMINALS[@]}")"; then
        mkdir -p "$CONFIG_DIR"
        printf '%s\n' "$CHOICE" > "$TERMINAL_FILE"
        echo "Saved terminal preference: $CHOICE"
        exit 0
    fi

    echo "No terminal selected." >&2
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

SELECTED_TERMINAL="$(choose_terminal "${AVAILABLE_TERMINALS[@]}")"

if [ -n "$SELECTED_TERMINAL" ] && run_in_terminal "$SELECTED_TERMINAL"; then
    exit 0
fi

for term in "${AVAILABLE_TERMINALS[@]}"; do
    [ "$term" = "$SELECTED_TERMINAL" ] && continue
    if run_in_terminal "$term"; then
        mkdir -p "$CONFIG_DIR"
        printf '%s\n' "$term" > "$TERMINAL_FILE"
        exit 0
    fi
done

notify-send "Ubuntu Automation" "Could not open a terminal window."
exit 1
