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

    if [ -n "$output" ]; then
        echo "$output" | tail -3 | sed 's/^/  /'
    fi
    return 0
}

TOTAL_FREED=0

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║            DEEP CLEAN                        ║"
echo "  ║   Free disk space · Kill bloat · Stay fast   ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

DISK_BEFORE=$(df / --output=used | tail -1 | tr -d ' ')
echo -e "  Disk used before: $(df -h / --output=used | tail -1 | tr -d ' ')"
echo -e "  ${DIM}$(date '+%A, %B %d %Y · %I:%M %p')${NC}"

# ─────────────────────────────────────────────────
# 1. STOP ALL BUILD DAEMONS
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 1. STOP BUILD DAEMONS${NC}"
echo ""

DAEMONS_STOPPED=0
for PROJECT_DIR in ~/StudioProjects/personal/*/gradlew ~/StudioProjects/work/*/gradlew; do
    if [ -f "$PROJECT_DIR" ]; then
        DIR=$(dirname "$PROJECT_DIR")
        NAME=$(basename "$DIR")
        timeout 10 "$PROJECT_DIR" --stop -p "$DIR" 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Stopped Gradle in ${NAME}"
        DAEMONS_STOPPED=1
    fi
done

if pgrep -f "GradleDaemon" &>/dev/null; then
    pkill -f "GradleDaemon" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Killed Gradle daemons"
    DAEMONS_STOPPED=1
fi

if pgrep -f "KotlinCompileDaemon" &>/dev/null; then
    pkill -f "KotlinCompileDaemon" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Killed Kotlin daemons"
    DAEMONS_STOPPED=1
fi

if [ "$DAEMONS_STOPPED" -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} No build daemons running"
else
    echo -e "  ${GREEN}✓${NC} All build daemons stopped"
fi

# ─────────────────────────────────────────────────
# 2. CLEAN PROJECT BUILD FOLDERS
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 2. PROJECT BUILD CACHES${NC}"
echo ""

PROJECT_TOTAL=0
PROJECT_LIST=""
echo -e "  ${BOLD}Project build/cache sizes:${NC}"

