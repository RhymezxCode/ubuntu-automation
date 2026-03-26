# I Automated My Entire Ubuntu Developer Workflow With Bash Scripts, Systemd Timers, and Desktop Notifications — Here's How

*How I turned my ThinkPad X1 Carbon into a self-maintaining machine that greets me every morning, reminds me to clean up on Sundays, and audits itself on demand — all with nothing but shell scripts and a few lines of config.*

---

I'm an Android developer. My daily tools are Android Studio, Gradle, ADB, and a dozen other things that silently eat disk space, leak memory through background daemons, and leave stale caches all over my home directory. For the longest time, I'd forget to update packages for weeks, let Gradle caches balloon to gigabytes, and only notice my disk was full when a build failed.

So one weekend, I sat down and asked myself a simple question: *What if my laptop just... took care of itself?*

Not with some bloated third-party tool. Not with a cron job I'd forget about. I wanted something that felt *native* — something that would tap me on the shoulder with a friendly GNOME notification, show me a motivational quote, tell me the weather, and let me decide whether to run the maintenance script right there from the notification.

That weekend project turned into a system I've been using daily for months. Here's exactly how I built it, step by step.

---

## The Big Picture

Before we dive into code, let me show you the architecture. It's simpler than you'd think:

```
┌─────────────────────────────────────────────────────────┐
│                    My Ubuntu Setup                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  SCRIPTS (in ~/):                                        │
│  ├── daily-startup.sh     → Full morning maintenance     │
│  ├── deep-clean.sh        → Weekly deep disk cleanup     │
│  ├── pc-audit.sh          → Full system audit/report     │
│  ├── morning-notify.sh    → Notification for morning     │
│  └── deepclean-notify.sh  → Notification for Sunday      │
│                                                          │
│  ALIASES (in ~/.bashrc):                                 │
│  ├── morning    → runs daily-startup.sh                  │
│  ├── deepclean  → runs deep-clean.sh                     │
│  ├── pcaudit    → runs pc-audit.sh                       │
│  └── autorun    → runs all three back-to-back            │
│                                                          │
│  AUTOMATION (systemd user timers):                       │
│  ├── morning-reminder.timer   → 60s after login          │
│  │   └── morning-reminder.service → morning-notify.sh    │
│  └── deepclean-reminder.timer → Every Sunday at 11:00    │
│      └── deepclean-reminder.service → deepclean-notify.sh│
│                                                          │
│  DESKTOP ENTRY:                                          │
│  └── morning-startup.desktop  → Launchable from GNOME    │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

There are three layers:

1. **The scripts** — the actual work (update packages, clean caches, audit hardware).
2. **The notifications** — pretty GNOME notifications with weather, system stats, and a clickable button that opens a terminal to run the script.
3. **The automation** — systemd user timers that fire the notifications at the right time, automatically.

And because I'm lazy in the best way, I set up bash aliases so I can also run any of them manually by typing a single word.

Let's build each layer.

---

## Part 1: The Scripts

### `daily-startup.sh` — The Morning Routine

This is the big one. Every morning, this script gives my system a health check and brings everything up to date. Here's what it does, section by section.

**The header and utilities:**

The script starts by defining colored output and two critical helper functions:

```bash
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
```

These ANSI escape codes give the terminal output color. `NC` stands for "No Color" — it resets formatting after a colored string. The timeout variables prevent any single operation from hanging the entire script.

Then there's the `spinner()` function, which shows a nice animated spinner while a background task runs:

```bash
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
```

The `kill -0 "$pid"` trick doesn't actually kill anything — it's a POSIX way to check "is this process still alive?" The Braille pattern characters (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) cycle through to create a smooth spinner animation.

And `run_with_timeout()` wraps any command so it runs in the background with a spinner and gets killed if it takes too long:

```bash
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
        return $exit_code
    fi

    echo -n "$output"
    return 0
}
```

This is the engine of both the morning and deep-clean scripts. It runs a command in the background, shows a spinner while it works, enforces a timeout, and captures output to a temp file so the terminal stays clean.

**Internet connectivity check:**

Before attempting any network operations, the script pings Google DNS (`8.8.8.8`) and Cloudflare (`1.1.1.1`) as a fallback:

```bash
check_internet() {
    if timeout 5 ping -c 1 8.8.8.8 &>/dev/null; then
        return 0
    elif timeout 5 ping -c 1 1.1.1.1 &>/dev/null; then
        return 0
    fi
    return 1
}
```

If there's no internet, the script gracefully skips all network-dependent tasks (APT, Snap, npm, firmware, SDK updates) and tells you to run `morning` again when you're connected. No errors, no hanging.

**System health dashboard:**

The script reads directly from Linux pseudo-filesystems and standard tools to build a health report:

```bash
UPTIME=$(uptime -p)
LOAD=$(awk '{print $1}' /proc/loadavg)
MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/Mem:/ {print $3}')
MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
```

Each metric gets color-coded: green if healthy, yellow if worth watching, red if it needs attention. The same logic applies to CPU temperature (read via `lm-sensors`), battery status (via `upower`), and swap usage.

**Memory cleanup:**

As an Android developer, I often close Android Studio but Gradle and Kotlin daemons keep running, eating hundreds of megabytes. The script hunts them down:

```bash
if pgrep -f "GradleDaemon" &>/dev/null; then
    pkill -f "GradleDaemon" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Killed leftover Gradle daemons"
