# Privacy Policy for MicSwitcher

*Last updated: July 22, 2025*

## Overview

MicSwitcher is committed to protecting your privacy. This privacy policy explains what information the app collects, how its used, and your rights regarding your data.


## Information We Collect

### Anonymous Telemetry Data (Optional)

When telemetry is enabled, MicSwitcher sends anonymous usage metrics to help improve the application. This feature is **disabled by default** and requires explicit opt-in. By default it targets a local opentelemetry-collector such as https://github.com/open-telemetry/opentelemetry-collector which most people would not even have running, but you can specify any you like. I do not collect any data at all.

Honestly it is only included because my enterprise apps always have it and every app should have it. Maybe it will inspire people to add it to their apps. 

**What the app sends to the opentelemetry server:**

- Application events (launches, settings opened)
- Microphone switching statistics (manual/automatic switches)
- Device count metrics (number of connected microphones)
- Anonymous device identifier (hashed, non-reversible)

**What is NOT collected:**

The app does not "collect" any information as its entirely up to the user to say where to send the data to and it defaults to localhost. But inside the metrics the app also do not collect:

- Personal information
- Microphone names or models
- Audio data or recordings
- Location information
- Network information
- User identifiable information

### Technical Implementation

- All telemetry data is sent to a user provided self-hosted OpenTelemetry collector
- No third-party analytics services are used
- Device IDs are one-way hashed and cannot be reversed

## How Can The Information Used

Collected metrics can be used by the provider of the opentelemetry target to:

- Understand feature usage patterns
- Identify and fix bugs
- Improve application performance
- Guide future development

## Data Storage and Retention

- Telemetry data is stored on user provided self-hosted infrastructure
- No data is shared with third parties as I do not collect it
- No data is sold or used for advertising as I do not collect it

## Your Rights and Controls

You have complete control over your data:

1. **Opt-in Only**: Telemetry is disabled by default
2. **Enable/Disable**: Toggle telemetry at any time in Advanced Settings
3. **Selective Tracking**: Choose which metrics to share
4. **Local Processing**: All microphone operations happen locally on your device
5. **User Provided**: The telemetry is stored on the user provided target only

## Local Data Storage

MicSwitcher stores the following data locally on your device:

- Microphone priority preferences
- Application settings
- Device history (for auto-switching)

This data never leaves your device.

## Children's Privacy

MicSwitcher does not knowingly collect information from children under 13 years of age.

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be posted to this page with an updated revision date.

## Contact

For questions about this privacy policy or MicSwitcher's privacy practices, please create an issue on our [GitHub repository](https://github.com/matthiasg/MicSwitcher).

## Compliance

MicSwitcher is designed to comply with:

- Apple's App Store Review Guidelines
- General Data Protection Regulation (GDPR)
- California Consumer Privacy Act (CCPA)

---

© 2025 Matthias Götzke. All rights reserved.
