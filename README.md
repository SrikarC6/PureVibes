# MusicApp

A minimal, high-fidelity music player for macOS — built entirely in Swift and SwiftUI.

## Features

- **Album Carousel** — browse albums with smooth 3D-tilt interactions and animated covers (Can change to grid if carousel not preferred)
- **Waveform Scrubber** — visual waveform display with drag-to-seek
- **Queue Management** — drag-to-reorder, play next, and loop modes
- **Media Keys** — play/pause, next/prev via keyboard and system controls
- **AI Album Art Animations** — Google Gemini-powered Ken Burns, parallax, ambient glow, and zoom in/out effects (Bring Your Own API Key)(FULLY OPTIONAL - NOT REQUIRED FOR APP TO WORK!)
- **Rich Metadata** — full MP4 and ID3 tag detection support, including specific Apple Music/iTunes tags (Apple Digital Master and <ITUNESADVISORY> tags are supported for .m4a files)
- **Full-Screen Support** — dynamic layout adapts to any window size

## Requirements

- macOS 26.2+
- Xcode 15+

## Downloading

1. Download .dmg file under the 'Releases' section
2. Mount the .dmg file and copy it to your 'Applications' folder
3. Delete the .dmg file and unmount the installer
4. Enjoy! 

## Usage

1. Click the **folder icon** in the mini player to select a directory of music files
2. Supported formats: AAC, ALAC, MP3, FLAC, WAV
3. Use built-in fast-forward and rewind keys for previous/next track and play/pause

## Disclaimers
- This app is currently in beta, so some functionalities (library/metadata caching, app menu information, app icon being the biggest ones) aren't implemented
- The AI functionality isn't required to use the app, and I am working on a local implementation using Apple's MLX protocol. I don't get any user information or data, the AI all runs with Gemini and they handle all the data
- This app was made entirely with Gemini-CLI and Google Antigravity, with some assistance with Claude Code
- You may need to go into Privacy/Security settings and allow the app to open, as macOS may claim the application is unsafe and not let you open it

## License

MIT
