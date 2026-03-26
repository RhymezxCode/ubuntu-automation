#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Cache sudo credentials upfront so password prompt doesn't collide with spinners
sudo -v 2>/dev/null

divider() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

bytes_to_human() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}")GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.0f\", $bytes/1048576}")MB"
    else
        echo "$(awk "BEGIN {printf \"%.0f\", $bytes/1024}")KB"
    fi
}

tool_version() {
    local name=$1
    local cmd=$2
    local version
    version=$(eval "$cmd" 2>/dev/null)
    if [ -n "$version" ]; then
        echo -e "  ${GREEN}✓${NC} ${name}: ${version}"
    else
        echo -e "  ${DIM}✗ ${name}: not installed${NC}"
    fi
}

FLAGS=0

flag() {
    local msg=$1
    FLAGS=$((FLAGS + 1))
    echo -e "  ${RED}⚠ ${msg}${NC}"
}

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║              PC AUDIT REPORT                 ║"
echo "  ║   ThinkPad X1 Carbon 6th · Ubuntu 24.04      ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  $(date '+%A, %B %d %Y · %I:%M %p')"

# ─────────────────────────────────────────────────
# 1. SYSTEM IDENTITY
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 1. SYSTEM IDENTITY${NC}"
echo ""

echo -e "  Hostname:     $(hostname)"
echo -e "  Username:     $(whoami)"

if [ -f /etc/os-release ]; then
    OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release | cut -d'"' -f2)
    echo -e "  OS:           ${OS_NAME}"
fi

echo -e "  Kernel:       $(uname -r)"
echo -e "  Arch:         $(uname -m)"

MACHINE_MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "Unknown")
MACHINE_VERSION=$(cat /sys/devices/virtual/dmi/id/product_version 2>/dev/null)
if [ -n "$MACHINE_VERSION" ]; then
    echo -e "  Machine:      ${MACHINE_MODEL} (${MACHINE_VERSION})"
else
    echo -e "  Machine:      ${MACHINE_MODEL}"
fi

BIOS_VERSION=$(sudo dmidecode -s bios-version 2>/dev/null)
BIOS_DATE=$(sudo dmidecode -s bios-release-date 2>/dev/null)
if [ -n "$BIOS_VERSION" ]; then
    echo -e "  BIOS:         ${BIOS_VERSION} (${BIOS_DATE})"
fi

# ─────────────────────────────────────────────────
# 2. HARDWARE
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 2. HARDWARE${NC}"
echo ""

echo -e "  ${BOLD}CPU${NC}"
CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | sed 's/Model name:[[:space:]]*//')
CPU_CORES=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
CPU_THREADS=$(lscpu 2>/dev/null | grep "Thread(s) per core" | awk '{print $4}')
CPU_SOCKETS=$(lscpu 2>/dev/null | grep "Socket(s)" | awk '{print $2}')
CPU_MAX_MHZ=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{printf "%.1f GHz", $4/1000}')
CPU_ARCH=$(lscpu 2>/dev/null | grep "Architecture" | awk '{print $2}')
TOTAL_THREADS=$((CPU_CORES))
echo -e "    Model:      ${CPU_MODEL}"
echo -e "    Cores:      ${CPU_CORES} (${CPU_THREADS} threads/core)"
if [ -n "$CPU_MAX_MHZ" ]; then
    echo -e "    Max freq:   ${CPU_MAX_MHZ}"
fi
echo -e "    Arch:       ${CPU_ARCH}"

echo ""
echo -e "  ${BOLD}RAM${NC}"
MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/Mem:/ {print $3}')
MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
echo -e "    Total:      ${MEM_TOTAL}"
echo -e "    Used:       ${MEM_USED} (${MEM_PCT}%)"

