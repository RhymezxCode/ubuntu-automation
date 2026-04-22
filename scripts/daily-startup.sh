#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

TIMEOUT_SECS=30
NET_TIMEOUT_SECS=60

# Cache sudo credentials upfront so password prompt doesn't collide with spinners
sudo -v 2>/dev/null

divider() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${spin:i++%${#spin}:1}${NC} %s" "$msg"
        sleep 0.1
    done
    printf "\r"
}

run_with_timeout() {
    local timeout=$1
    local label=$2
    shift 2
    local cmd=("$@")
    local tmpfile
    tmpfile=$(mktemp)

    "${cmd[@]}" >"$tmpfile" 2>&1 &
    local pid=$!

    spinner "$pid" "$label" &
    local spinner_pid=$!

    local elapsed=0
    while kill -0 "$pid" 2>/dev/null && [ "$elapsed" -lt "$timeout" ]; do
        sleep 1
        elapsed=$((elapsed + 1))
    done

    kill "$spinner_pid" 2>/dev/null
    wait "$spinner_pid" 2>/dev/null
    printf "\r"

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        echo -e "  ${RED}✗ ${label} — timed out after ${timeout}s${NC}"
        rm -f "$tmpfile"
        return 124
    fi

    wait "$pid"
    local exit_code=$?
    local output
    output=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ]; then
        echo -e "  ${RED}✗ ${label} — failed (exit $exit_code)${NC}"
        if [ -n "$output" ]; then
            echo "$output" | tail -3 | sed 's/^/    /'
        fi
        return $exit_code
    fi

    echo -n "$output"
    return 0
}

check_internet() {
    if timeout 5 ping -c 1 8.8.8.8 &>/dev/null; then
        return 0
    elif timeout 5 ping -c 1 1.1.1.1 &>/dev/null; then
        return 0
    fi
    return 1
}

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║         DAILY STARTUP MAINTENANCE            ║"
echo "  ║    ThinkPad X1 Carbon 6th · Ubuntu 26.04     ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  $(date '+%A, %B %d %Y · %I:%M %p')"

# ─────────────────────────────────────────────────
# INTERNET CONNECTIVITY CHECK
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} CONNECTIVITY${NC}"
echo ""

HAS_INTERNET=0
if check_internet; then
    HAS_INTERNET=1
    echo -e "  ${GREEN}✓${NC} Internet is reachable"
else
    echo -e "  ${RED}✗ No internet detected — network tasks will be skipped${NC}"
    echo -e "  ${DIM}  Run 'morning' again once you're connected${NC}"
fi

# ─────────────────────────────────────────────────
# SYSTEM HEALTH CHECK
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} SYSTEM HEALTH${NC}"
echo ""

UPTIME=$(uptime -p)
LOAD=$(awk '{print $1}' /proc/loadavg)
echo -e "  Uptime:       ${UPTIME}"
echo -e "  Load avg:     ${LOAD}"

MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/Mem:/ {print $3}')
MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
if [ "$MEM_PCT" -gt 85 ]; then
    MEM_COLOR=$RED
elif [ "$MEM_PCT" -gt 60 ]; then
    MEM_COLOR=$YELLOW
else
    MEM_COLOR=$GREEN
fi
echo -e "  RAM:          ${MEM_COLOR}${MEM_USED} / ${MEM_TOTAL} (${MEM_PCT}%)${NC}"

SWAP_TOTAL=$(free -h | awk '/Swap:/ {print $2}')
SWAP_USED=$(free -h | awk '/Swap:/ {print $3}')
SWAP_PCT=$(free | awk '/Swap:/ {if($2>0) printf "%.0f", $3/$2*100; else print "0"}')
if [ "$SWAP_PCT" -gt 50 ]; then
    SWAP_COLOR=$RED
elif [ "$SWAP_PCT" -gt 25 ]; then
    SWAP_COLOR=$YELLOW
