#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USERNAME=$(whoami)
HOME_DIR="$HOME"

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║      Ubuntu Automation Toolkit Installer      ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. Copy scripts
echo -e "${BOLD}[1/5] Installing scripts to ~/...${NC}"
for script in daily-startup.sh deep-clean.sh pc-audit.sh morning-notify.sh deepclean-notify.sh; do
    if [ -f "$HOME_DIR/$script" ]; then
        echo -e "  ${YELLOW}~/$script already exists. Overwrite? [y/N]:${NC} "
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            echo -e "  Skipped $script"
            continue
        fi
    fi
    cp "$SCRIPT_DIR/scripts/$script" "$HOME_DIR/$script"
    chmod +x "$HOME_DIR/$script"
    echo -e "  ${GREEN}✓${NC} $script"
done

# 2. Add aliases
echo ""
echo -e "${BOLD}[2/5] Setting up bash aliases...${NC}"
ALIASES_EXIST=0
if grep -q 'alias morning=' "$HOME_DIR/.bashrc" 2>/dev/null; then
    ALIASES_EXIST=1
fi

if [ "$ALIASES_EXIST" -eq 1 ]; then
    echo -e "  ${YELLOW}Aliases already exist in ~/.bashrc. Skipping.${NC}"
else
    cat >> "$HOME_DIR/.bashrc" << 'EOF'

# Ubuntu Automation aliases
alias morning="bash ~/daily-startup.sh"
alias deepclean="bash ~/deep-clean.sh"
alias pcaudit="bash ~/pc-audit.sh"
alias autorun="bash ~/daily-startup.sh && bash ~/deep-clean.sh && bash ~/pc-audit.sh"
EOF
    echo -e "  ${GREEN}✓${NC} Added aliases: morning, deepclean, pcaudit, autorun"
fi

# 3. Install systemd timers
echo ""
echo -e "${BOLD}[3/5] Installing systemd user timers...${NC}"
mkdir -p "$HOME_DIR/.config/systemd/user"

sed "s|/home/rhymezxcode/|${HOME_DIR}/|g" "$SCRIPT_DIR/systemd/morning-reminder.service" \
    > "$HOME_DIR/.config/systemd/user/morning-reminder.service"
cp "$SCRIPT_DIR/systemd/morning-reminder.timer" "$HOME_DIR/.config/systemd/user/"
echo -e "  ${GREEN}✓${NC} morning-reminder (timer + service)"

sed "s|/home/rhymezxcode/|${HOME_DIR}/|g" "$SCRIPT_DIR/systemd/deepclean-reminder.service" \
    > "$HOME_DIR/.config/systemd/user/deepclean-reminder.service"
cp "$SCRIPT_DIR/systemd/deepclean-reminder.timer" "$HOME_DIR/.config/systemd/user/"
echo -e "  ${GREEN}✓${NC} deepclean-reminder (timer + service)"

systemctl --user daemon-reload
systemctl --user enable --now morning-reminder.timer 2>/dev/null
systemctl --user enable --now deepclean-reminder.timer 2>/dev/null
echo -e "  ${GREEN}✓${NC} Timers enabled and started"

# 4. Install desktop entry
echo ""
echo -e "${BOLD}[4/5] Installing desktop entry...${NC}"
mkdir -p "$HOME_DIR/.local/share/applications"
sed "s|/home/rhymezxcode/|${HOME_DIR}/|g; s|rhymezxcode|${USERNAME}|g" \
    "$SCRIPT_DIR/desktop/morning-startup.desktop" \
    > "$HOME_DIR/.local/share/applications/morning-startup.desktop"
echo -e "  ${GREEN}✓${NC} morning-startup.desktop"

# 5. Verify
echo ""
echo -e "${BOLD}[5/5] Verifying installation...${NC}"
echo ""

ALL_OK=1
for script in daily-startup.sh deep-clean.sh pc-audit.sh morning-notify.sh deepclean-notify.sh; do
    if [ -x "$HOME_DIR/$script" ]; then
        echo -e "  ${GREEN}✓${NC} ~/$script"
    else
        echo -e "  ${RED}✗${NC} ~/$script"
        ALL_OK=0
    fi
done

for timer in morning-reminder.timer deepclean-reminder.timer; do
    STATUS=$(systemctl --user is-active "$timer" 2>/dev/null)
    if [ "$STATUS" = "active" ]; then
        echo -e "  ${GREEN}✓${NC} $timer (active)"
    else
        echo -e "  ${RED}✗${NC} $timer ($STATUS)"
        ALL_OK=0
    fi
done

if command -v notify-send &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} notify-send available"
else
    echo -e "  ${RED}✗${NC} notify-send not found (install libnotify-bin)"
    ALL_OK=0
fi

echo ""
if [ "$ALL_OK" -eq 1 ]; then
    echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
else
    echo -e "${YELLOW}${BOLD}  Installation complete with warnings.${NC}"
fi

echo ""
echo -e "  Open a new terminal and try:"
echo -e "    ${BOLD}morning${NC}     — daily maintenance"
echo -e "    ${BOLD}deepclean${NC}   — weekly deep clean"
echo -e "    ${BOLD}pcaudit${NC}     — full system audit"
echo -e "    ${BOLD}autorun${NC}     — run all three"
echo ""