fi

if pgrep -f "KotlinCompileDaemon" &>/dev/null; then
    pkill -f "KotlinCompileDaemon" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Killed leftover Kotlin daemons"
fi
```

`pgrep -f` searches all running processes by their full command line. `pkill -f` kills matching processes. Simple, surgical, effective.

**Package updates (APT, Snap, npm):**

The script checks for and optionally installs updates across all three Ubuntu package managers. Each one is interactive — it tells you how many updates are available and asks if you want to proceed:

```bash
if run_with_timeout "$NET_TIMEOUT_SECS" "Updating package lists..." sudo apt update -qq; then
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
    if [ "$UPGRADABLE" -gt 0 ]; then
        echo -e "  ${YELLOW}${UPGRADABLE} packages can be upgraded${NC}"
        read -t 30 -p "  Upgrade now? [Y/n]: " APT_ANSWER
        APT_ANSWER=${APT_ANSWER:-Y}
        if [[ "$APT_ANSWER" =~ ^[Yy]$ ]]; then
            sudo apt upgrade -y 2>&1 | tail -5 | sed 's/^/  /'
            sudo apt autoremove -y -qq 2>/dev/null
        fi
    fi
fi
```

The `read -t 30` gives you 30 seconds to answer before auto-defaulting to "Yes." The `-qq` flag on `apt` suppresses noise so only meaningful output shows up.

The same pattern repeats for Snap packages, npm globals, firmware updates (via `fwupdmgr`), and even Android SDK updates (via `sdkmanager`).

**Quick cleanup and service status:**

The script trims journal logs older than 7 days, checks if the Gradle build cache is oversized, counts installed kernels, and verifies that performance services like `tlp` (laptop power management), `thermald` (thermal management), and `earlyoom` (out-of-memory killer) are running.

**Security check:**

Before wrapping up, it checks for pending reboots and scans the last 24 hours of system logs for failed authentication attempts:

```bash
FAILED_LOGINS=$(journalctl -q --since "24 hours ago" 2>/dev/null \
    | grep -c "authentication failure" 2>/dev/null || echo 0)
```

---

### `deep-clean.sh` — The Sunday Scrub

This runs once a week and goes much deeper than the morning script. It's the difference between wiping down your desk and deep-cleaning your apartment.

**Build daemon shutdown:**

Instead of just killing daemons by process name, it iterates through every Android project and gracefully stops Gradle:

```bash
for PROJECT_DIR in ~/StudioProjects/personal/*/gradlew ~/StudioProjects/work/*/gradlew; do
    if [ -f "$PROJECT_DIR" ]; then
        DIR=$(dirname "$PROJECT_DIR")
        NAME=$(basename "$DIR")
        timeout 10 "$PROJECT_DIR" --stop -p "$DIR" 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Stopped Gradle in ${NAME}"
    fi