for DIR in ~/StudioProjects/personal/*/ ~/StudioProjects/work/*/; do
    [ ! -d "$DIR" ] && continue
    NAME=$(basename "$DIR")
    BUILD_SIZE=$(du -sb "$DIR/build" "$DIR/.gradle" "$DIR/app/build" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    if [ "$BUILD_SIZE" -gt 10485760 ]; then
        echo -e "    ${YELLOW}$(bytes_to_human $BUILD_SIZE)${NC}\t${NAME}"
        PROJECT_TOTAL=$((PROJECT_TOTAL + BUILD_SIZE))
        PROJECT_LIST="$PROJECT_LIST $DIR"
    fi
done

if [ "$PROJECT_TOTAL" -gt 0 ]; then
    echo ""
    echo -e "  Total cleanable: ${YELLOW}$(bytes_to_human $PROJECT_TOTAL)${NC}"
    read -t 30 -p "  Clean all project build caches? [Y/n]: " PROJ_ANSWER
    PROJ_ANSWER=${PROJ_ANSWER:-Y}
    if [[ "$PROJ_ANSWER" =~ ^[Yy]$ ]]; then
        for DIR in ~/StudioProjects/personal/*/ ~/StudioProjects/work/*/; do
            [ ! -d "$DIR" ] && continue
            rm -rf "$DIR/build" "$DIR/.gradle" "$DIR/app/build" 2>/dev/null
            for MODULE in "$DIR"/*/build; do
                rm -rf "$MODULE" 2>/dev/null
            done
        done
        TOTAL_FREED=$((TOTAL_FREED + PROJECT_TOTAL))
        echo -e "  ${GREEN}✓${NC} Project caches cleaned ($(bytes_to_human $PROJECT_TOTAL))"
    else
        echo -e "  ${YELLOW}⏭${NC}  Skipped"
    fi
else
    echo -e "  ${GREEN}✓${NC} Project caches are clean"
fi

# ─────────────────────────────────────────────────
# 3. GRADLE GLOBAL CACHE
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 3. GRADLE GLOBAL CACHE${NC}"
echo ""

GRADLE_BUILD_CACHE=$(du -sb ~/.gradle/caches/build-cache-* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
GRADLE_TRANSFORMS=$(du -sb ~/.gradle/caches/transforms-* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
GRADLE_DAEMON_LOGS=$(du -sb ~/.gradle/daemon/*/daemon-*.out.log 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
GRADLE_TOTAL=$((GRADLE_BUILD_CACHE + GRADLE_TRANSFORMS + GRADLE_DAEMON_LOGS))

echo -e "    Build cache:   $(bytes_to_human $GRADLE_BUILD_CACHE)"
echo -e "    Transforms:    $(bytes_to_human $GRADLE_TRANSFORMS)"
echo -e "    Daemon logs:   $(bytes_to_human $GRADLE_DAEMON_LOGS)"
echo -e "    ${BOLD}Total:         $(bytes_to_human $GRADLE_TOTAL)${NC}"

if [ "$GRADLE_TOTAL" -gt 52428800 ]; then
    echo ""
    read -t 30 -p "  Clean Gradle global caches? [Y/n]: " GC_ANSWER
    GC_ANSWER=${GC_ANSWER:-Y}
    if [[ "$GC_ANSWER" =~ ^[Yy]$ ]]; then
        rm -rf ~/.gradle/caches/build-cache-* 2>/dev/null
        rm -rf ~/.gradle/caches/transforms-* 2>/dev/null
        rm -rf ~/.gradle/daemon/*/daemon-*.out.log 2>/dev/null
        rm -rf ~/.gradle/caches/journal-* 2>/dev/null
        TOTAL_FREED=$((TOTAL_FREED + GRADLE_TOTAL))
        echo -e "  ${GREEN}✓${NC} Gradle global cache cleaned ($(bytes_to_human $GRADLE_TOTAL))"
    else
        echo -e "  ${YELLOW}⏭${NC}  Skipped"
    fi
else
    echo -e "  ${GREEN}✓${NC} Gradle cache is small"
fi

# ─────────────────────────────────────────────────
# 4. ANDROID STUDIO CACHE
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 4. ANDROID STUDIO CACHE${NC}"
echo ""

AS_VERSIONS=($(ls -d ~/.cache/Google/AndroidStudio* 2>/dev/null | sort -V))
if [ "${#AS_VERSIONS[@]}" -gt 1 ]; then
    LATEST="${AS_VERSIONS[-1]}"
    echo -e "  ${DIM}Latest: $(basename "$LATEST") (keeping)${NC}"
    for OLD_VER in "${AS_VERSIONS[@]}"; do
        if [ "$OLD_VER" != "$LATEST" ]; then
            OLD_SIZE=$(du -sb "$OLD_VER" 2>/dev/null | awk '{print $1}')
            OLD_NAME=$(basename "$OLD_VER")
            echo -e "  ${YELLOW}Old version: ${OLD_NAME} ($(bytes_to_human $OLD_SIZE))${NC}"
            read -t 30 -p "  Delete $OLD_NAME cache? [Y/n]: " OLD_ANSWER
            OLD_ANSWER=${OLD_ANSWER:-Y}
            if [[ "$OLD_ANSWER" =~ ^[Yy]$ ]]; then
                rm -rf "$OLD_VER"
                TOTAL_FREED=$((TOTAL_FREED + OLD_SIZE))
                echo -e "  ${GREEN}✓${NC} ${OLD_NAME} cache deleted ($(bytes_to_human $OLD_SIZE))"
            else
                echo -e "  ${YELLOW}⏭${NC}  Skipped"
            fi
        fi
    done
else
    echo -e "  ${GREEN}✓${NC} No old AS versions to clean"
fi

AS_LOG_SIZE=$(du -sb ~/.cache/Google/AndroidStudio*/log/ 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
if [ "$AS_LOG_SIZE" -gt 52428800 ]; then
    rm -rf ~/.cache/Google/AndroidStudio*/log/*.log.* 2>/dev/null
    TOTAL_FREED=$((TOTAL_FREED + AS_LOG_SIZE))
    echo -e "  ${GREEN}✓${NC} AS log files cleaned ($(bytes_to_human $AS_LOG_SIZE))"
else
    echo -e "  ${GREEN}✓${NC} AS logs are small ($(bytes_to_human $AS_LOG_SIZE))"
fi

# ─────────────────────────────────────────────────
# 5. SYSTEM CACHES
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 5. SYSTEM CLEANUP${NC}"
echo ""

if run_with_timeout "$TIMEOUT_SECS" "Cleaning APT cache..." sudo apt autoremove -y -qq; then
    echo -e "  ${GREEN}✓${NC} APT autoremove done"
fi
if run_with_timeout "$TIMEOUT_SECS" "Cleaning APT package cache..." sudo apt clean -qq; then
    echo -e "  ${GREEN}✓${NC} APT cache cleaned"
fi

sudo journalctl --vacuum-time=3d --vacuum-size=100M 2>&1 | grep -oE "freed.*|Vacuuming.*" | head -2 | sed 's/^/  /'
echo -e "  ${GREEN}✓${NC} Journal logs trimmed"

THUMB_SIZE=$(du -sb ~/.cache/thumbnails/ 2>/dev/null | awk '{print $1+0}')
if [ "$THUMB_SIZE" -gt 52428800 ]; then
    rm -rf ~/.cache/thumbnails/*
    TOTAL_FREED=$((TOTAL_FREED + THUMB_SIZE))
    echo -e "  ${GREEN}✓${NC} Thumbnail cache cleaned ($(bytes_to_human $THUMB_SIZE))"
else
    echo -e "  ${GREEN}✓${NC} Thumbnails OK ($(bytes_to_human $THUMB_SIZE))"
fi

TRASH_SIZE=$(du -sb ~/.local/share/Trash/ 2>/dev/null | awk '{print $1+0}')
if [ "$TRASH_SIZE" -gt 1048576 ]; then
    echo -e "  ${YELLOW}Trash: $(bytes_to_human $TRASH_SIZE)${NC}"
    read -t 30 -p "  Empty trash? [Y/n]: " TRASH_ANSWER
    TRASH_ANSWER=${TRASH_ANSWER:-Y}
    if [[ "$TRASH_ANSWER" =~ ^[Yy]$ ]]; then
        rm -rf ~/.local/share/Trash/*
        TOTAL_FREED=$((TOTAL_FREED + TRASH_SIZE))
        echo -e "  ${GREEN}✓${NC} Trash emptied ($(bytes_to_human $TRASH_SIZE))"
    else
        echo -e "  ${YELLOW}⏭${NC}  Skipped"
    fi
else
    echo -e "  ${GREEN}✓${NC} Trash is empty"
fi

find /tmp -maxdepth 1 -user "$(whoami)" -mtime +3 -exec rm -rf {} + 2>/dev/null
echo -e "  ${GREEN}✓${NC} Old temp files cleaned"

SNAP_OLD=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}')
if [ -n "$SNAP_OLD" ]; then
    SNAP_COUNT=$(echo "$SNAP_OLD" | wc -l)
    echo -e "  ${YELLOW}${SNAP_COUNT} old snap revisions found${NC}"
    read -t 30 -p "  Remove old snap revisions? [Y/n]: " SNAP_OLD_ANSWER
    SNAP_OLD_ANSWER=${SNAP_OLD_ANSWER:-Y}
    if [[ "$SNAP_OLD_ANSWER" =~ ^[Yy]$ ]]; then
        echo "$SNAP_OLD" | while read NAME REV; do
            echo -e "  ${DIM}  Removing ${NAME} rev ${REV}...${NC}"
            sudo snap remove "$NAME" --revision="$REV" 2>/dev/null
        done
        echo -e "  ${GREEN}✓${NC} Old snap revisions removed"
    else
        echo -e "  ${YELLOW}⏭${NC}  Skipped"
    fi
else
    echo -e "  ${GREEN}✓${NC} No old snap revisions"
fi

# ─────────────────────────────────────────────────
# 6. LARGE FILE FINDER
# ─────────────────────────────────────────────────
divider
echo -e "${BOLD} 6. LARGE FILES (>200MB in home)${NC}"
echo ""

echo -e "  ${DIM}Scanning (this may take a moment)...${NC}"
LARGE_FILES=$(find ~/ -maxdepth 4 -type f -size +200M \
    -not -path "*/Android/Sdk/*" \
    -not -path "*/.gradle/caches/modules*" \
    -not -path "*/.gradle/wrapper/*" \
    -not -path "*/.jdks/*" \
    -not -path "*/.local/share/JetBrains/*" \
    -not -path "*/snap/*" \
    -not -path "*/.cache/Google/AndroidStudio*/aia/*" \
    2>/dev/null | head -15)

if [ -n "$LARGE_FILES" ]; then
    echo -e "  These large files might be worth reviewing:"
    echo "$LARGE_FILES" | while read FILE; do
        SIZE=$(du -sh "$FILE" 2>/dev/null | awk '{print $1}')
        SHORT=$(echo "$FILE" | sed "s|$HOME|~|")
        echo -e "    ${YELLOW}${SIZE}${NC}\t${SHORT}"
    done
else
    echo -e "  ${GREEN}✓${NC} No unexpected large files found"
fi

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

DISK_AFTER=$(df / --output=used | tail -1 | tr -d ' ')
ACTUAL_FREED=$(( (DISK_BEFORE - DISK_AFTER) * 1024 ))
if [ "$ACTUAL_FREED" -gt 0 ]; then
    echo -e "  ${GREEN}${BOLD}Freed $(bytes_to_human $ACTUAL_FREED) of disk space!${NC}"
else
    echo -e "  ${GREEN}${BOLD}System is clean!${NC}"
fi

echo -e "  Disk now: $(df -h / --output=used,avail,pcent | tail -1 | awk '{print $1 " used, " $2 " free (" $3 ")"}')"
echo ""
