# insta360-go3s-video-downloader

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
   size) are skipped.
4. Optionally delete the copied files (and `.lrv` proxy files) off the
   camera, with a typed `DELETE` confirmation.

Destination folders open in Finder automatically after copying.