done
```

The glob `~/StudioProjects/personal/*/gradlew` expands to every project that has a Gradle wrapper. Running `./gradlew --stop` is cleaner than `pkill` because it lets Gradle shut down properly.

**Project build cache cleanup:**

This is where the real space savings happen. Android builds generate massive `build/` and `.gradle/` directories inside each project:

```bash
for DIR in ~/StudioProjects/personal/*/ ~/StudioProjects/work/*/; do
    [ ! -d "$DIR" ] && continue
    NAME=$(basename "$DIR")
    BUILD_SIZE=$(du -sb "$DIR/build" "$DIR/.gradle" "$DIR/app/build" 2>/dev/null \
        | awk '{sum+=$1} END {print sum+0}')
    if [ "$BUILD_SIZE" -gt 10485760 ]; then
        echo -e "    ${YELLOW}$(bytes_to_human $BUILD_SIZE)${NC}\t${NAME}"
    fi
done
```

It scans every project, calculates the cleanable size, shows you a breakdown, and asks before deleting. The `bytes_to_human` function converts raw bytes to human-readable KB/MB/GB.

**Gradle global cache cleanup:**

Beyond per-project caches, Gradle keeps a global cache in `~/.gradle/caches/`. The script breaks it down:

```bash
GRADLE_BUILD_CACHE=$(du -sb ~/.gradle/caches/build-cache-* 2>/dev/null \
    | awk '{sum+=$1} END {print sum+0}')
GRADLE_TRANSFORMS=$(du -sb ~/.gradle/caches/transforms-* 2>/dev/null \
    | awk '{sum+=$1} END {print sum+0}')
GRADLE_DAEMON_LOGS=$(du -sb ~/.gradle/daemon/*/daemon-*.out.log 2>/dev/null \
    | awk '{sum+=$1} END {print sum+0}')
```

Build caches, transform caches, and daemon logs are shown separately so you know exactly what's eating your disk.

**Android Studio version cleanup:**

If you've upgraded Android Studio, old caches linger in `~/.cache/Google/AndroidStudio*`. The script finds them, keeps the latest, and offers to delete the rest.

**System-level cleanup:**

The deep-clean script also handles:
- **APT autoremove and cache cleaning** — removes orphaned packages and clears the package cache
- **Journal log trimming** — keeps only the last 3 days, capped at 100MB
- **Thumbnail cache** — GNOME generates thumbnails for file previews; they pile up
- **Trash emptying** — `~/.local/share/Trash/` can grow silently
- **Old temp files** — files in `/tmp` older than 3 days owned by your user
- **Old Snap revisions** — Ubuntu keeps disabled snap revisions around; this cleans them

**Large file finder:**

At the end, it scans your home directory for any file over 200MB, excluding expected large directories (Android SDK, JetBrains tools, snap):

```bash
LARGE_FILES=$(find ~/ -maxdepth 4 -type f -size +200M \
    -not -path "*/Android/Sdk/*" \
    -not -path "*/.gradle/caches/modules*" \
    -not -path "*/.gradle/wrapper/*" \
    -not -path "*/.jdks/*" \
    -not -path "*/.local/share/JetBrains/*" \
    -not -path "*/snap/*" \
    -not -path "*/.cache/Google/AndroidStudio*/aia/*" \
    2>/dev/null | head -15)
```

This has caught forgotten ISO files, old APKs, and database dumps I completely forgot about.

**Final summary:**

The script measures disk usage before and after, then tells you exactly how much space was freed:

```bash
DISK_AFTER=$(df / --output=used | tail -1 | tr -d ' ')
ACTUAL_FREED=$(( (DISK_BEFORE - DISK_AFTER) * 1024 ))
if [ "$ACTUAL_FREED" -gt 0 ]; then
    echo -e "  ${GREEN}${BOLD}Freed $(bytes_to_human $ACTUAL_FREED) of disk space!${NC}"
fi
```

---

### `pc-audit.sh` — The Full System Report

This one is different from the others. It doesn't change anything — it just *observes* and reports. Think of it as running a full diagnostic on your car. I run it whenever something feels off, or just monthly to keep tabs on things.

**System identity:**

It reads from `/etc/os-release`, the kernel version, system DMI data (machine model, BIOS version), and presents a clean identity card.

**Hardware deep-dive:**

The audit script pulls detailed hardware info you'd normally need multiple tools to gather:

```bash
CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | sed 's/Model name:[[:space:]]*//')
CPU_CORES=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
RAM_TYPE=$(sudo dmidecode -t memory 2>/dev/null | grep "Type:" \
    | grep -v "Error\|Unknown" | head -1 | awk '{print $2}')
RAM_SPEED=$(sudo dmidecode -t memory 2>/dev/null \
    | grep "Configured Memory Speed" | head -1 | awk '{print $4, $5}')