RAM_TYPE=$(sudo dmidecode -t memory 2>/dev/null | grep "Type:" | grep -v "Error\|Unknown" | head -1 | awk '{print $2}')
RAM_SPEED=$(sudo dmidecode -t memory 2>/dev/null | grep "Configured Memory Speed" | head -1 | awk '{print $4, $5}')
RAM_SLOTS_TOTAL=$(sudo dmidecode -t memory 2>/dev/null | grep -c "Size:")
RAM_SLOTS_USED=$(sudo dmidecode -t memory 2>/dev/null | grep "Size:" | grep -vc "No Module")
if [ -n "$RAM_TYPE" ]; then
    echo -e "    Type:       ${RAM_TYPE} @ ${RAM_SPEED}"
fi
if [ -n "$RAM_SLOTS_TOTAL" ] && [ "$RAM_SLOTS_TOTAL" -gt 0 ]; then
    echo -e "    Slots:      ${RAM_SLOTS_USED}/${RAM_SLOTS_TOTAL} used"
fi

echo ""
echo -e "  ${BOLD}GPU${NC}"
GPU_INFO=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | sed 's/.*: //')
if [ -n "$GPU_INFO" ]; then
    echo "$GPU_INFO" | while read -r gpu; do
        echo -e "    ${gpu}"
    done
else
    echo -e "    ${DIM}No GPU detected${NC}"
fi

echo ""
echo -e "  ${BOLD}Disks${NC}"
lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | while read -r line; do
    if echo "$line" | grep -q "disk"; then
        DNAME=$(echo "$line" | awk '{print $1}')
        DSIZE=$(echo "$line" | awk '{print $2}')
        DTRAN=$(echo "$line" | awk '{print $4}')
        DMODEL=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
        ROTATIONAL=$(cat /sys/block/"$DNAME"/queue/rotational 2>/dev/null)
        if [ "$ROTATIONAL" = "0" ]; then
            DTYPE="SSD"
        else
            DTYPE="HDD"
        fi
        echo -e "    /dev/${DNAME}: ${DSIZE} ${DTYPE} (${DTRAN}) ${DMODEL}"
    fi
done

echo ""
echo -e "  ${BOLD}Battery${NC}"
BAT_INFO=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null)
if [ -n "$BAT_INFO" ]; then
    BAT_PCT=$(echo "$BAT_INFO" | grep percentage | awk '{print $2}')
    BAT_STATE=$(echo "$BAT_INFO" | grep "state:" | awk '{print $2}')
    BAT_HEALTH=$(echo "$BAT_INFO" | grep "capacity:" | awk '{print $2}')
    BAT_ENERGY_FULL=$(echo "$BAT_INFO" | grep "energy-full:" | awk '{print $2, $3}')
    BAT_ENERGY_DESIGN=$(echo "$BAT_INFO" | grep "energy-full-design:" | awk '{print $2, $3}')
    BAT_CYCLES=$(echo "$BAT_INFO" | grep "charge-cycles:" | awk '{print $2}')
    BAT_TECH=$(echo "$BAT_INFO" | grep "technology:" | awk '{print $2}')
    echo -e "    Charge:     ${BAT_PCT} (${BAT_STATE})"
    echo -e "    Health:     ${BAT_HEALTH}"
    echo -e "    Capacity:   ${BAT_ENERGY_FULL} / ${BAT_ENERGY_DESIGN} (design)"
    if [ -n "$BAT_CYCLES" ] && [ "$BAT_CYCLES" != "0" ]; then
        echo -e "    Cycles:     ${BAT_CYCLES}"
    fi
    if [ -n "$BAT_TECH" ]; then
        echo -e "    Type:       ${BAT_TECH}"
    fi
else
    echo -e "    ${DIM}No battery detected${NC}"
fi

echo ""
echo -e "  ${BOLD}Network Adapters${NC}"
WIFI=$(lspci 2>/dev/null | grep -i "network\|wireless" | sed 's/.*: //')
ETH=$(lspci 2>/dev/null | grep -i "ethernet" | sed 's/.*: //')
if [ -n "$WIFI" ]; then
    echo -e "    Wi-Fi:      ${WIFI}"
fi
if [ -n "$ETH" ]; then
    echo -e "    Ethernet:   ${ETH}"
fi
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$IP_ADDR" ]; then
    echo -e "    Local IP:   ${IP_ADDR}"
fi

