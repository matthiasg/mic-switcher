# MicSwitcher

A simple macOS menu bar app for quickly switching between audio input devices.

## Why?

I needed this. I switch microphones all the time - between my AirPods, webcam, external mics, etc. macOS makes you dig through System Settings every time. That's annoying.

So I made this little menu bar app that lets you switch with two clicks. Problem solved.

## Features

- Lives in your menu bar
- Shows all your microphones  
- Switch with one click
- Set priority order - higher priority mics auto-switch when connected
- Remembers all devices you've ever used
- No dock icon, no window clutter

## Installation

### App Store

Coming soon for ~ €1 (or whatever the minimum is in your region).

### Build from Source

```bash
git clone https://github.com/matthiasg/mic-switcher.git
cd mic-switcher
open MicSwitcher.xcodeproj
# Build and run in Xcode
```

### Requirements

- macOS 15.5 or later
- Xcode 14.0 or later (for building)

## Usage

1. Click the mic icon in your menu bar
2. Pick a microphone
3. That's it

Want to set priorities? Click Settings and drag devices to reorder them. Top = highest priority.

## Contributing

Got ideas to make this better while keeping it simple? Found a bug? Pull requests are welcome!

Issues without pull requests - I might read them, might not, depends on time. But PRs I'll definitely look at.

## Built With

Written with the help of Grok 4 and Claude. Because why not let AI help with the boring parts?

## License

MIT License - see LICENSE file.

## Disclaimer

This software is provided "as is", without warranty of any kind. I assume no liability for any damages arising from its use. Use at your own risk.

## Author

Matthias Götzke - Just someone who switches microphones too often. You can also find me at x.com/mgoetzke