```

It covers CPU (model, cores, threads, max frequency), RAM (total, type, speed, slot usage), GPU (via `lspci`), disk drives (SSD vs HDD, transport type, model), battery health (charge cycles, capacity degradation, chemistry), network adapters, and connected USB devices.

**Software inventory:**

A `tool_version` helper function cleanly checks and displays whether each development tool is installed:

```bash
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
```

It checks Git, Java, Kotlin, Node.js, npm, Python, pip, Flutter, Dart, Docker, ADB, Gradle, Go, Rust, GCC, Android Studio, and Cursor. It also counts total APT, Snap, and Flatpak packages.

**Storage breakdown:**

Beyond a simple `df`, the audit shows all partitions (excluding virtual filesystems like `tmpfs` and `squashfs`), swap usage, and the top 10 largest directories in your home folder.

**Performance snapshot:**

Uptime, load averages, CPU temperature, boot time (via `systemd-analyze`), top 5 CPU consumers, top 5 memory consumers, total systemd services, and any failed services.

**Security audit:**

This is where the script uses a flag counter to track issues:

```bash
FLAGS=0

flag() {
    local msg=$1
    FLAGS=$((FLAGS + 1))
    echo -e "  ${RED}⚠ ${msg}${NC}"
}
```

It checks:
- **Firewall status** — is `ufw` active?
- **Open listening ports** — what's exposed on the network?
- **Failed login attempts** — last 7 days of `journalctl` logs
- **Users with login shells** — any unexpected accounts?
- **SSH configuration** — is root login enabled? Is password auth on?
- **Pending security updates**
- **Reboot required flag**

At the end, it either gives you a clean bill of health or tells you exactly how many issues were flagged.

---

## Part 2: The Notification System

The scripts are great, but I'm not going to remember to run them every morning. I needed something that would remind me — *nicely*. Not a beep. Not a cron email. A proper, beautiful GNOME desktop notification with context.

### How the notification scripts work

Each notification script (`morning-notify.sh` and `deepclean-notify.sh`) is a bash script that embeds a Python block. The Python code gathers dynamic data (weather, system stats, a random quote), writes the notification title and body to temp files, and then bash takes over to send the notification using `notify-send`.

Here's the flow:

```
┌─────────────────────┐
│   Python gathers:   │
│  • Greeting (AM/PM) │
│  • Date & time      │
│  • Weather (wttr.in)│
│  • RAM/Disk/Battery │
│  • Random quote     │
│  Writes to tmpfiles │
└────────┬────────────┘
         ▼
┌─────────────────────┐
│   Bash sends:       │
│  notify-send with   │
│  --action and --wait│
│  Shows button:      │
│  "🚀 Run Morning    │
│      Script"        │
└────────┬────────────┘
         ▼
┌─────────────────────┐
│   On button click:  │
│  Opens gnome-terminal│
│  Runs the .sh script│
└─────────────────────┘
```

**Why Python for data gathering?**

Bash *can* do all of this, but Python makes it cleaner — especially for HTTP requests (weather API), parsing `/proc/meminfo`, and handling edge cases without a chain of fragile `awk`/`sed` pipes.

**The weather function:**

```python
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
```

[wttr.in](https://wttr.in) is a free weather service that returns plain-text weather data. No API key needed. The `%C|%t|%h|%l` format string asks for condition, temperature, humidity, and location, pipe-separated. The function then maps weather conditions to emoji icons.

**The motivational quotes:**

Each notification includes a random motivational quote from a curated list:

```python
QUOTES = [
    "The only way to do great work is to love what you do. — Steve Jobs",
    "First, solve the problem. Then, write the code. — John Johnson",
    "Make it work, make it right, make it fast. — Kent Beck",
    "Talk is cheap. Show me the code. — Linus Torvalds",
    "Shipping beats perfection.",
    "One commit at a time.",
    # ...30 quotes total
]

quote = random.choice(QUOTES)
```

It's a small thing, but starting my day with "Debug your life the way you debug your code — one breakpoint at a time" genuinely puts me in a better mood.

**Sending the notification:**

After Python writes the title and body to temp files, bash reads them and uses `notify-send`:

```bash
TITLE=$(<"$TITLE_FILE")
BODY=$(<"$BODY_FILE")

ACTION=$(notify-send "$TITLE" "$BODY" \
    --icon=computer \
    --app-name="Daily Maintenance" \
    --action="run=🚀 Run Morning Script" \
    --wait)

if [ "$ACTION" = "run" ]; then
    gnome-terminal -- bash -c 'bash ~/daily-startup.sh; echo ""; read -p "Press Enter to close..."'