echo ""
echo -e "  ${BOLD}USB Devices${NC}"
USB_DEVICES=$(lsusb 2>/dev/null)
if [ -n "$USB_DEVICES" ]; then
    echo "$USB_DEVICES" | while read -r usbline; do
        UDEV=$(echo "$usbline" | sed 's/Bus [0-9]* Device [0-9]*: ID [a-f0-9:]* //')
        echo -e "    - ${UDEV}"
    done
else
    echo -e "    ${DIM}No USB devices detected${NC}"
fi

# ─────────────────────────────────────────────────
# 3. SOFTWARE & VERSIONS
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 3. SOFTWARE & VERSIONS${NC}"
echo ""

echo -e "  ${BOLD}System${NC}"
echo -e "  Kernel:       $(uname -r)"

DE="${XDG_CURRENT_DESKTOP:-Unknown}"
echo -e "  Desktop:      ${DE}"

SESSION_TYPE="${XDG_SESSION_TYPE:-Unknown}"
echo -e "  Display:      ${SESSION_TYPE}"

echo -e "  Shell:        ${SHELL} ($(bash --version | head -1 | grep -oP '\d+\.\d+\.\d+'))"

echo ""
echo -e "  ${BOLD}Dev Tools${NC}"
tool_version "Git" "git --version | awk '{print \$3}'"
tool_version "Java" "java --version 2>&1 | head -1"
tool_version "Kotlin" "kotlin -version 2>&1 | grep -oP 'kotlinc-jvm \K[\d.]+'"
tool_version "Node.js" "node --version"
tool_version "npm" "npm --version"
tool_version "Python3" "python3 --version | awk '{print \$2}'"
tool_version "pip3" "pip3 --version 2>/dev/null | awk '{print \$2}'"
tool_version "Flutter" "flutter --version 2>/dev/null | head -1 | awk '{print \$2}'"
tool_version "Dart" "dart --version 2>&1 | grep -oP 'Dart SDK version: \K[\d.]+'"
tool_version "Docker" "docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+'"
tool_version "ADB" "adb --version | head -1 | grep -oP '[\d.]+'"
tool_version "Gradle" "gradle --version 2>/dev/null | grep 'Gradle' | awk '{print \$2}'"
tool_version "Go" "go version 2>/dev/null | awk '{print \$3}' | sed 's/go//'"
tool_version "Rust" "rustc --version 2>/dev/null | awk '{print \$2}'"
tool_version "GCC" "gcc --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+'"

AS_DIR=$(ls -d ~/.local/share/JetBrains/Toolbox/apps/android-studio* 2>/dev/null | head -1)
if [ -n "$AS_DIR" ]; then
    AS_VER=$(basename "$AS_DIR" | sed 's/android-studio-*//')
    echo -e "  ${GREEN}✓${NC} Android Studio: installed"
else
    echo -e "  ${DIM}✗ Android Studio: not found${NC}"
fi

if command -v cursor &>/dev/null || [ -d "/usr/share/cursor" ] || [ -d "$HOME/.cursor" ]; then
    echo -e "  ${GREEN}✓${NC} Cursor: installed"
else
    echo -e "  ${DIM}✗ Cursor: not found${NC}"
fi

echo ""
echo -e "  ${BOLD}Package Counts${NC}"
APT_COUNT=$(dpkg --get-selections 2>/dev/null | grep -c "install$")
echo -e "  APT packages:   ${APT_COUNT}"

SNAP_COUNT=$(snap list 2>/dev/null | tail -n +2 | wc -l)
echo -e "  Snap packages:  ${SNAP_COUNT}"

if command -v flatpak &>/dev/null; then
    FLATPAK_COUNT=$(flatpak list 2>/dev/null | wc -l)
    echo -e "  Flatpak apps:   ${FLATPAK_COUNT}"
fi

# ─────────────────────────────────────────────────
# 4. STORAGE BREAKDOWN
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 4. STORAGE BREAKDOWN${NC}"
echo ""

