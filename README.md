# insta360 go3s video downloader

Import photos/videos from an Insta360 GO 3S (USB mass storage) into a local
folder on macOS, organized by date.

## Usage

```sh
./import_insta360.sh [options]
```

| Option | Effect |
| --- | --- |
| `-n`, `--dry-run` | Show what would be copied; change nothing. |
| `-y`, `--yes` | No prompts; take each prompt's default (copy, don't re-copy, **don't delete**, eject). |
| `-d`, `--dest DIR` | Import into `DIR` instead of `~/Movies/Insta360`. |
| `--no-delete` | Never offer to delete files from the camera. |
| `--install-autorun` | Open the importer in Terminal whenever the camera is plugged in. |
| `--uninstall-autorun` | Remove the auto-run agent. |

1. Plug in the Insta360 GO 3S via USB so it mounts under `/Volumes`.
2. Run the script. It scans the camera's `DCIM` folder for media files
   (`.mp4`, `.mov`, `.jpg`, `.jpeg`, `.dng`, `.insv`, `.insp`) and lists which
   are new and which were already imported.
3. Confirm to copy the new files into `~/Movies/Insta360/YYYY-MM-DD/`, grouped
   by capture date taken from the file name (e.g. `VID_20250903_…` →
   `2025-09-03`), or by modification date for names without one. Files
   already present locally (same name + size) are skipped, including copies
   filed by modification date by earlier versions of the script. A file with
   the same name but a different size is saved under a new name
   (`NAME_HHMMSS.ext`, then `NAME_HHMMSS_2.ext`, …) instead of overwriting.
   The script checks for enough free space before copying anything.
4. If any files were skipped, optionally re-copy them anyway, overwriting the
   local copies.
5. Optionally delete the imported files off the camera, with a typed `DELETE`
   confirmation. This includes files skipped as already imported, so a later
   run can clear files kept on the camera earlier. A file is only deleted if its local copy exists with the
   same size; any that fail this check stay on the camera and are reported.
   A video's `.lrv` proxy is deleted only together with that video (matched
   by name, e.g. `VID_20250903_142501_00_012.mp4` ↔
   `LRV_20250903_142501_01_012.lrv`), so videos left on the camera keep their
   previews in the Insta360 app.
6. Optionally eject the camera so it's safe to unplug.

Destination folders open in Finder automatically after copying.

## Auto-run on plug-in

`./import_insta360.sh --install-autorun` installs a launchd agent
(`~/Library/LaunchAgents/local.insta360-import.plist`) that runs on every
volume mount and opens the importer in Terminal if a camera is attached and
no import is already running. It points at the script's current location, so
re-run the install after moving the repo. Mounting another disk while the
camera is still plugged in opens the importer again. macOS may ask to allow
access to removable volumes the first time.

## Requirements

macOS only (uses BSD `stat`/`date`, `open`, and `/Volumes`). Runs on the
stock `/bin/bash` 3.2; no extra installs needed — `rsync` ships with macOS.
