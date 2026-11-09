# BGLIT Signage Controller

BGLIT Signage Controller runs on one Windows PC and drives every signage TV on the local network. It holds the playlist, keeps the master clock, and serves media to the player app on each TV. Players find the controller on their own, follow its playback position, and keep looping the last playlist if the controller goes offline.

The player app that runs on the TVs is a separate project. This repo is the controller only.

## What it does

- **Playlist and library.** Add videos, images, audio, PDFs and YouTube links by file picker or drag-and-drop, then reorder, shuffle, repeat one item, pause, stop or seek. The library and playlist are saved to `playlist.json` in the media folder.
- **Synchronized playback.** Every player reads the same current file and position from the controller and corrects drift (2 s for video and audio, 3.5 s for YouTube, 1.5 s for images and PDFs). See [SYNC_PROTOCOL.md](SYNC_PROTOCOL.md).
- **Device wall.** Each TV reports a heartbeat every 2 seconds. From the controller you can set volume or mute per TV, reboot it, clear its cache, flash an identify banner, or pull a screenshot.
- **Emergency message.** One switch overlays a message on every screen.
- **Screen sharing.** Broadcasts the whole desktop or one window to the TVs as a 10 fps JPEG stream (Windows only, needs ffmpeg).
- **Video conversion.** Videos that are not H.264 / yuv420p / AAC stereo in an MP4 container, or that are larger than 1920×1080, are re-encoded so every TV can play them. The controller uses NVIDIA NVENC, Intel QSV or AMD AMF when the GPU supports it, and falls back to software encoding otherwise.

## Requirements

- Windows 10 or 11 (the main target; Android, macOS and Linux folders exist but screen sharing and window listing are Windows-only)
- Flutter SDK with Dart 3.x and the Windows desktop toolchain (Visual Studio with "Desktop development with C++")
- ffmpeg and ffprobe, optional but needed for video conversion and screen sharing
- Controller PC and TVs on the same LAN, with UDP 45454 and the HTTP port allowed through Windows Firewall

## Build and run

```powershell
git clone https://github.com/bitopiit-dev/Signage-Controller.git
cd Signage-Controller
flutter pub get
flutter run -d windows          # development
flutter build windows --release # output: build\windows\x64\runner\Release\
```

Copy the whole `Release` folder to the controller PC; `signagecontroller.exe` needs the DLLs and `data` folder next to it.

## Setting up ffmpeg

The controller looks for `ffmpeg.exe` and `ffprobe.exe` in this order and uses the first folder that has both:

1. The folder that contains `signagecontroller.exe`
2. `ffmpeg\` or `ffmpeg\bin\` next to the exe
3. `Documents\signage_controller\ffmpeg\` or its `bin\` subfolder
4. The system `PATH`

Without ffmpeg the app still runs. Videos are added as-is and screen sharing is disabled; the log panel shows "ffmpeg not found".

## Where data is stored

Media files and `playlist.json` live in `Documents\signage_controller\media\`. Back up this folder to move a controller to another PC.

## Network

On start the controller opens an HTTP server on the first free port from 8888, 9090, 5500, 7777 and 8080, and listens for player discovery broadcasts on UDP 45454. The header shows the IP and port that players connect to.

The endpoints have no authentication. Run the controller only on a trusted signage network.

## Project layout

```
lib/
  main.dart                 App entry, HTTP server, UDP discovery, playlist state, screen sharing
  components/
    app_header.dart         Clock, server status, IP/port card, emergency button
    command_center_dock.dart  Play / pause / stop / seek, reboot all TVs
    enterprise_library.dart   Media library, import, video conversion queue
    broadcast_monitor.dart    Preview of what the TVs are showing
    device_command_wall.dart  Per-TV status and commands
  models/                   PlaylistItem, DeviceStatus
  core/                     Theme, colors, spacing
  utils/
    transcoder.dart         ffmpeg discovery, codec checks, GPU encoder selection
    media_utils.dart        File-type detection, YouTube ID parsing
  widgets/                  Clock, live pulse, idle CD-player animation
test/widget_test.dart       Smoke test (app builds and renders)
```

`DESIGN_SYSTEM.md` describes the UI style. `SYNC_PROTOCOL.md` is the contract with the player app; update it whenever an endpoint or a field in `/playlist.json` changes.

## Tests

```powershell
flutter test
```

Only a smoke test exists today.
