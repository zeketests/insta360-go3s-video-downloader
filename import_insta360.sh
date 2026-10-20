#!/usr/bin/env bash
#
# Import photos/videos from Insta360 GO 3S (USB mass storage) into a local
# folder, organized by capture date. Skips files already imported. Optionally
# offers to delete files off the camera after copy, with a confirmation prompt.
# Run with --help for options.

set -euo pipefail

# Colors
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
DEST_ROOT="$HOME/Movies/Insta360"
EXTS=(mp4 MP4 mov MOV jpg JPG jpeg JPEG dng DNG insv INSV insp INSP)
# Fixed path (not $TMPDIR): the launchd agent and Terminal see different TMPDIRs.
LOCK_FILE="$HOME/Library/Caches/insta360-import.pid"
AGENT_LABEL="local.insta360-import"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

DRY_RUN=0
ASSUME_YES=0
NO_DELETE=0
MODE=import

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

  -n, --dry-run          Show what would be copied; change nothing.
  -y, --yes              Don't prompt; take each prompt's default
                         (copy, don't re-copy, don't delete, eject).
  -d, --dest DIR         Import into DIR (default: ~/Movies/Insta360).
      --no-delete        Never offer to delete files from the camera.
      --install-autorun  Open this script in Terminal whenever the camera
                         is plugged in.
      --uninstall-autorun
                         Remove the auto-run agent.
  -h, --help             Show this help.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -d|--dest)
            if [ $# -lt 2 ]; then
                echo "$1 needs a directory." >&2
                exit 2
            fi
            DEST_ROOT="$2"
            shift
            ;;
        --dest=*) DEST_ROOT="${1#--dest=}" ;;
        --no-delete) NO_DELETE=1 ;;
        --install-autorun) MODE=install ;;
        --uninstall-autorun) MODE=uninstall ;;
        --autorun-check) MODE=autorun ;;   # internal: run by the launchd agent
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
DEST_ROOT="${DEST_ROOT%/}"