else
    SWAP_COLOR=$GREEN
fi
echo -e "  Swap:         ${SWAP_COLOR}${SWAP_USED} / ${SWAP_TOTAL} (${SWAP_PCT}%)${NC}"

DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
if [ "$DISK_PCT" -gt 85 ]; then
    DISK_COLOR=$RED
elif [ "$DISK_PCT" -gt 70 ]; then
    DISK_COLOR=$YELLOW
else
    DISK_COLOR=$GREEN
fi
echo -e "  Disk:         ${DISK_COLOR}${DISK_PCT}% used (${DISK_AVAIL} free)${NC}"

if command -v sensors &>/dev/null; then
    CPU_TEMP=$(sensors 2>/dev/null | grep "Package id 0" | awk '{print $4}' | tr -d '+')
    if [ -n "$CPU_TEMP" ]; then
        TEMP_VAL=$(echo "$CPU_TEMP" | tr -d '°C' | cut -d. -f1)
        if [ "$TEMP_VAL" -gt 80 ]; then
            TEMP_COLOR=$RED
        elif [ "$TEMP_VAL" -gt 65 ]; then
            TEMP_COLOR=$YELLOW
        else
            TEMP_COLOR=$GREEN
        fi
        echo -e "  CPU Temp:     ${TEMP_COLOR}${CPU_TEMP}${NC}"
    fi
fi

BAT_PCT=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null | grep percentage | awk '{print $2}')
BAT_STATE=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null | grep state | awk '{print $2}')
BAT_HEALTH=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null | grep capacity | awk '{print $2}')
if [ -n "$BAT_PCT" ]; then
    echo -e "  Battery:      ${BAT_PCT} (${BAT_STATE}) · Health: ${BAT_HEALTH}"
fi

# ─────────────────────────────────────────────────
# FREE UP MEMORY (kill leftover daemons)
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} MEMORY CLEANUP${NC}"
echo ""

GRADLE_KILLED=0
if pgrep -f "GradleDaemon" &>/dev/null; then
    pkill -f "GradleDaemon" 2>/dev/null
    GRADLE_KILLED=1
    echo -e "  ${GREEN}✓${NC} Killed leftover Gradle daemons"
fi

KOTLIN_KILLED=0
if pgrep -f "KotlinCompileDaemon" &>/dev/null; then
    pkill -f "KotlinCompileDaemon" 2>/dev/null
    KOTLIN_KILLED=1
    echo -e "  ${GREEN}✓${NC} Killed leftover Kotlin daemons"
fi

if [ "$GRADLE_KILLED" -eq 0 ] && [ "$KOTLIN_KILLED" -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} No leftover daemons found"
fi

