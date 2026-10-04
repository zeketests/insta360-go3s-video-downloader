#!/usr/bin/env bash
#
# Import photos/videos from Insta360 GO 3S (USB mass storage) into a local
# folder, organized by date. Skips files already imported. Optionally offers
# to delete files off the camera after copy, with a confirmation prompt.

set -euo pipefail

# Colors
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

pause_on_exit() {
    echo
    read -r -p "Press Enter to close..." _ || true
}
trap pause_on_exit EXIT

DEST_ROOT="$HOME/Movies/Insta360"
EXTS=(mp4 MP4 mov MOV jpg JPG jpeg JPEG dng DNG insv INSV insp INSP)

find_camera_volume() {
    for vol in /Volumes/*/; do
        [ -d "${vol}DCIM" ] && [ "$vol" != "/Volumes/Macintosh HD/" ] && echo "$vol" && return 0
    done
    return 1
}

# Copy one file to dest with a progress bar (rsync ships with macOS).
# Extra args are passed through to rsync.
copy_file() {
    local src="$1" dest="$2"
    shift 2
    rsync -a --progress "$@" "$src" "$dest"
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
done < <(find "${SRC_VOL}DCIM" -type f \( "${find_args[@]}" \) -print0)

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "No media files found on camera."
    exit 0
fi

echo "${BOLD}Found ${#candidates[@]} file(s) on camera:${RESET}"
for f in "${candidates[@]}"; do
    echo "  $(basename "$f")"
done

read -r -p "Copy these files to ${DEST_ROOT}? [Y/n] " import_ans
if [[ "$import_ans" =~ ^[Nn]$ ]]; then
    echo "Cancelled. Nothing copied."
    exit 0
fi

mkdir -p "$DEST_ROOT"

copied=0
skipped=0
copied_paths=()
skipped_paths=()
dest_dirs=()

for f in "${candidates[@]}"; do
    size=$(stat -f%z "$f")
    fname=$(basename "$f")

    mdate=$(date -r "$(stat -f%m "$f")" +%Y-%m-%d)
    day_dir="$DEST_ROOT/$mdate"
    mkdir -p "$day_dir"

    dest="$day_dir/$fname"
    if [ -e "$dest" ]; then
        dest_size=$(stat -f%z "$dest")
        if [ "$dest_size" = "$size" ]; then
            # Already present locally (same name + size) — skip.
            skipped=$((skipped + 1))
            skipped_paths+=("$f")
            echo "${YELLOW}Skipped:${RESET} $fname (already imported)"
            continue
        fi
        # Same name, different size — make unique instead of overwriting.
        dest="$day_dir/${fname%.*}_$(date -r "$(stat -f%m "$f")" +%H%M%S).${fname##*.}"
    fi

    copy_file "$f" "$dest"
    copied_paths+=("$f")
    case " ${dest_dirs[*]-} " in
        *" $day_dir "*) ;;
        *) dest_dirs+=("$day_dir") ;;
    esac
    copied=$((copied + 1))
    echo "${GREEN}Copied:${RESET} $fname -> ${dest#$HOME/}"
done

echo
echo "${BOLD}Done.${RESET} Copied: ${GREEN}$copied${RESET}, skipped (already imported): ${YELLOW}$skipped${RESET}."

if [ "$skipped" -gt 0 ]; then
    read -r -p "Re-copy the $skipped already-imported file(s) anyway (overwrite)? [y/N] " recopy_ans
    if [[ "$recopy_ans" =~ ^[Yy]$ ]]; then
        for f in "${skipped_paths[@]}"; do
            fname=$(basename "$f")
            mdate=$(date -r "$(stat -f%m "$f")" +%Y-%m-%d)
            day_dir="$DEST_ROOT/$mdate"
            dest="$day_dir/$fname"
            # --ignore-times: rsync -a preserved mtime, so quick-check would skip it.
            copy_file "$f" "$dest" --ignore-times
            copied_paths+=("$f")
            case " ${dest_dirs[*]-} " in
                *" $day_dir "*) ;;
                *) dest_dirs+=("$day_dir") ;;
            esac
            copied=$((copied + 1))
            echo "${GREEN}Copied:${RESET} $fname -> ${dest#$HOME/}"
        done
    fi
fi

if [ "$copied" -eq 0 ]; then
    exit 0
fi

for d in "${dest_dirs[@]}"; do
    open "$d"
done

lrv_paths=()
while IFS= read -r -d '' lf; do
    lrv_paths+=("$lf")
done < <(find "${SRC_VOL}DCIM" -type f -iname "*.lrv" -print0)

total_delete=$((copied + ${#lrv_paths[@]}))

read -r -p "Delete the $copied copied file(s) and ${#lrv_paths[@]} .lrv proxy file(s) from the camera? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo
    echo "${RED}${BOLD}WARNING:${RESET} this will permanently delete $total_delete file(s) from your Insta360 GO 3S."
    echo "This cannot be undone. Files were copied to: $DEST_ROOT"
    read -r -p "Type DELETE to confirm: " confirm
    if [ "$confirm" = "DELETE" ]; then
        for f in "${copied_paths[@]}"; do
            rm -f "$f"
        done
        # ${arr[@]+...} guard: bash 3.2 (macOS /bin/bash) + set -u errors on empty arrays.
        for f in ${lrv_paths[@]+"${lrv_paths[@]}"}; do
            rm -f "$f"
        done
        echo "${GREEN}Deleted $total_delete file(s) from camera.${RESET}"
    else
        echo "${YELLOW}Confirmation not given. Nothing deleted from camera.${RESET}"
    fi
else
    echo "Keeping files on camera."
fi