echo -e "  ${BOLD}Partitions${NC}"
echo ""
df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk '
NR==1 {printf "    %-20s %6s %6s %6s %5s  %s\n", "Filesystem", "Size", "Used", "Avail", "Use%", "Mount"}
NR>1  {
    pct = $5 + 0
    printf "    %-20s %6s %6s %6s %5s  %s\n", $1, $2, $3, $4, $5, $6
}'

echo ""
echo -e "  ${BOLD}Swap${NC}"
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
echo -e "    ${SWAP_COLOR}${SWAP_USED} / ${SWAP_TOTAL} (${SWAP_PCT}%)${NC}"

echo ""
echo -e "  ${BOLD}Top 10 Directories in \$HOME${NC}"
echo -e "  ${DIM}(scanning, may take a moment...)${NC}"
du -sh ~/*/  ~/.*/  2>/dev/null | sort -rh | head -10 | while read -r size dir; do
    short=$(echo "$dir" | sed "s|$HOME|~|")
    echo -e "    ${YELLOW}${size}${NC}\t${short}"
done

# ─────────────────────────────────────────────────
# 5. PERFORMANCE
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 5. PERFORMANCE${NC}"
echo ""

UPTIME=$(uptime -p)
LOAD=$(awk '{printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg)
echo -e "  Uptime:       ${UPTIME}"
echo -e "  Load avg:     ${LOAD} (1m, 5m, 15m)"

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

if command -v systemd-analyze &>/dev/null; then
    BOOT_TIME=$(systemd-analyze 2>/dev/null | head -1 | grep -oP 'reached .* = .*' | sed 's/reached .* = //')
    if [ -n "$BOOT_TIME" ]; then
        echo -e "  Boot time:    ${BOOT_TIME}"
    fi
fi

echo ""
echo -e "  ${BOLD}Top 5 CPU Consumers${NC}"
ps aux --sort=-%cpu | awk 'NR>1 && NR<=6 {printf "    %-6s %s\n", $3"%", $11}' | head -5

echo ""
echo -e "  ${BOLD}Top 5 Memory Consumers${NC}"
ps aux --sort=-%mem | awk 'NR>1 && NR<=6 {printf "    %-6s %s\n", $4"%", $11}' | head -5

echo ""
echo -e "  ${BOLD}Systemd Services${NC}"
TOTAL_SERVICES=$(systemctl list-units --type=service --no-legend 2>/dev/null | wc -l)
RUNNING_SERVICES=$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l)
FAILED_SERVICES=$(systemctl list-units --type=service --state=failed --no-legend 2>/dev/null)
FAILED_COUNT=$(echo "$FAILED_SERVICES" | grep -c "failed" 2>/dev/null || echo 0)

echo -e "    Total:      ${TOTAL_SERVICES} loaded"
echo -e "    Running:    ${RUNNING_SERVICES}"

if [ "$FAILED_COUNT" -gt 0 ]; then
    echo -e "    ${RED}Failed:     ${FAILED_COUNT}${NC}"
    echo "$FAILED_SERVICES" | awk '{print "      - " $1}' | head -10
else
    echo -e "    ${GREEN}Failed:     0${NC}"
fi

# ─────────────────────────────────────────────────
# 6. SECURITY
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 6. SECURITY${NC}"
echo ""

echo -e "  ${BOLD}Firewall${NC}"
UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1)
if echo "$UFW_STATUS" | grep -q "active"; then
    echo -e "    ${GREEN}✓${NC} UFW is active"
    sudo ufw status numbered 2>/dev/null | grep -E "^\[" | head -10 | sed 's/^/    /'
elif echo "$UFW_STATUS" | grep -q "inactive"; then
    echo -e "    ${RED}✗${NC} UFW is inactive"
    flag "Firewall is not enabled"
else
    echo -e "    ${DIM}UFW not available${NC}"
fi

echo ""
echo -e "  ${BOLD}Open Listening Ports${NC}"
PORTS=$(sudo ss -tlnp 2>/dev/null | tail -n +2)
if [ -n "$PORTS" ]; then
    PORT_COUNT=$(echo "$PORTS" | wc -l)
    echo -e "    ${PORT_COUNT} ports listening:"
    echo "$PORTS" | awk '{printf "      %-25s %s\n", $4, $7}' | sed 's/users:(("/  /;s/".*//' | head -15