# ─────────────────────────────────────────────────
# NETWORK-DEPENDENT TASKS (only if internet is up)
# ─────────────────────────────────────────────────
if [ "$HAS_INTERNET" -eq 1 ]; then

    # ─────────────────────────────────────────────
    # UPDATE APT PACKAGES
    # ─────────────────────────────────────────────
    divider
    echo -e "${BOLD} APT PACKAGES${NC}"
    echo ""

    if run_with_timeout "$NET_TIMEOUT_SECS" "Updating package lists..." sudo apt update -qq; then
        UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
        if [ "$UPGRADABLE" -gt 0 ]; then
            echo -e "  ${YELLOW}${UPGRADABLE} packages can be upgraded${NC}"
            read -t 30 -p "  Upgrade now? [Y/n]: " APT_ANSWER
            APT_ANSWER=${APT_ANSWER:-Y}
            if [[ "$APT_ANSWER" =~ ^[Yy]$ ]]; then
                echo -e "  ${DIM}Running apt upgrade...${NC}"
                sudo apt upgrade -y 2>&1 | tail -5 | sed 's/^/  /'
                sudo apt autoremove -y -qq 2>/dev/null
                echo -e "  ${GREEN}✓${NC} APT packages upgraded"
            else
                echo -e "  ${YELLOW}⏭${NC}  Skipped"
            fi
        else
            echo -e "  ${GREEN}✓${NC} All APT packages are up to date"
        fi
    fi

    # ─────────────────────────────────────────────
    # UPDATE SNAP PACKAGES
    # ─────────────────────────────────────────────
    divider
    echo -e "${BOLD} SNAP PACKAGES${NC}"
    echo ""

    SNAP_OUTPUT=$(mktemp)
    if run_with_timeout "$NET_TIMEOUT_SECS" "Checking for snap updates..." sudo snap refresh --list > "$SNAP_OUTPUT" 2>&1; then
        SNAP_UPDATES=$(tail -n +2 "$SNAP_OUTPUT")
    else
        SNAP_UPDATES=""
    fi
    rm -f "$SNAP_OUTPUT"

    if [ -n "$SNAP_UPDATES" ]; then
        SNAP_COUNT=$(echo "$SNAP_UPDATES" | wc -l)
        echo -e "  ${YELLOW}${SNAP_COUNT} snaps can be updated:${NC}"
        echo "$SNAP_UPDATES" | awk '{printf "    - %s (%s → %s)\n", $1, $2, $3}'
        read -t 30 -p "  Update now? [Y/n]: " SNAP_ANSWER
        SNAP_ANSWER=${SNAP_ANSWER:-Y}
        if [[ "$SNAP_ANSWER" =~ ^[Yy]$ ]]; then
            echo -e "  ${DIM}Refreshing snaps...${NC}"
            sudo snap refresh 2>&1 | tail -5 | sed 's/^/  /'
            echo -e "  ${GREEN}✓${NC} Snaps updated"
        else
            echo -e "  ${YELLOW}⏭${NC}  Skipped"
        fi
    else
        echo -e "  ${GREEN}✓${NC} All snaps are up to date"
    fi

    # ─────────────────────────────────────────────
    # UPDATE NPM GLOBAL PACKAGES
    # ─────────────────────────────────────────────
    if command -v npm &>/dev/null; then
        divider
        echo -e "${BOLD} NPM GLOBAL PACKAGES${NC}"
        echo ""

        NPM_OUTPUT=$(mktemp)
        if run_with_timeout "$TIMEOUT_SECS" "Checking npm globals..." npm outdated -g > "$NPM_OUTPUT" 2>&1; then
            OUTDATED_NPM=$(cat "$NPM_OUTPUT")
        else
            OUTDATED_NPM=""
        fi
        rm -f "$NPM_OUTPUT"

        if [ -n "$OUTDATED_NPM" ]; then
            echo -e "  ${YELLOW}Outdated global npm packages:${NC}"
            echo "$OUTDATED_NPM" | head -10 | sed 's/^/    /'
            read -t 30 -p "  Update now? [Y/n]: " NPM_ANSWER
            NPM_ANSWER=${NPM_ANSWER:-Y}
            if [[ "$NPM_ANSWER" =~ ^[Yy]$ ]]; then
                echo -e "  ${DIM}Updating npm globals...${NC}"
                sudo npm update -g 2>&1 | tail -5 | sed 's/^/  /'
                echo -e "  ${GREEN}✓${NC} NPM globals updated"
            else
                echo -e "  ${YELLOW}⏭${NC}  Skipped"
            fi
        else
            echo -e "  ${GREEN}✓${NC} All npm globals are up to date"
        fi
    fi

    # ─────────────────────────────────────────────
    # FIRMWARE UPDATES
    # ─────────────────────────────────────────────
    if command -v fwupdmgr &>/dev/null; then
        divider
        echo -e "${BOLD} FIRMWARE${NC}"
        echo ""

        if run_with_timeout "$TIMEOUT_SECS" "Refreshing firmware metadata..." fwupdmgr refresh --force; then
            FW_OUTPUT=$(mktemp)
            if run_with_timeout "$TIMEOUT_SECS" "Checking for firmware updates..." fwupdmgr get-updates > "$FW_OUTPUT" 2>&1; then
                FW_UPDATES=$(cat "$FW_OUTPUT")
            else
                FW_UPDATES=""
            fi
            rm -f "$FW_OUTPUT"

            if echo "$FW_UPDATES" | grep -q "No upgrades"; then
                echo -e "  ${GREEN}✓${NC} Firmware is up to date"
            elif [ -n "$FW_UPDATES" ]; then
                echo -e "  ${YELLOW}Firmware updates available!${NC}"
                echo "$FW_UPDATES" | grep -E "(Name|Version)" | head -10 | sed 's/^/    /'
                read -t 30 -p "  Update firmware? [y/N]: " FW_ANSWER
                FW_ANSWER=${FW_ANSWER:-N}
                if [[ "$FW_ANSWER" =~ ^[Yy]$ ]]; then
                    fwupdmgr update
                    echo -e "  ${GREEN}✓${NC} Firmware updated (may need reboot)"
                else
                    echo -e "  ${YELLOW}⏭${NC}  Skipped"
                fi
            else
                echo -e "  ${GREEN}✓${NC} Firmware is up to date"
            fi
        fi
    fi

    # ─────────────────────────────────────────────
    # ANDROID SDK UPDATES
    # ─────────────────────────────────────────────
    if [ -f "$HOME/Android/Sdk/cmdline-tools/latest/bin/sdkmanager" ]; then
        divider
        echo -e "${BOLD} ANDROID SDK${NC}"
        echo ""

        SDK_OUTPUT=$(mktemp)
        if run_with_timeout "$NET_TIMEOUT_SECS" "Checking for SDK updates..." "$HOME/Android/Sdk/cmdline-tools/latest/bin/sdkmanager" --list > "$SDK_OUTPUT" 2>&1; then
            SDK_UPDATES=$(grep "Available Updates" -A 100 "$SDK_OUTPUT" | tail -n +3)
        else
            SDK_UPDATES=""
        fi
        rm -f "$SDK_OUTPUT"

        if [ -n "$SDK_UPDATES" ] && ! echo "$SDK_UPDATES" | grep -q "^$"; then
            echo -e "  ${YELLOW}SDK updates available:${NC}"
            echo "$SDK_UPDATES" | head -10 | sed 's/^/    /'
            read -t 30 -p "  Update SDK? [Y/n]: " SDK_ANSWER
            SDK_ANSWER=${SDK_ANSWER:-Y}
            if [[ "$SDK_ANSWER" =~ ^[Yy]$ ]]; then
                echo -e "  ${DIM}Updating SDK...${NC}"
                yes | "$HOME/Android/Sdk/cmdline-tools/latest/bin/sdkmanager" --update 2>&1 | tail -5 | sed 's/^/  /'
                echo -e "  ${GREEN}✓${NC} Android SDK updated"
            else
                echo -e "  ${YELLOW}⏭${NC}  Skipped"
            fi
        else
            echo -e "  ${GREEN}✓${NC} Android SDK is up to date"
        fi
    fi

