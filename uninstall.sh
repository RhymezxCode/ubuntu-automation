#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║     Ubuntu Automation Toolkit Uninstaller     ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${YELLOW}This will remove all scripts, aliases, timers, and config.${NC}"
read -r -p "  Continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 0
fi
echo ""

# 1. Disable and remove systemd timers/services
echo -e "${BOLD}[1/5] Removing systemd timers...${NC}"
for unit in morning-reminder deepclean-reminder system-alert; do
    systemctl --user disable --now "${unit}.timer" 2>/dev/null && \
        echo -e "  ${GREEN}✓${NC} ${unit}.timer stopped and disabled" || true
    rm -f "$HOME/.config/systemd/user/${unit}.timer" \
          "$HOME/.config/systemd/user/${unit}.service"
done
systemctl --user daemon-reload 2>/dev/null
echo -e "  ${GREEN}✓${NC} Systemd units removed"

# 2. Remove installed scripts from ~/
echo ""
echo -e "${BOLD}[2/5] Removing scripts...${NC}"
for script in daily-startup.sh deep-clean.sh pc-audit.sh \
              morning-notify.sh deepclean-notify.sh system-alert.sh; do
    if [ -f "$HOME/$script" ]; then
        rm -f "$HOME/$script"
        echo -e "  ${GREEN}✓${NC} ~/$script"
    fi
done
rm -f "$HOME/.local/bin/ubuntu-automation-launch-in-terminal.sh"
echo -e "  ${GREEN}✓${NC} ~/.local/bin/ubuntu-automation-launch-in-terminal.sh"

# 3. Remove aliases from ~/.bashrc and ~/.zshrc
echo ""
echo -e "${BOLD}[3/5] Removing aliases...${NC}"
for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$RC" ] || continue
    if grep -q 'Ubuntu Automation aliases' "$RC" 2>/dev/null; then
        # Remove the alias block (comment line + 4 alias lines)
        sed -i '/# Ubuntu Automation aliases/,/^alias autorun=/d' "$RC"
        # Clean up any blank line left before the block
        echo -e "  ${GREEN}✓${NC} Aliases removed from ${RC/$HOME/~}"
    fi
done

# 4. Remove desktop entry
echo ""
echo -e "${BOLD}[4/5] Removing desktop entry...${NC}"
rm -f "$HOME/.local/share/applications/morning-startup.desktop"
echo -e "  ${GREEN}✓${NC} morning-startup.desktop"

# 5. Remove config directory
echo ""
echo -e "${BOLD}[5/5] Removing config...${NC}"
if [ -d "$HOME/.config/ubuntu-automation" ]; then
    rm -rf "$HOME/.config/ubuntu-automation"
    echo -e "  ${GREEN}✓${NC} ~/.config/ubuntu-automation/"
else
    echo -e "  ${GREEN}✓${NC} No config directory found"
fi

echo ""
echo -e "${GREEN}${BOLD}  Uninstall complete.${NC}"
echo -e "  Open a new terminal to clear the removed aliases from your session."
echo ""
