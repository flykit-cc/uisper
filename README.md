# uisper

Native, fully local dictation for macOS. Hold a key, speak, let go. Clean text lands in whatever app you are typing in.

Nothing leaves your Mac. No accounts, no cloud, no telemetry.

<p align="center"><img src="docs/screenshots/pill.png" alt="Live transcription pill" width="600"></p>

## Install

You need a Mac with Apple silicon running macOS 26 or newer. Nothing else.

1. Download the latest `uisper-x.y.z.zip` from [Releases](https://github.com/flykit-cc/uisper/releases).
2. Unzip it and move `uisper.app` to your Applications folder.
3. Right-click `uisper.app` and choose **Open**, then **Open** again in the dialog. This is needed once, because the build is not notarized by Apple.
4. Grant the three permissions macOS asks for: Microphone, Accessibility, Input Monitoring. Then quit uisper from the menu bar and open it again.
5. For the grammar cleanup, turn on Apple Intelligence in System Settings › Apple Intelligence & Siri. Without it, uisper still works and inserts the raw transcript. macOS only shows the Apple Intelligence switch when the Mac language and the Siri language match.

uisper lives in the menu bar. Look for the microphone icon.

## Use

1. Hold your hotkey. A small pill appears at the bottom of the window you are in.
2. Speak. Words show up in the pill as you talk.
3. Let go. The text is cleaned up and inserted at the cursor.

Press Escape while dictating to cancel. A tap shorter than 300 ms does nothing.

The default hotkey is Option+Space. Change it in Settings › General: click the field and press any shortcut. Modifier-only chords like Fn or Right Option work too.

<p align="center"><img src="docs/screenshots/menu.png" alt="Menu bar menu" width="220"></p>
<p align="center">Everything lives in the menu bar: language, cleanup toggle, hold or toggle mode.</p>

<p align="center"><img src="docs/screenshots/settings.png" alt="Settings" width="560"></p>
<p align="center">Click the hotkey field and press any shortcut. That is your key from then on.</p>

## What the cleanup does

A small AI model that ships with macOS rewrites the raw transcript before it is inserted:

- Fixes punctuation, capitalization and grammar.
- Drops fillers like "uh" and "um" and false starts.
- Applies self-corrections: "send it Monday, no wait, Tuesday" becomes "send it Tuesday".
- Spells the words in your vocabulary list the way you told it to.

It runs on your Mac. Turn it off in the menu bar when you want the raw words.

## Features

- Hold-to-talk or press-to-toggle.
- Any hotkey, recorded by pressing it.
- English, German, Brazilian Portuguese. Switch from the menu bar.
- Personal vocabulary list.
- Password fields are respected: when secure input is on, the text goes to the clipboard instead.
- Works in every app, including Chrome and Electron apps, through a paste fallback.

## How it is built

Everything runs on device inside macOS 26:

| Part | What it uses |
|---|---|
| Speech to text | Apple `SpeechAnalyzer`, streaming |
| Cleanup | Apple Foundation Models, the model behind Apple Intelligence |
| Text insertion | Accessibility API, with a paste fallback |
| Hotkey | A global event tap, so hold-to-talk works everywhere |

The app is not sandboxed and is not on the App Store. Global hotkeys and text insertion need permissions the App Store forbids.

## Build from source

Only needed if you want to change the code. Requires Xcode 26 and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```
brew install xcodegen
scripts/build.sh --open
```

This generates the Xcode project, builds, signs with your local identity, and launches the app.

Tests:

```
cd UisperCore && swift test
```

All logic lives in the `UisperCore` package and is tested there. The `Uisper` app target is a thin shell.

To publish a release: `scripts/release.sh 0.2.0`.

## Known limits

- On Apple keyboards, F14 and F15 double as brightness keys at a level no app can intercept. Remap them with [Karabiner-Elements](https://karabiner-elements.pqrs.org), for example F15 to F20, and record the mapped key.
- Cleanup speed depends on how busy your Mac is. On a calm machine it takes well under a second.

## Roadmap

- WhisperKit as a second engine, with automatic language detection.
- Per-app context: tone and vocabulary hints from the app you are typing in.
- Voice commands while dictating, like "new line" and "delete that".

## License

MIT.