else
    divider
    echo -e "${DIM}  Skipped: APT, Snap, NPM, Firmware, SDK (no internet)${NC}"
fi

# ─────────────────────────────────────────────────
# QUICK CLEANUP
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} QUICK CLEANUP${NC}"
echo ""

GRADLE_CACHE_SIZE=$(du -sm ~/.gradle/caches/build-cache-* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
if [ "$GRADLE_CACHE_SIZE" -gt 500 ]; then
    echo -e "  ${YELLOW}Gradle build cache: ${GRADLE_CACHE_SIZE}MB${NC}"
    read -t 30 -p "  Clean it? [Y/n]: " GRADLE_ANSWER
    GRADLE_ANSWER=${GRADLE_ANSWER:-Y}
    if [[ "$GRADLE_ANSWER" =~ ^[Yy]$ ]]; then
        rm -rf ~/.gradle/caches/build-cache-*
        echo -e "  ${GREEN}✓${NC} Gradle build cache cleaned"
    fi
else
    echo -e "  ${GREEN}✓${NC} Gradle cache is small (${GRADLE_CACHE_SIZE}MB)"
fi

JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[MG]')
echo -e "  Journal logs: ${JOURNAL_SIZE}"
sudo journalctl --vacuum-time=7d --vacuum-size=200M 2>&1 | tail -1 | sed 's/^/  /'

KERN_COUNT=$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)
if [ "$KERN_COUNT" -gt 2 ]; then
    echo -e "  ${YELLOW}${KERN_COUNT} kernels installed (consider removing old ones)${NC}"
