# Ubuntu Developer Automation Toolkit

Automated daily maintenance, weekly deep cleaning, and full system auditing for Ubuntu — with GNOME desktop notifications, systemd timers, and one-word bash aliases.

Built for my ThinkPad X1 Carbon 6th Gen running Ubuntu 24.04, with terminal-launch compatibility updates for newer Ubuntu releases (including 26.04).

## What's Inside

```
ubuntu-automation/
├── scripts/
│   ├── daily-startup.sh        # Daily system health check & updates
│   ├── deep-clean.sh           # Weekly deep disk cleanup
│   ├── pc-audit.sh             # Full hardware/software/security audit
│   ├── morning-notify.sh       # Morning notification with weather & stats
│   ├── deepclean-notify.sh     # Sunday cleanup reminder notification
│   └── ubuntu-automation-launch-in-terminal.sh  # Terminal chooser/launcher
├── systemd/
│   ├── morning-reminder.timer  # Fires 60s after login
│   ├── morning-reminder.service
│   ├── deepclean-reminder.timer # Fires every Sunday at 11:00 AM
│   └── deepclean-reminder.service
├── desktop/
│   └── morning-startup.desktop # GNOME app launcher entry
├── install.sh                  # Automated installer
├── article-my-ubuntu-automation.md  # Full Medium article
└── README.md
```

## Quick Install

```bash
git clone https://github.com/YOUR_USERNAME/ubuntu-automation.git
cd ubuntu-automation
chmod +x install.sh
./install.sh
```

## Manual Install

### 1. Copy scripts to home directory and launcher to `~/.local/bin`

```bash
cp scripts/daily-startup.sh scripts/deep-clean.sh scripts/pc-audit.sh ~/
cp scripts/morning-notify.sh scripts/deepclean-notify.sh ~/
chmod +x ~/daily-startup.sh ~/deep-clean.sh ~/pc-audit.sh
chmod +x ~/morning-notify.sh ~/deepclean-notify.sh

mkdir -p ~/.local/bin
cp scripts/ubuntu-automation-launch-in-terminal.sh ~/.local/bin/
chmod +x ~/.local/bin/ubuntu-automation-launch-in-terminal.sh
```

### 2. Add aliases to `~/.bashrc`

```bash
cat >> ~/.bashrc << 'EOF'

# Ubuntu Automation aliases
alias morning="bash ~/daily-startup.sh"
alias deepclean="bash ~/deep-clean.sh"
alias pcaudit="bash ~/pc-audit.sh"
alias autorun="bash ~/daily-startup.sh && bash ~/deep-clean.sh && bash ~/pc-audit.sh"
EOF
source ~/.bashrc
```

### 3. Install systemd user timers

```bash
mkdir -p ~/.config/systemd/user

# Copy and update username in service files
sed "s|/home/rhymezxcode/|/home/$(whoami)/|g" systemd/morning-reminder.service \
    > ~/.config/systemd/user/morning-reminder.service
sed "s|/home/rhymezxcode/|/home/$(whoami)/|g" systemd/deepclean-reminder.service \
    > ~/.config/systemd/user/deepclean-reminder.service

cp systemd/morning-reminder.timer ~/.config/systemd/user/
cp systemd/deepclean-reminder.timer ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now morning-reminder.timer
systemctl --user enable --now deepclean-reminder.timer
```

### 4. Install desktop entry (optional)

```bash
sed "s|/home/rhymezxcode/|/home/$(whoami)/|g" desktop/morning-startup.desktop \
    > ~/.local/share/applications/morning-startup.desktop
```

## Usage

| Command | What it does |
|---------|-------------|
| `morning` | Run daily maintenance (health check, updates, daemon cleanup) |
| `deepclean` | Run weekly deep clean (build caches, system caches, large files) |
| `pcaudit` | Run full system audit (hardware, software, security report) |
| `autorun` | Run all three in sequence |

The notifications appear automatically:
- **Morning** — 60 seconds after login, with weather, system stats, and a motivational quote
- **Sunday** — At 11:00 AM, with disk usage stats and cleanup reminder

Click the notification button (or the notification body) to open a terminal and run the script.

Set your preferred terminal once:

```bash
~/.local/bin/ubuntu-automation-launch-in-terminal.sh --choose-terminal
```

## What Each Script Does

### `daily-startup.sh` (alias: `morning`)
- System health dashboard (RAM, disk, swap, CPU temp, battery)
- Kill leftover Gradle/Kotlin daemons
- Update APT, Snap, npm packages (interactive)
- Check firmware and Android SDK updates
- Quick Gradle cache cleanup
- Trim journal logs
- Verify performance services (tlp, thermald, earlyoom)
- Security check (failed logins, reboot required)
- Top memory consumers

### `deep-clean.sh` (alias: `deepclean`)
- Stop all Gradle daemons gracefully per project
- Clean project build caches (build/, .gradle/, app/build/)
- Clean Gradle global caches (build-cache, transforms, daemon logs)
- Remove old Android Studio version caches
- APT autoremove and cache clean
- Trim journal logs aggressively (3 days, 100MB cap)
- Clean thumbnail cache and trash
- Remove old snap revisions
- Scan for large files (>200MB)
- Before/after disk usage summary

### `pc-audit.sh` (alias: `pcaudit`)
- System identity (OS, kernel, machine model, BIOS)
- Hardware inventory (CPU, RAM, GPU, disks, battery, network, USB)
- Software versions (Git, Java, Kotlin, Node, Python, Flutter, Docker, etc.)
- Storage breakdown (partitions, swap, top 10 directories)
- Performance snapshot (load, temperature, boot time, top consumers)
- Security audit (firewall, open ports, failed logins, SSH config, pending updates)

## Requirements

- Ubuntu 24.04+ (or any GNOME-based distro)
- `notify-send` with `--action` support (libnotify 0.8+)
- Any supported terminal launcher (for example: `x-terminal-emulator`, `gnome-terminal`, `ptyxis`, `kgx`, `konsole`, `xfce4-terminal`, `tilix`, `kitty`, `wezterm`, `xterm`)
- Python 3
- `curl` (for weather in notifications)

Optional tools the scripts detect and use if available:
- `lm-sensors` (CPU temperature)
- `upower` (battery details)
- `fwupdmgr` (firmware updates)
- `dmidecode` (hardware details in audit)
- `zenity` (for GUI terminal picker; CLI fallback is included)

## Customization

- **Edit quotes** — modify the `QUOTES` list in `morning-notify.sh` and `deepclean-notify.sh`
- **Change notification timing** — edit `OnStartupSec` in `morning-reminder.timer` or `OnCalendar` in `deepclean-reminder.timer`
- **Add project paths** — update the glob patterns in `deep-clean.sh` for your project directories
- **Adjust thresholds** — the color-coded alerts use configurable thresholds (RAM >85% = red, disk >70% = yellow, etc.)

## License

MIT - use it, modify it, make your machine take care of itself.