else
    echo -e "    ${GREEN}✓${NC} No listening ports"
fi

echo ""
echo -e "  ${BOLD}Failed Login Attempts (7 days)${NC}"
FAILED_LOGINS=$(journalctl -q --since "7 days ago" 2>/dev/null | grep -c "authentication failure" 2>/dev/null || echo 0)
if [ "$FAILED_LOGINS" -gt 10 ]; then
    echo -e "    ${RED}${FAILED_LOGINS} failed attempts${NC}"
    flag "${FAILED_LOGINS} failed login attempts in last 7 days"
elif [ "$FAILED_LOGINS" -gt 0 ]; then
    echo -e "    ${YELLOW}${FAILED_LOGINS} failed attempts${NC}"
else
    echo -e "    ${GREEN}✓${NC} No failed login attempts"
fi

echo ""
echo -e "  ${BOLD}Users with Login Shells${NC}"
LOGIN_USERS=$(grep -vE '(nologin|false|sync|halt|shutdown)$' /etc/passwd 2>/dev/null | cut -d: -f1,7)
if [ -n "$LOGIN_USERS" ]; then
    echo "$LOGIN_USERS" | while IFS=: read -r user shell; do
        echo -e "    - ${user} (${shell})"
    done
fi

echo ""
echo -e "  ${BOLD}SSH Configuration${NC}"
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    ROOT_LOGIN=$(grep -i "^PermitRootLogin" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
    PASS_AUTH=$(grep -i "^PasswordAuthentication" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')

    if [ -z "$ROOT_LOGIN" ]; then
        ROOT_LOGIN="(default: prohibit-password)"
    fi
    if [ -z "$PASS_AUTH" ]; then
        PASS_AUTH="(default: yes)"
    fi

    if [ "$ROOT_LOGIN" = "yes" ]; then
        echo -e "    ${RED}✗${NC} Root login: ${ROOT_LOGIN}"
        flag "SSH root login is enabled"
    else
        echo -e "    ${GREEN}✓${NC} Root login: ${ROOT_LOGIN}"
    fi

    if [ "$PASS_AUTH" = "yes" ] || [ "$PASS_AUTH" = "(default: yes)" ]; then
        echo -e "    ${YELLOW}!${NC} Password auth: ${PASS_AUTH}"
    else
        echo -e "    ${GREEN}✓${NC} Password auth: ${PASS_AUTH}"
    fi
else
    echo -e "    ${DIM}SSH server not installed${NC}"
fi

echo ""
echo -e "  ${BOLD}Pending Security Updates${NC}"
SEC_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i "security" | wc -l)
ALL_UPDATES=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
if [ "$SEC_UPDATES" -gt 0 ]; then
    echo -e "    ${RED}${SEC_UPDATES} security updates pending${NC}"
    flag "${SEC_UPDATES} pending security updates"
else
    echo -e "    ${GREEN}✓${NC} No pending security updates"
fi
if [ "$ALL_UPDATES" -gt 0 ]; then
    echo -e "    ${YELLOW}${ALL_UPDATES} total updates available${NC}"
fi

echo ""
echo -e "  ${BOLD}Reboot Required${NC}"
if [ -f /var/run/reboot-required ]; then
    echo -e "    ${RED}⚠ System reboot required${NC}"
    flag "System reboot required"
else
    echo -e "    ${GREEN}✓${NC} No reboot required"
fi

# ─────────────────────────────────────────────────
# 7. SUMMARY
# ─────────────────────────────────────────────────
divider
echo ""

if [ "$FLAGS" -gt 0 ]; then
    echo -e "${BOLD}  Audit complete.${NC} ${RED}${FLAGS} issue(s) flagged.${NC}"
    echo ""
    echo -e "  ${YELLOW}Review the red flags above and take action if needed.${NC}"
else
    echo -e "${BOLD}  Audit complete.${NC} ${GREEN}No issues found — system looks healthy!${NC}"
fi

echo ""
