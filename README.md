# trackpad

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android app (remote trackpad/keyboard)

Prebuilt APK: `dist/android/trackpad.apk` (release build, signed with the Android **debug** key, which is fine for sideloading but not for the Play Store). Rebuild with `flutter build apk --release`.

### Install

- With adb (USB debugging on): `adb install -r dist/android/trackpad.apk`
- Or copy the APK to the phone, open it, and allow "Install unknown apps" for your file manager or browser.

### Pair with the Mac agent

1. Start the Mac agent by double-clicking `TrackpadAgent.app` (details in [agent/README.md](agent/README.md)). It prints a 6-digit Pairing Code in Terminal.
2. Grant the agent Accessibility access in System Settings > Privacy & Security > Accessibility.
3. On the phone, open Trackpad and allow the Nearby devices / Bluetooth permissions when asked.
4. Put the phone and Mac on the same Wi-Fi network (the Mac agent is Wi-Fi only), pick the Mac from the list or enter its IP manually, and enter the pairing code.
