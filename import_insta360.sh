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

offer_eject() {
    read -r -p "Eject the camera now? [Y/n] " eject_ans
    if [[ "$eject_ans" =~ ^[Nn]$ ]]; then
        return 0
    fi
    if diskutil eject "$SRC_VOL" >/dev/null; then
        echo "${GREEN}Camera ejected. Safe to unplug.${RESET}"
    else
        echo "${YELLOW}Could not eject camera (in use?). Eject it from Finder before unplugging.${RESET}"
    fi
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
copied_dests=()   # parallel to copied_paths: where each file was copied to
skipped_paths=()
skipped_dests=()  # parallel to skipped_paths: existing local copy
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
            skipped_dests+=("$dest")
            echo "${YELLOW}Skipped:${RESET} $fname (already imported)"
            continue
        fi
        # Same name, different size — make unique instead of overwriting.
        dest="$day_dir/${fname%.*}_$(date -r "$(stat -f%m "$f")" +%H%M%S).${fname##*.}"
    fi

    copy_file "$f" "$dest"
    copied_paths+=("$f")
    copied_dests+=("$dest")
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
            copied_dests+=("$dest")
            case " ${dest_dirs[*]-} " in
                *" $day_dir "*) ;;
                *) dest_dirs+=("$day_dir") ;;
            esac
            copied=$((copied + 1))
            echo "${GREEN}Copied:${RESET} $fname -> ${dest#$HOME/}"
        done
        # Now tracked as copied; don't count them twice below.
        skipped_paths=()
        skipped_dests=()
    fi
fi

# Delete candidates: files copied this run plus files already imported
# earlier (so a later run can still clear them off the camera).
# ${arr[@]+...} guard: bash 3.2 (macOS /bin/bash) + set -u errors on empty arrays.
delete_paths=(${copied_paths[@]+"${copied_paths[@]}"} ${skipped_paths[@]+"${skipped_paths[@]}"})
delete_dests=(${copied_dests[@]+"${copied_dests[@]}"} ${skipped_dests[@]+"${skipped_dests[@]}"})

for d in ${dest_dirs[@]+"${dest_dirs[@]}"}; do
    open "$d"
done

if [ "${#delete_paths[@]}" -eq 0 ]; then
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
done < <(find "${SRC_VOL}DCIM" -type f -iname "*.lrv" -print0)

total_delete=$((${#delete_paths[@]} + ${#lrv_paths[@]}))

read -r -p "Delete the ${#delete_paths[@]} imported file(s) and ${#lrv_paths[@]} matching .lrv proxy file(s) from the camera? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
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