fi
```

Let me break down the `notify-send` flags:
- `--icon=computer` — uses the system "computer" icon
- `--app-name="Daily Maintenance"` — how GNOME identifies this notification source
- `--action="run=🚀 Run Morning Script"` — creates a clickable button. `run` is the action ID, and the text after `=` is the button label
- `--wait` — keeps the process alive until you interact with the notification

When you click the button, `notify-send` outputs the action ID (`run`) to stdout. The `if` block catches that and opens a GNOME Terminal running the maintenance script. The `read -p "Press Enter to close..."` at the end keeps the terminal open so you can review the output.

**A note on why `notify-send` instead of Python's libnotify:**

I originally used Python's `gi.repository.Notify` with a `GLib.MainLoop` to handle notification actions. It worked great — until it didn't. After a GNOME Shell update, the action callbacks stopped firing. The notification would show up, but clicking it did nothing. After debugging, I discovered that GNOME Shell's notification daemon was dismissing the notification before the Python GLib MainLoop could process the `ActionInvoked` D-Bus signal. Switching to `notify-send --action --wait` fixed it immediately because `notify-send` is GNOME's own tool and handles the D-Bus plumbing correctly. Sometimes the simplest tool is the right one.

### The deep-clean notification

The Sunday notification follows the same pattern but with disk-focused stats:

```python
def get_disk_stats():
    lines = []
    # Disk usage percentage
    st = os.statvfs("/")
    disk_pct = int(((disk_total - disk_free) / disk_total) * 100)

    # Gradle cache size
    result = subprocess.run(["du", "-sm", os.path.expanduser("~/.gradle/caches")], ...)

    # Journal log size
    result = subprocess.run(["journalctl", "--disk-usage"], ...)

    # Trash size
    result = subprocess.run(["du", "-sm", trash_path], ...)
```

It shows you how full your disk is, how big your Gradle cache has gotten, how much space journal logs are consuming, and how much junk is in the trash — all before you decide whether to run the cleanup.

---

## Part 3: The Automation Layer

Scripts and notifications are useless if I have to remember to run them. This is where systemd user timers come in.

### Why systemd timers instead of cron?

Cron is fine for servers. But for a desktop:
- Cron doesn't know about your graphical session — it can't send desktop notifications
- Cron doesn't have `OnStartupSec` — you can't say "run this 60 seconds after I log in"
- Cron doesn't have `Persistent=true` — if the machine was off when a job was scheduled, cron just skips it
- Systemd user timers run in your user session, so they inherit your D-Bus session, display server, and environment variables

### The morning timer

Two files, placed in `~/.config/systemd/user/`:

**`morning-reminder.timer`:**

```ini
[Unit]
Description=Remind to run morning script after login

[Timer]
OnStartupSec=60
Unit=morning-reminder.service

[Install]
WantedBy=timers.target
```

`OnStartupSec=60` means "60 seconds after the user session starts." This gives GNOME time to fully load before firing a notification. `WantedBy=timers.target` tells systemd to start this timer automatically when timers are activated (i.e., at login).

**`morning-reminder.service`:**

```ini
[Unit]
Description=Morning startup script reminder
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=/home/rhymezxcode/morning-notify.sh
TimeoutStartSec=180
TimeoutStopSec=10
```

`After=graphical-session.target` ensures the graphical session is up before running. `TimeoutStartSec=180` gives the notification script up to 3 minutes (the notification waits for you to click it). `TimeoutStopSec=10` ensures a clean shutdown if systemd needs to stop the service.

### The Sunday timer

**`deepclean-reminder.timer`:**

```ini
[Unit]
Description=Remind to run deep clean every Sunday

[Timer]
OnCalendar=Sun *-*-* 11:00:00
Persistent=true
Unit=deepclean-reminder.service

