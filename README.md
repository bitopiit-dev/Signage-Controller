# BGL IT Signage Controller 🚀📺

**BGL IT Signage Controller** is an enterprise-grade, high-performance master control center for digital signage networks. Running on a Windows PC or mobile device, it drives, synchronizes, and manages every signage TV screen across the local area network in real time.

[![Latest Release](https://img.shields.io/github/v/release/bitopiit-dev/Signage-Controller?color=00e5ff&style=flat-square)](https://github.com/bitopiit-dev/Signage-Controller/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android%20%7C%20iOS%20%7C%20Web-00e5ff.svg?style=flat-square)](https://github.com/bitopiit-dev/Signage-Controller)

---

## ✨ Key Features & Benefits

### ⏱️ 1. Ultra-Low Latency Multi-Screen Frame Sync
- **Sub-Second Micro-Drift Threshold (400ms):** Automatically detects and corrects playback drift as soon as a TV screen deviates by more than 0.4 seconds.
- **High-Frequency 300ms Polling:** Keeps connected TV clients responsive to master position updates in real time.
- **Network RTT Compensation (+25ms):** Calculates network travel time between the Controller and TV screens to guarantee frame-exact playback harmony.
- **Smooth Playback Speed Nudging (±5%):** Adjusts playback speed by ±5% for minor drifts (400ms - 1200ms), eliminating audio pops and video stutters.

### 🖥️ 2. Live Desktop & Application Window Screen Share
- **Full Desktop or Specific Window Selection:** Share your entire PC screen or a specific application window (e.g., **Google Chrome, PowerPoint, Excel, PDF Reader, WhatsApp**) live to all connected TVs.
- **Win32 Background Window Rendering:** Automatically restores target windows in the background (`SW_SHOWNOACTIVATE`) so Windows OS continues painting GDI graphics even when you minimize or switch windows.
- **Non-Recursive Control Dashboard:** Replaces infinite video feedback loops with a sleek, non-recursive Screen Share Dashboard in the Controller UI.

### 🎛️ 3. Independent Per-Device Controls (Command Wall)
- **Custom Media Assignment (`ASSIGN / CUSTOM`):** Assign specific videos or images to run independently on individual TV screens (e.g., Lobby TV vs Director Room TV) while others continue the main loop.
- **Independent Pause & Resume:** Pause or resume playback on a single TV screen without affecting other screens.
- **Individual Screen Volume & Mute:** Adjust volume levels or mute specific TV screens independently.
- **Hardware Commands:** Send instant **RESTART** (reboots TV player), **CAPTURE** (pulls live TV screenshot), and **IDENTIFY** (flashes screen ID banner) to any screen.

### 🚀 4. Hardware-Accelerated GPU Video Transcoding
- **Automatic GPU Acceleration:** Harnesses **AMD Radeon AMF**, **NVIDIA NVENC**, and **Intel QuickSync (QSV)** hardware encoders to transcode 1080p videos at 200–400 FPS (a 5-minute video converts in **2–4 seconds**).
- **2x Parallel Concurrent Workers:** Transcodes multiple imported videos simultaneously in parallel.
- **Ultrafast Multi-Core CPU Fallback (`libx264`):** Automatically falls back to software encoding if a specific video stream (e.g., VP9, AV1, 10-bit color) is rejected by GPU drivers, guaranteeing 100% video conversion success.

### 📱 5. Adaptive Mobile & Desktop Responsive UI
- **Responsive Desktop 3-Pane Layout:** Enterprise Library (Left) | Central Monitor (Middle) | Command Wall (Right).
- **Dedicated Mobile Phone Interface:** Automatically transforms into a mobile-friendly view on Android/iOS phones with a **Bottom Navigation Bar** (`[ 🎵 Library | 🖥️ Monitor | 📡 Screens ]`).
- **Overflow-Free Horizontal Scrolling:** Wraps panels in responsive containers to eliminate UI overflow errors on small screens and narrow windows.

### 🚨 6. Emergency Broadcast System
- **Instant Evacuation & Alert Overlay:** Broadcast text messages or full-screen emergency posters/images to all connected screens with a single click.
- **Live Countdown Timer:** Configurable timer (30s to 30m, or Manual) with live badge updates and auto-end triggers.

---

## 🛠️ System Requirements

- **Operating System:** Windows 10 or 11 (Main Controller Target; Android, iOS, macOS supported)
- **SDK:** Flutter SDK with Dart 3.x and Visual Studio C++ Toolchain
- **FFmpeg & FFprobe:** Included or installed in `PATH` / application directory for GPU transcoding and screen capture.
- **Network:** Local Area Network (Wi-Fi / Ethernet) with UDP port `45454` and HTTP port `8888` enabled.

---

## 🚀 Quick Start & Installation

### Option A: Download Pre-built Release (Windows)
1. Download the latest release package `Signage-Controller-v1.1.0-Windows.zip` from [GitHub Releases](https://github.com/bitopiit-dev/Signage-Controller/releases/latest).
2. Extract the ZIP file and run `signagecontroller.exe`.

### Option B: Build from Source
```powershell
# Clone repository
git clone https://github.com/bitopiit-dev/Signage-Controller.git
cd Signage-Controller

# Get dependencies
flutter pub get

# Run on Windows Desktop
flutter run -d windows

# Build Release Executable
flutter build windows --release
```

---

## 📂 Project Architecture

```
lib/
├── main.dart                  # Entry point, HTTP server, UDP discovery, Master state engine
├── components/
│   ├── app_header.dart        # Header status cards, clock, IP badge, screen share controls
│   ├── command_center_dock.dart # Master play/pause/stop/seek dock
│   ├── enterprise_library.dart  # Media library, drag-and-drop import, jobs panel
│   ├── broadcast_monitor.dart   # Live screen share & playback preview monitor
│   └── device_command_wall.dart # Individual TV screen control cards & activity feed
├── models/                    # PlaylistItem, DeviceStatus, ActivityEntry
├── core/                      # Design system, theme colors, spacing
└── utils/
    ├── transcoder.dart        # FFmpeg GPU acceleration detection & parallel transcode queue
    └── media_utils.dart       # File format detection & YouTube link parsing
```

---

## 👤 Developed By

**K A Rahman / BGL IT Signage**  
🌐 Portfolio: [https://bitopiit-dev.github.io/#top](https://bitopiit-dev.github.io/#top)  
📦 GitHub Repository: [https://github.com/bitopiit-dev/Signage-Controller](https://github.com/bitopiit-dev/Signage-Controller)
