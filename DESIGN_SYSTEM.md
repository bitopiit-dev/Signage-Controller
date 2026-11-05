# SignageController Design System

## Overview
A modern, production-ready design system for the SignageController app, leveraging Material 3 principles and glassmorphism for a high-tech, clean aesthetic.

## 1. Typography
- **Primary Font**: `Inter` (or `Segoe UI` as fallback)
- **Headings**: Semi-bold, tight letter spacing.
- **Body**: Regular, 14pt-16pt for readability.
- **Monospace**: `JetBrains Mono` for IP addresses and technical logs.

## 2. Color Palette
- **Primary**: `#4FC3F7` (Light Blue / Cyan)
- **Surface**: `#0D1B4B` (Deep Navy) - Main background.
- **Glass**: `RGBA(255, 255, 255, 0.08)` with BackdropFilter (blur: 20px).
- **Success**: `#4CAF50` (Green) - Active/Live status.
- **Warning**: `#FFC107` (Amber) - Syncing/Connecting.
- **Danger**: `#F44336` (Red) - Error/Stopped.

## 3. Spacing & Grid
- **Base Grid**: 8dp.
- **Padding**: 16dp (standard), 24dp (relaxed).
- **Radius**: 16dp for cards, 32dp for buttons.

## 4. Components

### AppHeader
- **Style**: Glass-morphic blur background.
- **Content**: Large digital clock, server health indicator, and a prominent IP Address card.
- **Visuals**: Soft glowing border for the active server state.

### GlobalCommandBar
- **Style**: Floating bottom bar or docked under the header.
- **Buttons**: Large icon buttons with haptic feedback.
- **Feedback**: Dynamic labels (e.g., "LIVE" vs "PAUSED").

### LibraryPanel
- **Structure**: Sidebar or Tabbed view.
- **Grouping**: Badge indicators for file types (Video, Image, etc.).
- **Interactions**: Drag-and-drop reordering, multi-select checkboxes.

### PreviewPlayer
- **Style**: Centered focus area with aspect-ratio management.
- **Placeholder**: `VintageCDPlayer` animation when idle.
- **Overlay**: Subtle playback info (filename, elapsed time).

### TVStatusSidebar
- **Style**: Grid or List of "Device Cards".
- **Details**: IP, status icon, volume slider, and "Reboot" quick action.
- **Grouping**: Group by online/offline status.

## 5. Effects
- **Glassmorphism**: 
  - `color: Colors.white.withOpacity(0.05)`
  - `BackdropFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10)`
  - `Border: Border.all(color: Colors.white.withOpacity(0.1))`
- **Transitions**: 300ms `Curves.easeInOutCubic` for all state changes.