[Install]
WantedBy=timers.target
```

`OnCalendar=Sun *-*-* 11:00:00` fires every Sunday at 11:00 AM. `Persistent=true` is the magic — if your laptop was off or asleep at 11 AM Sunday, the timer fires the next time you're on. You won't miss a cleanup just because you slept in.

**`deepclean-reminder.service`:**

```ini
[Unit]
Description=Weekly deep clean reminder
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=/home/rhymezxcode/deepclean-notify.sh
TimeoutStartSec=180
TimeoutStopSec=10
```

### Enabling the timers

After creating the files, you enable them once:

```bash
systemctl --user daemon-reload
systemctl --user enable --now morning-reminder.timer
systemctl --user enable --now deepclean-reminder.timer
```

`daemon-reload` tells systemd to re-read its config files. `enable --now` both enables the timer for future logins and starts it immediately.

You can check their status anytime:

```bash
systemctl --user list-timers --all
```

Which shows you:

```
NEXT                          LEFT     UNIT                       ACTIVATES
Sun 2026-03-29 11:00:00 WAT   3 days  deepclean-reminder.timer   deepclean-reminder.service
-                              -       morning-reminder.timer     morning-reminder.service
```

---

## Part 4: The Desktop Entry

For times when I want to trigger the morning script from the GNOME Activities overview (or from any launcher), there's a `.desktop` file:

**`~/.local/share/applications/morning-startup.desktop`:**

```ini
[Desktop Entry]
Type=Application
Name=Morning Startup
Comment=Run daily startup maintenance script
Exec=gnome-terminal -- bash -c 'bash ~/daily-startup.sh; echo ""; read -p "Press Enter to close..."'
Icon=dialog-information
Terminal=false
Categories=Utility;
NoDisplay=true
```

`NoDisplay=true` hides it from the app grid but keeps it searchable. `Terminal=false` tells GNOME not to try opening a terminal itself — the `Exec` line already handles that with `gnome-terminal --`. The `--` tells GNOME Terminal that everything after it is the command to run.

---

## Part 5: The Aliases

The final piece. In `~/.bashrc`:

```bash
# Custom script aliases
alias morning="bash ~/daily-startup.sh"
alias deepclean="bash ~/deep-clean.sh"
alias pcaudit="bash ~/pc-audit.sh"
alias autorun="bash ~/daily-startup.sh && bash ~/deep-clean.sh && bash ~/pc-audit.sh"
```

Now from any terminal:
- `morning` — run the daily maintenance
- `deepclean` — run the weekly deep clean
- `pcaudit` — run a full system audit
- `autorun` — run all three in sequence

The `&&` in `autorun` means each script only runs if the previous one succeeded. If the morning script fails, the deep clean and audit won't run on a potentially broken system.

After adding these to `~/.bashrc`, either open a new terminal or run:

```bash
source ~/.bashrc
```

---

## How It All Comes Together

Here's what a typical day looks like:

**7:45 AM** — I open my laptop. Ubuntu loads GNOME, which starts my user systemd session.

**7:46 AM** — The `morning-reminder.timer` fires (60 seconds after login). It runs `morning-notify.sh`.

**7:46 AM** — A beautiful notification appears in the top-right corner:

> ☀️ Good Morning, rhymezxcode!
>
> **Thursday, March 26, 2026 · 7:46 AM**
>
> ⛅ Partly Cloudy, 28°C · 65% humidity — Lagos
>
> 🟢 RAM 34% of 15.4 GB
> 🟢 Disk 45% used · 120 GB free
> 🔋 Battery 87%
> 📊 Load 0.42
>
> *💬 "One commit at a time."*
>
> **[🚀 Run Morning Script]**

**7:46 AM** — I click the button. A GNOME Terminal opens and runs through the full morning maintenance — health check, updates, daemon cleanup — with colored output and spinners.

**Sunday 11:00 AM** — A different notification appears:

> 🧹 Sunday Deep Clean
>
> Your system could use a weekly cleanup!
>
> 🟢 Disk: 47% used · 118 GB free of 233 GB
> 📦 Gradle cache: 342 MB
> 📜 Journal logs: 156M
>
> *💬 "A clean machine is a fast machine."*
>
> **[🧹 Run Deep Clean]**

**Anytime** — I type `pcaudit` in a terminal and get a comprehensive report on my hardware, software, storage, performance, and security.

---

## Setting This Up on Your Machine

If you want to replicate this setup, here's the order:

**1. Create the scripts:**

```bash
# Place your scripts in ~/
touch ~/daily-startup.sh ~/deep-clean.sh ~/pc-audit.sh
touch ~/morning-notify.sh ~/deepclean-notify.sh
chmod +x ~/daily-startup.sh ~/deep-clean.sh ~/pc-audit.sh
chmod +x ~/morning-notify.sh ~/deepclean-notify.sh
```

**2. Add the aliases to `~/.bashrc`:**

```bash
echo '' >> ~/.bashrc
echo '# Custom script aliases' >> ~/.bashrc
echo 'alias morning="bash ~/daily-startup.sh"' >> ~/.bashrc
echo 'alias deepclean="bash ~/deep-clean.sh"' >> ~/.bashrc
echo 'alias pcaudit="bash ~/pc-audit.sh"' >> ~/.bashrc
echo 'alias autorun="bash ~/daily-startup.sh && bash ~/deep-clean.sh && bash ~/pc-audit.sh"' >> ~/.bashrc
source ~/.bashrc
```

**3. Create the systemd timer and service files:**

```bash
mkdir -p ~/.config/systemd/user

