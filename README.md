# Ubuntu Developer Automation Toolkit For An Android Engineer 

Automated daily maintenance, weekly deep cleaning, and full system auditing for Ubuntu — with GNOME desktop notifications, systemd timers, and one-word bash aliases.

Built for a ThinkPad X1 Carbon 6th Gen running Ubuntu, with full compatibility for Ubuntu 24.04 and 26.04 (GNOME 48, ptyxis terminal).

## What's Inside

```
ubuntu-automation/
├── scripts/
│   ├── daily-startup.sh        # Daily system health check & updates
│   ├── deep-clean.sh           # Weekly deep disk cleanup (supports --dry-run)
│   ├── pc-audit.sh             # Full hardware/software/security audit
│   ├── morning-notify.sh       # Morning notification with weather & stats
│   ├── deepclean-notify.sh     # Sunday cleanup reminder notification
│   ├── system-alert.sh         # Critical disk/battery alert (runs every 6h)
│   └── ubuntu-automation-launch-in-terminal.sh  # Terminal chooser/launcher
├── systemd/
│   ├── morning-reminder.timer  # Fires 60s after login
│   ├── morning-reminder.service
│   ├── deepclean-reminder.timer # Fires every Sunday at 11:00 AM
│   ├── deepclean-reminder.service
│   ├── system-alert.timer      # Fires 5min after boot, then every 6h
│   └── system-alert.service
├── desktop/
│   └── morning-startup.desktop # GNOME app launcher entry
├── install.sh                  # Automated installer
├── uninstall.sh                # Clean removal of everything
├── article-my-ubuntu-automation.md
└── README.md
```

## Quick Install

```bash
git clone https://github.com/YOUR_USERNAME/ubuntu-automation.git
cd ubuntu-automation
chmod +x install.sh
./install.sh
```

The installer handles scripts, aliases (bash + zsh), systemd timers, and the desktop entry automatically.

## Uninstall

```bash
bash uninstall.sh
```

Removes all scripts, aliases from `.bashrc`/`.zshrc`, systemd timers, the desktop entry, and `~/.config/ubuntu-automation/`.

## Manual Install

### 1. Copy scripts

```bash
cp scripts/daily-startup.sh scripts/deep-clean.sh scripts/pc-audit.sh ~/
cp scripts/morning-notify.sh scripts/deepclean-notify.sh scripts/system-alert.sh ~/
chmod +x ~/daily-startup.sh ~/deep-clean.sh ~/pc-audit.sh
chmod +x ~/morning-notify.sh ~/deepclean-notify.sh ~/system-alert.sh

mkdir -p ~/.local/bin
cp scripts/ubuntu-automation-launch-in-terminal.sh ~/.local/bin/
chmod +x ~/.local/bin/ubuntu-automation-launch-in-terminal.sh
```

### 2. Add aliases to `~/.bashrc` (and `~/.zshrc` if using zsh)

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

sed "s|/home/rhymezxcode/|/home/$(whoami)/|g" systemd/morning-reminder.service \
    > ~/.config/systemd/user/morning-reminder.service
sed "s|/home/rhymezxcode/|/home/$(whoami)/|g" systemd/deepclean-reminder.service \
    > ~/.config/systemd/user/deepclean-reminder.service
sed "s|/home/rhymezxcode/|/home/$(whoami)/|g" systemd/system-alert.service \
    > ~/.config/systemd/user/system-alert.service

cp systemd/morning-reminder.timer ~/.config/systemd/user/
cp systemd/deepclean-reminder.timer ~/.config/systemd/user/
cp systemd/system-alert.timer ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now morning-reminder.timer
systemctl --user enable --now deepclean-reminder.timer
systemctl --user enable --now system-alert.timer
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
| `deepclean --dry-run` | Preview what would be cleaned without making any changes |
| `pcaudit` | Run full system audit (hardware, software, security report) |
| `autorun` | Run all three in sequence |

## Notifications

Notifications appear automatically via systemd timers:

- **Morning** — 60 seconds after login, shows weather, RAM, disk, battery, and a motivational quote
- **Sunday** — At 11:00 AM, shows disk usage stats and a cleanup reminder
- **System Alert** — 5 minutes after boot then every 6 hours, fires only when disk ≥ 80% full or battery ≤ 20%

Each notification has three action buttons:

| Button | Behaviour |
|--------|-----------|
| **Run Script** / **Run Deep Clean** | Opens the script in your default terminal immediately |
| **Choose Terminal and Run** | Opens a terminal picker (zenity), saves your choice, then launches the script |
| **Snooze 1h** | Dismisses the notification and re-fires it after 60 minutes |