fi

# ─────────────────────────────────────────────────
# SERVICE STATUS CHECK
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} PERFORMANCE SERVICES${NC}"
echo ""

for SVC in tlp thermald earlyoom preload zramswap; do
    STATUS=$(systemctl is-active "$SVC" 2>/dev/null)
    if [ "$STATUS" = "active" ]; then
        echo -e "  ${GREEN}✓${NC} ${SVC}"
    else
        echo -e "  ${RED}✗${NC} ${SVC} (${STATUS})"
    fi
done

# ─────────────────────────────────────────────────
# SECURITY CHECK
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} SECURITY${NC}"
echo ""

REBOOT_REQUIRED=""
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=1
    echo -e "  ${RED}⚠ System reboot required (kernel/security update)${NC}"
fi

FAILED_LOGINS=$(journalctl -q --since "24 hours ago" 2>/dev/null | grep -c "authentication failure" 2>/dev/null || echo 0)
if [ "$FAILED_LOGINS" -gt 0 ]; then
    echo -e "  ${YELLOW}${FAILED_LOGINS} failed login attempts in last 24h${NC}"
else
    echo -e "  ${GREEN}✓${NC} No failed login attempts"
fi

echo -e "  ${GREEN}✓${NC} Security check done"

# ─────────────────────────────────────────────────
# TOP MEMORY CONSUMERS
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} TOP MEMORY CONSUMERS${NC}"
echo ""
ps aux --sort=-%mem | awk 'NR>1 && NR<=6 {printf "  %-6s %s\n", $4"%", $11}' | head -5

# ─────────────────────────────────────────────────
# FINAL APT CLEANUP
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} FINAL APT CLEANUP${NC}"
echo ""

sudo apt-get autoremove -y -qq 2>/dev/null
echo -e "  ${GREEN}✓${NC} apt-get autoremove done"

sudo apt-get autoclean -qq 2>/dev/null
echo -e "  ${GREEN}✓${NC} apt-get autoclean done"

# ─────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────
divider
echo ""
echo -e "${BOLD}  All done!${NC} Your system is ready."

if [ "$HAS_INTERNET" -eq 0 ]; then
    echo ""
    echo -e "  ${YELLOW}→ Network tasks were skipped. Run 'morning' again when online.${NC}"
fi

if [ -n "$REBOOT_REQUIRED" ]; then
    echo ""
    echo -e "  ${RED}→ Don't forget to reboot when convenient.${NC}"
fi

echo ""

# Post-run summary notification
if command -v notify-send &>/dev/null; then
    _DISK_FREE=$(df -h / --output=avail | tail -1 | tr -d ' ')
    _REBOOT_NOTE=""
    [ -n "$REBOOT_REQUIRED" ] && _REBOOT_NOTE=" · Reboot needed"
    notify-send "✅  Morning Done" "System ready · ${_DISK_FREE} free${_REBOOT_NOTE}" \
        --icon=computer --app-name="Daily Maintenance" --expire-time=8000 2>/dev/null || true
fi