find_camera_volume() {
    for vol in /Volumes/*/; do
        [ -d "${vol}DCIM" ] && [ "$vol" != "/Volumes/Macintosh HD/" ] && echo "$vol" && return 0
    done
    return 1
}

install_autorun() {
    local path="${SCRIPT_PATH//&/&amp;}"
    path="${path//</&lt;}"
    mkdir -p "$(dirname "$AGENT_PLIST")"
    cat >"$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$path</string>
        <string>--autorun-check</string>
    </array>
    <key>StartOnMount</key>
    <true/>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
    echo "${GREEN}Auto-run installed.${RESET} Plugging in the camera now opens the importer in Terminal."
    echo "If you move this script, run --install-autorun again from its new location."
}

uninstall_autorun() {
    launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
    echo "Auto-run removed."
}

# Run by launchd on every volume mount: open the importer if a camera is
# attached and no import is already running.
autorun_check() {
    sleep 2   # let the volume finish mounting
    find_camera_volume >/dev/null || return 0
    if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
        return 0
    fi
    open -a Terminal "$SCRIPT_PATH"
}

case "$MODE" in
    install) install_autorun; exit 0 ;;
    uninstall) uninstall_autorun; exit 0 ;;
    autorun) autorun_check; exit 0 ;;
esac

on_exit() {
    rm -f "$LOCK_FILE"
    # Keep the window open when launched from Finder/auto-run, not when scripted.
    if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
        echo
        read -r -p "Press Enter to close..." _ || true
    fi
}
trap on_exit EXIT
mkdir -p "$(dirname "$LOCK_FILE")"
echo $$ >"$LOCK_FILE"

# ask PROMPT y|n: succeeds on yes. The second arg is the default, used on
# empty input and always with --yes.
ask() {
    local prompt="$1" def="$2" hint="[y/N]" ans=""
    [ "$def" = y ] && hint="[Y/n]"
    if [ "$ASSUME_YES" -eq 1 ]; then
        echo "$prompt $hint $def"
        [ "$def" = y ]
        return
    fi
    read -r -p "$prompt $hint " ans || true
    if [ "$def" = y ]; then
        [[ ! "$ans" =~ ^[Nn]$ ]]
    else
        [[ "$ans" =~ ^[Yy]$ ]]
    fi
}

human_size() {
    awk -v b="$1" 'BEGIN {
        split("B KB MB GB TB", u); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf "%.1f %s", b, u[i]
    }'
}

# Free bytes on the disk holding $1 (or its nearest existing parent).
free_bytes() {
    local d="$1"
    while [ ! -d "$d" ]; do d=$(dirname "$d"); done
    df -Pk "$d" | awk 'NR == 2 { print $4 * 1024 }'
}

offer_eject() {
    ask "Eject the camera now?" y || return 0
    if diskutil eject "$SRC_VOL" >/dev/null; then
        echo "${GREEN}Camera ejected. Safe to unplug.${RESET}"
    else
        echo "${YELLOW}Could not eject camera (in use?). Eject it from Finder before unplugging.${RESET}"
    fi
}

# Capture date/time from the camera's file name, e.g.
#   VID_20250903_142501_00_012.mp4 -> 2025-09-03 / 142501
# The file's mtime can be off (clock reset, FAT timezone quirks), so it's only
# the fallback for names that don't follow this pattern.
name_time_re='^[A-Za-z]+_([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{6})_'
mtime_date() { date -r "$(stat -f%m "$1")" +%Y-%m-%d; }
capture_date() {
    local b
    b=$(basename "$1")
    if [[ "$b" =~ $name_time_re ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    else
        mtime_date "$1"
    fi
}
capture_time() {
    local b
    b=$(basename "$1")
    if [[ "$b" =~ $name_time_re ]]; then
        echo "${BASH_REMATCH[4]}"
    else
        date -r "$(stat -f%m "$1")" +%H%M%S
    fi
}

same_size() { [ -f "$1" ] && [ "$(stat -f%z "$1")" = "$2" ]; }

# Newline-delimited destinations already claimed by this run (bash 3.2 has no
# associative arrays).
planned=$'\n'
is_planned() {
    case "$planned" in
        *$'\n'"$1"$'\n'*) return 0 ;;
    esac
    return 1
}

# Sets DEST for file $1 (size $2), and DEST_EXISTS=1 if a same-size copy is
# already there. Never picks a path holding a different file or one already
# claimed by another file in this run.
pick_dest() {
    local f="$1" size="$2" fname base ext day_dir old_dir stamp d n=1
    fname=$(basename "$f")
    base="${fname%.*}"
    ext="${fname##*.}"
    day_dir="$DEST_ROOT/$(capture_date "$f")"
    old_dir="$DEST_ROOT/$(mtime_date "$f")"
    DEST_EXISTS=0
    # Earlier versions filed by mtime date; a copy there counts as imported.
    if [ "$old_dir" != "$day_dir" ] && same_size "$old_dir/$fname" "$size"; then
        DEST="$old_dir/$fname"
        DEST_EXISTS=1
        return
    fi
    # Same name, different size: try NAME_HHMMSS.ext, then NAME_HHMMSS_2.ext, ...
    stamp=$(capture_time "$f")
    d="$day_dir/$fname"
    while :; do
        if same_size "$d" "$size"; then
            DEST="$d"
            DEST_EXISTS=1
            return
        fi
        if [ ! -e "$d" ] && ! is_planned "$d"; then
            DEST="$d"
            return
        fi
        n=$((n + 1))
        if [ "$n" -eq 2 ]; then
            d="$day_dir/${base}_${stamp}.${ext}"
        else
            d="$day_dir/${base}_${stamp}_$((n - 1)).${ext}"
        fi
    done
}

SRC_VOL="$(find_camera_volume || true)"
if [ -z "${SRC_VOL:-}" ]; then
    echo "${RED}No camera found.${RESET} Plug in Insta360 GO 3S via USB and make sure it shows up under /Volumes." >&2
    exit 1
fi

echo "${CYAN}Camera found at: $SRC_VOL${RESET}"

# Build a glob find expression for our extensions.
find_args=()
for ext in "${EXTS[@]}"; do
    find_args+=(-iname "*.${ext}" -o)
done
unset 'find_args[${#find_args[@]}-1]'   # drop trailing -o

candidates=()
while IFS= read -r -d '' f; do
    candidates+=("$f")
# ! -name '._*': skip AppleDouble files macOS leaves on FAT volumes.
done < <(find "${SRC_VOL}DCIM" -type f ! -name '._*' \( "${find_args[@]}" \) -print0)

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "No media files found on camera."
    exit 0
fi

echo "${BOLD}Found ${#candidates[@]} file(s) on camera.${RESET}"

# Plan every copy up front so free space can be checked before starting.
plan_srcs=()
plan_dests=()  # parallel to plan_srcs
skipped_paths=()
skipped_dests=()  # parallel to skipped_paths: existing local copy
need_bytes=0

for f in "${candidates[@]}"; do
    size=$(stat -f%z "$f")
    pick_dest "$f" "$size"
    if [ "$DEST_EXISTS" -eq 1 ]; then
        skipped_paths+=("$f")
        skipped_dests+=("$DEST")
        echo "${YELLOW}Already imported:${RESET} $(basename "$f")"
    else
        plan_srcs+=("$f")
        plan_dests+=("$DEST")
        planned+="$DEST"$'\n'
        need_bytes=$((need_bytes + size))
        echo "${GREEN}New:${RESET} $(basename "$f") -> ${DEST#$HOME/}"
    fi
done

echo
echo "${BOLD}${#plan_srcs[@]} new file(s) to copy ($(human_size "$need_bytes")), ${#skipped_paths[@]} already imported.${RESET}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run: nothing copied or deleted."
    exit 0
fi

copied=0
copied_paths=()
copied_dests=()   # parallel to copied_paths: where each file was copied to
dest_dirs=()

add_dest_dir() {
    case " ${dest_dirs[*]-} " in
        *" $1 "*) ;;
        *) dest_dirs+=("$1") ;;
    esac
}

if [ "${#plan_srcs[@]}" -gt 0 ]; then
    free=$(free_bytes "$DEST_ROOT")
    if [ "$need_bytes" -gt "$free" ]; then
        echo "${RED}Not enough space:${RESET} need $(human_size "$need_bytes"), $(human_size "$free") free on the disk holding $DEST_ROOT." >&2
        exit 1
    fi

    if ! ask "Copy ${#plan_srcs[@]} file(s) to ${DEST_ROOT}?" y; then
        echo "Cancelled. Nothing copied."
        exit 0
    fi

    for i in "${!plan_srcs[@]}"; do
        f="${plan_srcs[$i]}"
        dest="${plan_dests[$i]}"
        mkdir -p "$(dirname "$dest")"
        rsync -a --progress "$f" "$dest"
        copied_paths+=("$f")
        copied_dests+=("$dest")
        add_dest_dir "$(dirname "$dest")"
        copied=$((copied + 1))
        echo "${GREEN}Copied:${RESET} $(basename "$f") -> ${dest#$HOME/}"
    done
fi

echo
echo "${BOLD}Done.${RESET} Copied: ${GREEN}$copied${RESET}, skipped (already imported): ${YELLOW}${#skipped_paths[@]}${RESET}."

if [ "${#skipped_paths[@]}" -gt 0 ] &&
    ask "Re-copy the ${#skipped_paths[@]} already-imported file(s) anyway (overwrite)?" n; then
    for i in "${!skipped_paths[@]}"; do
        f="${skipped_paths[$i]}"
        dest="${skipped_dests[$i]}"
        # --ignore-times: rsync -a preserved mtime, so quick-check would skip it.
        rsync -a --progress --ignore-times "$f" "$dest"
        copied_paths+=("$f")
        copied_dests+=("$dest")
        add_dest_dir "$(dirname "$dest")"
        copied=$((copied + 1))
        echo "${GREEN}Copied:${RESET} $(basename "$f") -> ${dest#$HOME/}"
    done
    # Now tracked as copied; don't count them twice below.
    skipped_paths=()
    skipped_dests=()
fi

# Delete candidates: files copied this run plus files already imported
# earlier (so a later run can still clear them off the camera).
# ${arr[@]+...} guard: bash 3.2 (macOS /bin/bash) + set -u errors on empty arrays.
delete_paths=(${copied_paths[@]+"${copied_paths[@]}"} ${skipped_paths[@]+"${skipped_paths[@]}"})
delete_dests=(${copied_dests[@]+"${copied_dests[@]}"} ${skipped_dests[@]+"${skipped_dests[@]}"})

for d in ${dest_dirs[@]+"${dest_dirs[@]}"}; do
    open "$d"
done

if [ "$NO_DELETE" -eq 1 ] || [ "${#delete_paths[@]}" -eq 0 ]; then
    offer_eject
    exit 0
fi

# Key shared by a video and its .lrv proxy, e.g.
#   VID_20250903_142501_00_012.mp4 / LRV_20250903_142501_01_012.lrv -> 20250903_142501_012
# Prints nothing for names that don't follow this pattern.
media_key_re='^[A-Za-z]+_([0-9]{8}_[0-9]{6})_[0-9]{2}_([0-9]+)\.'
media_key() {
    local b
    b=$(basename "$1")
    if [[ "$b" =~ $media_key_re ]]; then
        echo "${BASH_REMATCH[1]}_${BASH_REMATCH[2]}"
    fi
}

# Space-delimited key list (bash 3.2 has no associative arrays).
copied_keys=" "
for f in "${delete_paths[@]}"; do
    k=$(media_key "$f")
    [ -n "$k" ] && copied_keys+="$k "
done

# Only proxies belonging to a copied video; others stay so the Insta360 app
# can still preview videos left on the camera.
lrv_paths=()
while IFS= read -r -d '' lf; do
    k=$(media_key "$lf")
    case "$copied_keys" in
        *" $k "*) [ -n "$k" ] && lrv_paths+=("$lf") ;;
    esac
done < <(find "${SRC_VOL}DCIM" -type f ! -name '._*' -iname "*.lrv" -print0)

total_delete=$((${#delete_paths[@]} + ${#lrv_paths[@]}))

if ask "Delete the ${#delete_paths[@]} imported file(s) and ${#lrv_paths[@]} matching .lrv proxy file(s) from the camera?" n; then
    echo
    echo "${RED}${BOLD}WARNING:${RESET} this will permanently delete up to $total_delete file(s) from your Insta360 GO 3S."
    echo "Files whose local copy fails verification (missing or size mismatch) are kept."
    echo "This cannot be undone. Files were copied to: $DEST_ROOT"
    read -r -p "Type DELETE to confirm: " confirm
    if [ "$confirm" = "DELETE" ]; then
        deleted=0
        kept=0
        deleted_keys=" "
        for i in "${!delete_paths[@]}"; do
            f="${delete_paths[$i]}"
            d="${delete_dests[$i]}"
            # Only delete from camera if the local copy exists with matching size.
            if [ -f "$d" ] && [ "$(stat -f%z "$d")" = "$(stat -f%z "$f")" ]; then
                k=$(media_key "$f")
                rm -f "$f"
                deleted=$((deleted + 1))
                [ -n "$k" ] && deleted_keys+="$k "
            else
                kept=$((kept + 1))
                echo "${RED}Not deleted:${RESET} $(basename "$f") (local copy missing or size mismatch: ${d#$HOME/})"
            fi
        done
        # Proxy goes only if its video was actually deleted.
        for f in ${lrv_paths[@]+"${lrv_paths[@]}"}; do
            case "$deleted_keys" in
                *" $(media_key "$f") "*)
                    rm -f "$f"
                    deleted=$((deleted + 1))
                    ;;
            esac
        done
        echo "${GREEN}Deleted $deleted file(s) from camera.${RESET}"
        if [ "$kept" -gt 0 ]; then
            echo "${YELLOW}Kept $kept file(s) on camera that failed verification.${RESET}"
        fi
    else
        echo "${YELLOW}Confirmation not given. Nothing deleted from camera.${RESET}"
    fi
else
    echo "Keeping files on camera."
fi

offer_eject