# Create morning timer
cat > ~/.config/systemd/user/morning-reminder.timer << 'EOF'
[Unit]
Description=Remind to run morning script after login

[Timer]
OnStartupSec=60
Unit=morning-reminder.service

[Install]
WantedBy=timers.target
EOF

# Create morning service
cat > ~/.config/systemd/user/morning-reminder.service << 'EOF'
[Unit]
Description=Morning startup script reminder
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=/home/YOUR_USERNAME/morning-notify.sh
TimeoutStartSec=180
TimeoutStopSec=10
EOF

# Create deep-clean timer
cat > ~/.config/systemd/user/deepclean-reminder.timer << 'EOF'
[Unit]
Description=Remind to run deep clean every Sunday

[Timer]
OnCalendar=Sun *-*-* 11:00:00
Persistent=true
Unit=deepclean-reminder.service

[Install]
WantedBy=timers.target
EOF

# Create deep-clean service
cat > ~/.config/systemd/user/deepclean-reminder.service << 'EOF'
[Unit]
Description=Weekly deep clean reminder
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=/home/YOUR_USERNAME/deepclean-notify.sh
TimeoutStartSec=180
TimeoutStopSec=10
EOF
```

Replace `YOUR_USERNAME` with your actual username.

**4. Enable the timers:**

```bash
systemctl --user daemon-reload
systemctl --user enable --now morning-reminder.timer
systemctl --user enable --now deepclean-reminder.timer
```

**5. Create the desktop entry (optional):**

```bash
cat > ~/.local/share/applications/morning-startup.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Morning Startup
Comment=Run daily startup maintenance script
Exec=gnome-terminal -- bash -c 'bash ~/daily-startup.sh; echo ""; read -p "Press Enter to close..."'
Icon=dialog-information
Terminal=false
Categories=Utility;
NoDisplay=true
EOF
```

**6. Verify everything works:**

```bash
# Test the scripts manually
morning
deepclean
pcaudit

# Check timer status
systemctl --user list-timers

# Test a notification manually
bash ~/morning-notify.sh
```

---

## Lessons Learned

**Keep it interactive.** The scripts ask before doing anything destructive. "Clean Gradle cache? [Y/n]" is way better than silently deleting 2 GB of files.

**Use timeouts everywhere.** Network calls hang. Package managers lock. Firmware checks stall. Every external operation in my scripts has a timeout. A stuck `apt update` will never block my morning.

**Color-code everything.** Green for good, yellow for "notice this," red for "fix this." When you're scanning terminal output before your first coffee, color is the difference between useful and overwhelming.

**Fail gracefully.** No internet? Skip network tasks. `sensors` not installed? Skip temperature. No battery? Skip battery. The scripts work on any Ubuntu machine — they just show what's available.

**`notify-send --wait` is your friend on GNOME.** If you need notification actions (clickable buttons) on modern GNOME Shell, use `notify-send` with `--action` and `--wait`. Don't fight with `libnotify` Python bindings — they have known issues with GNOME Shell's D-Bus action signaling on Wayland.

---

## Wrapping Up

This entire setup is just bash, Python for data gathering, `notify-send` for notifications, and systemd for scheduling. No external dependencies. No daemons running in the background. No apps to install. Everything lives in your home directory, and you can version-control it with a simple `git init`.

My ThinkPad boots up, greets me by name with the weather, tells me how my system is doing, and offers to run maintenance with a single click. On Sundays, it nudges me to clean up. Anytime I'm curious, I type `pcaudit` and get a full diagnostic.

It took a weekend to build. It saves me hours every month. And honestly? Opening my laptop to a personalized good-morning notification with a motivational quote just makes the whole day start better.

Your machine works hard for you. Build something that takes care of it in return.

---

*All scripts referenced in this article are available as standalone files you can adapt for your own setup. The setup works on Ubuntu 24.04 with GNOME Shell but should work on any GNOME-based distribution with minimal changes.*
