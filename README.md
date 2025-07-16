# MicSwitcher

A simple macOS menu bar application that makes switching between microphones effortless. Built because the native macOS microphone switching experience is cumbersome.

## Features

- **Menu Bar Integration**: Lives in your menu bar for quick access
- **Real-time Monitoring**: Automatically detects when microphones are added or removed
- **Smart Notifications**: Get notified when your microphone changes or new devices are detected
- **Visual Feedback**: Clear checkmark indicator for the currently selected microphone

## Installation

### Building from Source

1. Clone this repository
2. Open `MicSwitcher.xcodeproj` in Xcode
3. Build and run the project (⌘+R)

### Requirements

- macOS 12.0 or later
- Xcode 14.0 or later (for building)

## Usage

1. Launch the app - it will appear in your menu bar as a microphone icon
2. Click the microphone icon to see all available input devices
3. Select any microphone from the dropdown to switch to it
4. The app will show a checkmark next to your currently active microphone
5. Receive notifications when microphones are switched or devices are added/removed

## How It Works

The app uses CoreAudio APIs to:

- Monitor the system's default input device
- Listen for audio device changes in real-time
- Programmatically switch between available microphones
- Provide system notifications and audio feedback

## Development

This project was entirely written by Grok 4 AI assistant, the README by Claude 4 sonnet. I just read over it and prompted it.

### Key Components

- **AppState**: Manages the current microphone state and handles notifications
- **AudioMonitor**: Listens for system audio device changes
- **MicMenuContent**: Provides the menu bar interface
- **CoreAudio Integration**: Direct system-level microphone control

## License

See the LICENSE file for details.

## Contributing

Feel free to submit issues and enhancement requests!
