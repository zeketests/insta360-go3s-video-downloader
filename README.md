# insta360 go3s video downloader

Import photos/videos from an Insta360 GO 3S (USB mass storage) into a local
folder on macOS, organized by date.

## Usage

```sh
./import_insta360.sh
```

1. Plug in the Insta360 GO 3S via USB so it mounts under `/Volumes`.
2. Run the script. It scans the camera's `DCIM` folder and lists every media
   file found (`.mp4`, `.mov`, `.jpg`, `.jpeg`, `.dng`, `.insv`, `.insp`).
3. Confirm to copy the files into `~/Movies/Insta360/YYYY-MM-DD/`, grouped by
   the file's modification date. Files already present locally (same name +
   size) are skipped. A file with the same name but a different size is
   saved under a new name (`NAME_HHMMSS.ext`) instead of overwriting.
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

## Requirements

macOS only (uses BSD `stat`/`date`, `open`, and `/Volumes`). Runs on the
stock `/bin/bash` 3.2; no extra installs needed — `rsync` ships with macOS.
