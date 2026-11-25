# Trackpad

Use an Android phone as a wireless trackpad and keyboard for a Mac or Windows computer.

The project has two parts:

- **Android app** (Flutter): the touch surface and keyboard on the phone.
- **Desktop agent** (.NET 7): a small console program on the computer that receives input events and injects them as mouse and keyboard input.

## How it works

1. The agent starts on the computer, advertises itself on the local network with mDNS, and prints a 6-digit pairing code in its console.
2. The phone lists agents it finds on the same Wi-Fi network (or you can enter the computer's IP address manually) and asks for the pairing code.
3. After pairing, phone and agent talk over an encrypted channel. The phone remembers the paired computer.
4. Touch gestures and key presses on the phone are sent to the agent, which performs them on the computer.

## Features

- Pointer movement with adjustable sensitivity
- Tap to click, right-click, double-click, and drag
- Two-finger scroll (natural scrolling can be switched on or off)
- Three-finger swipe and an on-screen app-switch button
- Keyboard panel with modifier keys (Alt and others) and an F1 to F12 row
- Settings screen: sensitivity, natural scrolling, tap-to-click

## Download

Get the files from the [latest release](https://github.com/Vyshnav161/trackpad/releases/latest).

| Platform | File |
| --- | --- |
| Android phone | `trackpad-android.apk` |
| macOS, Apple Silicon | `trackpad-agent-macos-arm64.zip` |
| macOS, Intel | `trackpad-agent-macos-x64.zip` |
| Windows 64-bit | `trackpad-agent-windows-x64.zip` |

The agent builds are self-contained, so no .NET install is needed.

## Install and pair

### 1. Android app

1. Download `trackpad-android.apk` to the phone.
2. Open it and allow "Install unknown apps" for your browser or file manager when asked. The APK is signed with the Android debug key, so it is for sideloading only, not the Play Store.
3. Or, with USB debugging on: `adb install -r trackpad-android.apk`.
4. Allow the Nearby devices / Bluetooth permissions when the app asks.

### 2. Mac agent

1. Unzip the file that matches your Mac and open `TrackpadAgent.app`. It opens Terminal and runs the agent there, where the pairing code is printed.
2. The app is ad-hoc signed, not notarized. If macOS blocks it, right-click the app and choose Open, or run `xattr -dr com.apple.quarantine TrackpadAgent.app`.
3. Grant Accessibility access in System Settings > Privacy & Security > Accessibility (enable Terminal, which hosts the agent), then restart the agent.
4. If macOS asks about incoming network connections, choose Allow.

More detail is in [agent/README.md](agent/README.md).

### 3. Windows agent

1. Unzip `trackpad-agent-windows-x64.zip` and run `Agent.Windows.exe`. A console window opens and shows the pairing code.
2. Allow it through Windows Firewall on private networks if prompted.

### 4. Pair

Put the phone and computer on the same Wi-Fi network, open Trackpad on the phone, pick the computer from the list (or enter its IP), and enter the 6-digit code shown in the agent's console.

## Known limitations

- **Wi-Fi only.** Bluetooth on the computer side is not implemented, so the agent logs that Bluetooth is disabled. Phone and computer must share a network.
- **The Windows agent is untested.** It is cross-compiled from macOS and has never been run on a Windows machine. Expect rough edges.
- The pairing code appears in the agent's console, not in a tray icon or window.
- The Mac agent needs Accessibility permission and is only ad-hoc signed (see the Gatekeeper steps above). Rebuilding changes its code hash, so permission may need to be granted again.
- The APK is debug-signed and needs "Install unknown apps".
- No automatic updates.

## Build from source

Requirements: Flutter SDK for the app, .NET 7 SDK for the agents.

```sh
# Android APK -> build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release

# Mac agent (arm64, x64, or all) -> dist/<arch>/TrackpadAgent.app
scripts/build-mac-agent.sh all

# Windows agent (cross-publish works from macOS) -> dist/release/trackpad-agent-windows-x64.zip
scripts/build-windows-agent.sh
# or directly:
cd agent && dotnet publish Agent.Windows -c Release -r win-x64 --self-contained -o ../dist/windows-agent
```

Tests: `flutter test` for the app and `dotnet test agent/Agent.sln` for the agent.

## Project layout

```
lib/                 Flutter app (gestures, keyboard, protocol, transport, storage, ui)
android/             Android project
test/                Flutter tests
agent/Agent.Core/    Shared agent code: protocol, pairing, secure channel, Wi-Fi/mDNS, dispatch
agent/Agent.Mac/     macOS input injection
agent/Agent.Windows/ Windows input injection
agent/Agent.Tests/   Agent tests
scripts/             Build scripts for the agents
```

## License

No license has been chosen yet. Until one is added, all rights are reserved by the author.