Buttons can be clicked any number of times — each click opens a new terminal. The notification stays active until you dismiss it or the 45-second timeout expires.

When a script finishes running, a summary notification is sent showing disk space freed (deep clean) or current free disk space (morning), plus a reboot reminder if one is pending.

For desktops where notification action callbacks are unavailable, the scripts fall back to a Zenity dialog with Run / Choose Terminal / Skip options.

### Set your preferred terminal

```bash
~/.local/bin/ubuntu-automation-launch-in-terminal.sh --choose-terminal
```

Or set it directly:

```bash
~/.local/bin/ubuntu-automation-launch-in-terminal.sh --set-terminal ptyxis
```

Other terminal management commands:

```bash
--list-terminals      # Show all detected terminals
--current-terminal    # Show the currently saved preference
```

## What Each Script Does

### `daily-startup.sh` (alias: `morning`)
- System health dashboard (RAM, disk, swap, CPU temp, battery)
- Kill leftover Gradle/Kotlin daemons
- Update APT, Snap, npm packages (interactive, with timeout)
- Check firmware and Android SDK updates
- Quick Gradle build cache cleanup
- Trim journal logs
- Verify performance services (tlp, thermald, earlyoom)
- Security check (failed logins, reboot-required flag)
- Top memory consumers
- **Post-run notification** with disk free space and reboot reminder if needed

### `deep-clean.sh` (alias: `deepclean`)
- Stop all Gradle daemons gracefully per project
- Clean project build caches (`build/`, `.gradle/`, `app/build/`)
- Clean Gradle global caches (build-cache, transforms, daemon logs)
- Remove old Android Studio version caches
- APT autoremove and cache clean
- Trim journal logs aggressively (3 days / 100 MB cap)
- Clean thumbnail cache and trash
- Remove old snap revisions
- Scan for large files (>200 MB)
- Before/after disk usage summary
- **`--dry-run` flag** — shows everything that would be cleaned without touching anything
- **Post-run notification** with total space freed

### `pc-audit.sh` (alias: `pcaudit`)
- System identity (OS, kernel, machine model, BIOS)
- Hardware inventory (CPU, RAM, GPU, disks, battery, network, USB)
- Software versions (Git, Java, Kotlin, Node, Python, Flutter, Docker, etc.)
- Storage breakdown (partitions, swap, top 10 directories)
- Performance snapshot (load, temperature, boot time, top consumers)
- Security audit (firewall, open ports, failed logins, SSH config, pending updates)

### `system-alert.sh`
- Checks disk usage and battery level
- Sends a critical-urgency notification if disk ≥ 80% or battery ≤ 20% (and not charging)
- Runs automatically via systemd 5 minutes after boot, then every 6 hours
- Silent when everything is healthy — no noise unless action is needed

## Requirements

- Ubuntu 24.04+ (tested on 24.04 and 26.04 / GNOME 48)
- Notification daemon on `org.freedesktop.Notifications` (GNOME default)
- Python 3
- `python3-dbus` and `python3-gi` — for notification action button handling
- Any supported terminal: `ptyxis`, `x-terminal-emulator`, `gnome-terminal`, `kgx`, `konsole`, `xfce4-terminal`, `tilix`, `alacritty`, `kitty`, `wezterm`, `xterm`
- `curl` — for weather in morning notification

Optional tools detected and used when available:
- `lm-sensors` — CPU temperature
- `upower` — battery details
- `fwupdmgr` — firmware updates
- `dmidecode` — hardware details in audit
- `zenity` — GUI terminal picker (CLI fallback is included)

## Customization

- **Edit quotes** — modify the `QUOTES` list in `morning-notify.sh` or `deepclean-notify.sh`
- **Change notification timing** — edit `OnStartupSec` in `morning-reminder.timer` or `OnCalendar` in `deepclean-reminder.timer`
- **Change alert frequency** — edit `OnUnitActiveSec` in `system-alert.timer`
- **Adjust alert thresholds** — edit the `DISK_PCT` and `BAT_PCT` thresholds in `system-alert.sh`
- **Add project paths** — update the glob patterns in `deep-clean.sh` for your own project directories
- **Adjust colour thresholds** — RAM >85% = red, disk >70% = yellow, etc. — all configurable at the top of each script

## License

MIT — use it, modify it, make your machine take care of itself.
