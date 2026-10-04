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
5. Optionally delete the copied files (and `.lrv` proxy files) off the
   camera, with a typed `DELETE` confirmation. A file is only deleted if its
   local copy exists with the same size; any that fail this check stay on the
   camera and are reported.

Destination folders open in Finder automatically after copying.

## Requirements

macOS only (uses BSD `stat`/`date`, `open`, and `/Volumes`). Runs on the
stock `/bin/bash` 3.2; no extra installs needed — `rsync` ships with macOS.
