# uisper

Native, fully local dictation for macOS 26. Hold ⌥Space, speak, release. Text appears in whatever app has focus.

- Speech: Apple SpeechAnalyzer (on device)
- Cleanup: Apple Foundation Models (on device)
- No network, no accounts, no telemetry

## Build

    brew install xcodegen
    scripts/build.sh --open

Needs Xcode 26.6+, Apple Silicon. Grant Microphone, Accessibility and Input Monitoring when asked.
