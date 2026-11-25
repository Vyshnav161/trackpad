# Implementation Plan: Android Remote Input

## Overview

The plan builds the shared wire protocol first, then the pure-logic layers of the Android_App (settings, paired hosts, gesture and keyboard recognizers), then its transport and UI, and finally the Desktop_Agent. The Android_App is Flutter/Dart (property tests with `glados`). The Desktop_Agent is a .NET (C#) solution with a platform-agnostic core and per-OS injectors (Windows `SendInput`, macOS `CGEventPost`), with property tests in FsCheck. Each step wires into the previous ones, so no code is left orphaned.

## Tasks

- [x] 1. Set up project structure and tooling
  - Create the Flutter app skeleton (Android target) with folders `lib/protocol`, `lib/gestures`, `lib/keyboard`, `lib/transport`, `lib/storage`, `lib/ui`, and `test/`
  - Add dependencies: `glados`, `shared_preferences`, `flutter_secure_storage`, a Bluetooth Classic package (`flutter_blue_classic`), an mDNS discovery package, and `permission_handler`
  - Create the .NET solution `agent/` with projects `Agent.Core`, `Agent.Windows`, `Agent.Mac`, and `Agent.Tests` (xUnit + FsCheck)
  - _Requirements: 9.4_

- [x] 2. Implement the Dart Protocol_Codec
  - [x] 2.1 Implement `InputEvent` types and `ProtocolCodec`
    - Define the sealed `InputEvent` hierarchy (PointerMove, ButtonAction, ClickAction, ScrollEvent, ZoomEvent, AppSwitchEvent, KeyAction, Heartbeat) and `CodecError` (Malformed, VersionMismatch)
    - Implement `encode` (`[version u8][type u8][payload]`), `decode` returning a typed result and never throwing, and `prettyPrint`
    - Implement the length-prefix framing helper used by both Transports
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.7_

  - [ ]* 2.2 Write property test for encode/decode round trip
    - **Property 24: Protocol encode/decode round-trips for all event types**
    - **Validates: Requirements 10.1, 10.2, 10.6**

  - [ ]* 2.3 Write property test for malformed messages
    - **Property 25: Malformed messages always decode to an error, never a crash or bogus event**
    - **Validates: Requirements 10.3**

  - [ ]* 2.4 Write property test for unsupported versions
    - **Property 26: Unsupported protocol versions are reported distinctly**
    - **Validates: Requirements 10.4**

  - [ ]* 2.5 Write property test for the pretty printer
    - **Property 27: Pretty-printed output names the event type**
    - **Validates: Requirements 10.5**

- [x] 3. Implement Android storage (settings and paired hosts)
  - [x] 3.1 Implement `SettingsStore`
    - Persist Sensitivity, natural scrolling, and tap-to-click with `shared_preferences`
    - Reject Sensitivity outside [0.5, 5.0] and retain the previous value
    - Expose the latest Sensitivity to consumers on every change
    - _Requirements: 5.5, 12.1, 12.2, 12.4_

  - [ ]* 3.2 Write property test for settings persistence
    - **Property 33: Settings persist across restarts**
    - **Validates: Requirements 12.2**

  - [ ]* 3.3 Write property test for Sensitivity validation
    - **Property 35: Sensitivity updates only apply within the valid range**
    - Include boundary examples at exactly 0.5 and 5.0
    - **Validates: Requirements 12.4**

  - [ ]* 3.4 Write property test for latest Sensitivity
    - **Property 13: The most recently set sensitivity is always used**
    - **Validates: Requirements 5.5**

  - [x] 3.5 Implement `HostInfo`, `PairedHost`, and `PairedHostStore`
    - Persist `{hostInfo, sharedSecret, pairedAt}` with `flutter_secure_storage`
    - Support add, lookup by host id, list, and remove (deleting only that host's data)
    - _Requirements: 4.2, 4.8_

  - [ ]* 3.6 Write property test for paired host removal
    - **Property 10: Removing a paired host deletes only that host's data**
    - **Validates: Requirements 4.8**

- [x] 4. Implement the Gesture Recognizer
  - [x] 4.1 Implement `GestureClassifier` for pointer, tap, double-tap, and drag
    - Consume `GestureSample` streams as a pure function and emit `PointerMove`, `ClickAction`, and drag events (`DragStart`, `DragMove`, `DragEnd`)
    - Take the tap-to-click flag as input and suppress tap-derived clicks when it is disabled
    - _Requirements: 5.1, 5.3, 6.1, 6.2, 6.3, 6.4, 12.3_

  - [x] 4.2 Extend `GestureClassifier` for scroll, zoom, app switch, and dedicated buttons
    - Emit `ScrollEvent` for two-finger slides and invert the sign when natural scrolling is enabled
    - Emit `ZoomEvent` for pinch and `AppSwitchEvent` for three-finger horizontal slides
    - Map dedicated left/right button press and release to `ButtonAction` Down and Up
    - _Requirements: 6.5, 6.6, 7.1, 7.2, 7.3, 7.4, 7.5_

  - [ ]* 4.3 Write property test for pointer displacement
    - **Property 11: Pointer movement preserves relative displacement**
    - **Validates: Requirements 5.1**

  - [ ]* 4.4 Write property test for single-finger tap
    - **Property 14: Single-finger tap classifies as a left click**
    - **Validates: Requirements 6.1**

  - [ ]* 4.5 Write property test for two-finger tap
    - **Property 15: Two-finger tap classifies as a right click**
    - **Validates: Requirements 6.2**

  - [ ]* 4.6 Write property test for double tap
    - **Property 16: Double-tap classifies as a double left click**
    - **Validates: Requirements 6.3**

  - [ ]* 4.7 Write property test for drag
    - **Property 17: Tap-hold-slide classifies as a drag for the full hold duration**
    - **Validates: Requirements 6.4**

  - [ ]* 4.8 Write property test for tap-to-click disabled
    - **Property 34: Disabling tap-to-click suppresses click events from taps**
    - **Validates: Requirements 12.3**

  - [ ]* 4.9 Write property test for dedicated buttons
    - **Property 18: Dedicated button controls map press/release to button down/up**
    - **Validates: Requirements 6.6**

  - [ ]* 4.10 Write property test for scroll and natural scrolling
    - **Property 19: Two-finger slide maps to a scroll event honoring natural scrolling**
    - **Validates: Requirements 7.1, 7.2, 7.3**

  - [ ]* 4.11 Write property test for pinch zoom
    - **Property 20: Pinch gesture maps to a zoom event**
    - **Validates: Requirements 7.4**

- [x] 5. Implement the Keyboard Recognizer
  - [x] 5.1 Implement `KeyboardRecognizer` and modifier toggle state
    - Map typed characters (including non-ASCII Unicode codepoints) and special keys (Backspace, Enter, Tab, Escape, Delete, arrows, F1-F12) to `KeyAction`
    - Track Shift, Control, Alt, and platform-key toggles and attach the active modifier set to the next key action
    - _Requirements: 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

  - [ ]* 5.2 Write property test for Unicode key events
    - **Property 22: Key event round-trips for any Unicode character**
    - **Validates: Requirements 8.2, 8.7**

  - [ ]* 5.3 Write property test for modifier attachment
    - **Property 23: Active modifiers are always attached to the next key action**
    - **Validates: Requirements 8.5**

  - [ ]* 5.4 Write unit tests for special key mapping
    - Cover each special key and F1-F12
    - _Requirements: 8.3, 8.6_

- [x] 6. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement Android discovery, transports, and connection management
  - [x] 7.1 Implement host display mapping and manual IP validator
    - Map `HostInfo` to a display record with name, OS, and Transport
    - Validate manual input as syntactically valid IPv4 or IPv6
    - _Requirements: 1.2, 2.2_

  - [ ]* 7.2 Write property test for host display mapping
    - **Property 1: Discovered host info renders all required fields**
    - **Validates: Requirements 1.2**

  - [ ]* 7.3 Write property test for manual IP validation
    - **Property 2: Manual IP validation accepts only syntactically valid addresses**
    - **Validates: Requirements 2.2**

  - [x] 7.4 Implement the secure channel
    - Derive a per-Connection key from the pairing shared secret and encrypt/decrypt framed Input_Events with authenticated encryption
    - _Requirements: 4.7, 10.7_

  - [ ]* 7.5 Write property test for encryption
    - **Property 9: Input event encryption round-trips and conceals plaintext**
    - **Validates: Requirements 4.7**

  - [x] 7.6 Implement `WifiTransportClient` and mDNS discovery
    - Discover advertised Desktop_Agent services, connect over TCP with TLS and length-prefix framing, and support manual IP entry
    - Map socket and timeout failures to user-facing failure reasons
    - _Requirements: 1.1, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4_

  - [x] 7.7 Implement `BluetoothTransportClient` and Bluetooth discovery
    - Discover devices exposing the agent's RFCOMM service, connect with the same framing, and detect the adapter being off
    - Map failures to user-facing failure reasons
    - _Requirements: 1.1, 3.1, 3.2, 3.3, 3.4_

  - [x] 7.8 Implement `TransportManager` and the connection state machine
    - Implement states Discovering, Connecting, AwaitingPairing, Authenticated, and Disconnected, with the pairing-code submission flow and paired-host skip
    - Run heartbeat sending, disconnect within 2 seconds, auto-reconnect every 3 seconds for up to 30 seconds, and the 60-second background timeout
    - Read the Host OS reported by the agent on connect and expose the platform-key label (Command or Windows)
    - Expose a connection-status mapping with host name and Transport
    - _Requirements: 4.2, 4.3, 4.5, 9.1, 9.2, 9.3, 11.1, 11.2, 11.3, 11.6_

  - [ ]* 7.9 Write property test for connection status display
    - **Property 28: Connection status display always reflects the active host and transport**
    - **Validates: Requirements 11.1**

  - [ ]* 7.10 Write property test for reconnection schedule
    - **Property 29: Reconnection is attempted every 3 seconds and stops after 30 seconds**
    - Include 30-second boundary examples
    - **Validates: Requirements 11.3**

  - [ ]* 7.11 Write property test for background timeout
    - **Property 32: Background duration determines whether the connection stays open**
    - Include the 60-second boundary example
    - **Validates: Requirements 11.6**

  - [ ]* 7.12 Write unit tests for connection failures and state transitions
    - Cover failure-reason messages, Bluetooth-off prompt, incorrect-code handling, and platform-key labels
    - _Requirements: 2.4, 3.3, 3.4, 4.3, 9.2, 9.3_

- [x] 8. Implement the Android UI and wiring
  - [x] 8.1 Build the host list screen
    - Show discovered Hosts, refresh, the 10-second no-host message with manual IP entry, and permission requests with an explanation for each permission
    - Prompt the user to turn Bluetooth on when it is off
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 3.3_

  - [x] 8.2 Build the pairing screen
    - Accept the 6-digit Pairing_Code, show the incorrect-code message, and show a lockout countdown
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 8.3 Build the Trackpad_Surface screen
    - Add the touch surface, dedicated left/right button controls, a connected-host and Transport banner, and a disconnect action
    - _Requirements: 5.1, 6.5, 6.6, 7.1, 11.1, 11.2_

  - [x] 8.4 Build the keyboard panel
    - Open the Android on-screen keyboard, add the Shift/Control/Alt/platform-key toggles with the OS-specific label, and add the F1-F12 row
    - _Requirements: 8.1, 8.4, 8.6, 9.2, 9.3_

  - [x] 8.5 Build the settings screen
    - Add Sensitivity, natural scrolling, and tap-to-click controls bound to `SettingsStore`
    - _Requirements: 12.1, 12.2, 12.4_

  - [x] 8.6 Wire the app together
    - Connect gesture and keyboard recognizers to the codec, secure channel, and `TransportManager`
    - Apply the current Sensitivity to pointer deltas before encoding, without requiring reconnection
    - Send pointer events at 60 or more per second during continuous movement
    - Add app navigation, the connected-state display, and the lifecycle (background) hook
    - _Requirements: 5.3, 5.5, 8.1, 8.2, 11.6, 12.3_

  - [ ]* 8.7 Write widget tests for the Android UI
    - Verify presence of dedicated buttons, modifier toggles, F1-F12 row, host list states, and settings controls
    - _Requirements: 1.4, 6.5, 8.4, 8.6, 12.1_

- [x] 9. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Implement the Desktop_Agent core (C#, `Agent.Core`)
  - [x] 10.1 Implement the codec port
    - Port `InputEvent`, `ProtocolCodec`, and framing to C# with the same wire format as the Dart codec
    - Add golden byte vectors generated from the Dart codec to `Agent.Tests`
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.7_

  - [ ]* 10.2 Write property test for agent codec round trip
    - **Property 24: Protocol encode/decode round-trips for all event types**
    - **Validates: Requirements 10.1, 10.2, 10.6**

  - [ ]* 10.3 Write property test for agent malformed messages
    - **Property 25: Malformed messages always decode to an error, never a crash or bogus event**
    - **Validates: Requirements 10.3**

  - [ ]* 10.4 Write property test for agent version mismatch
    - **Property 26: Unsupported protocol versions are reported distinctly**
    - **Validates: Requirements 10.4**

  - [ ]* 10.5 Write property test for agent pretty printer
    - **Property 27: Pretty-printed output names the event type**
    - **Validates: Requirements 10.5**

  - [x] 10.6 Implement the agent secure channel
    - Implement the matching key derivation and authenticated encryption for framed events
    - _Requirements: 4.7_

  - [ ]* 10.7 Write property test for agent encryption
    - **Property 9: Input event encryption round-trips and conceals plaintext**
    - **Validates: Requirements 4.7**

  - [x] 10.8 Implement `PairingAuthManager`
    - Generate 6-digit Pairing_Codes, verify entered codes, count consecutive failures, invalidate the code after 3, and refuse attempts for 60 seconds
    - Skip the challenge for Paired_Hosts and track authenticated state per Connection
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ]* 10.9 Write property test for pairing code format
    - **Property 3: Pairing code is always a 6-digit code**
    - **Validates: Requirements 4.1**

  - [ ]* 10.10 Write property test for matching code
    - **Property 4: Matching pairing code authenticates the Connection**
    - **Validates: Requirements 4.2**

  - [ ]* 10.11 Write property test for non-matching code
    - **Property 5: Non-matching pairing code rejects the Connection**
    - **Validates: Requirements 4.3**

  - [ ]* 10.12 Write property test for lockout
    - **Property 6: Three consecutive incorrect codes trigger a lockout**
    - Include the 60-second expiry boundary example
    - **Validates: Requirements 4.4**

  - [ ]* 10.13 Write property test for paired host skip
    - **Property 7: Known paired hosts skip the pairing challenge**
    - **Validates: Requirements 4.5**

  - [x] 10.14 Implement `EventDispatcher` and the `IInputInjector` interface
    - Define `IInputInjector` (`MoveTo`, `Click`, `KeyDown`, `KeyUp`, `Scroll`)
    - Discard events from unauthenticated Connections, apply Sensitivity scaling, and clamp the pointer to display bounds
    - Map `AppSwitchEvent` to Command+Tab or Alt+Tab by Host OS
    - Track held buttons and modifiers and release them all on Connection close
    - _Requirements: 4.6, 5.2, 5.6, 6.6, 7.5, 11.5_

  - [ ]* 10.15 Write property test for unauthenticated events
    - **Property 8: Unauthenticated connections never affect injected state**
    - **Validates: Requirements 4.6**

  - [ ]* 10.16 Write property test for scaling and clamping
    - **Property 12: Pointer movement is scaled by sensitivity and clamped to the display**
    - **Validates: Requirements 5.2, 5.6**

  - [ ]* 10.17 Write property test for app switch shortcut
    - **Property 21: Three-finger horizontal slide maps to the OS-correct app-switch shortcut**
    - **Validates: Requirements 7.5**

  - [ ]* 10.18 Write property test for release on close
    - **Property 31: Closing a connection always releases all held buttons and modifiers**
    - **Validates: Requirements 11.5**

  - [x] 10.19 Implement the agent `ConnectionSession`
    - Report the Host OS to the Android_App on connect
    - Decode frames, discard malformed messages while keeping the Connection alive, and log the pretty-printed error
    - Close the Connection after 10 seconds without data or heartbeat
    - _Requirements: 9.1, 10.3, 10.4, 11.4, 11.5_

  - [ ]* 10.20 Write property test for heartbeat timeout
    - **Property 30: Heartbeat silence beyond 10 seconds is always treated as a dead connection**
    - **Validates: Requirements 11.4**

- [x] 11. Implement the Desktop_Agent platform layer
  - [x] 11.1 Implement `WindowsInputInjector` in `Agent.Windows`
    - Use `SendInput` for pointer, buttons, scroll, key codes, and Unicode characters
    - _Requirements: 5.2, 6.1, 6.2, 6.3, 6.6, 7.1, 7.2, 7.4, 8.2, 8.3, 8.7, 9.4_

  - [x] 11.2 Implement `MacInputInjector` in `Agent.Mac`
    - Use `CGEventPost` with mouse, scroll, and keyboard events via P/Invoke, including Unicode strings
    - _Requirements: 5.2, 6.1, 6.2, 6.3, 6.6, 7.1, 7.2, 7.4, 8.2, 8.3, 8.7, 9.4_

  - [x] 11.3 Implement the Wi-Fi server and discovery advertiser
    - Accept TCP with TLS, advertise the mDNS service with Host name and OS, and hand connections to `ConnectionSession`
    - _Requirements: 1.1, 1.2, 2.1, 9.1_

  - [x] 11.4 Implement the Bluetooth server and discovery advertiser
    - Host an RFCOMM service with an SDP record and hand connections to `ConnectionSession` using the same framing
    - _Requirements: 1.1, 1.2, 3.1, 10.7_

  - [x] 11.5 Implement permission checks and the pairing-code display
    - Detect missing macOS Accessibility or Windows injection permission and show grant instructions
    - Show the Pairing_Code in a tray or menu-bar window
    - _Requirements: 4.1, 9.5_

  - [x] 11.6 Wire the agent entry point
    - Select the injector by OS, start the transports and advertisers, and connect `PairingAuthManager`, `EventDispatcher`, and `ConnectionSession`
    - _Requirements: 4.6, 9.4, 11.5_

  - [ ]* 11.7 Write unit tests for key and OS mappings
    - Cover the special-key to native key code tables and the OS identifier reported to the Android_App
    - _Requirements: 8.3, 9.1_

- [ ] 12. Cross-implementation and integration testing
  - [ ]* 12.1 Write codec conformance tests across Dart and C#
    - Decode the shared golden vectors in both implementations and assert identical results
    - _Requirements: 10.6, 10.7_

  - [ ]* 12.2 Write a loopback integration test
    - Connect the Dart `TransportManager` to the agent `ConnectionSession` with a fake injector, covering pairing, pointer events, key events, and disconnect release
    - _Requirements: 2.1, 4.2, 4.6, 5.2, 8.2, 11.5_

- [x] 13. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Build and package the macOS agent
  - Publish `agent/Agent.Mac` self-contained for `osx-arm64` (already output to `dist/mac-agent`) and `osx-x64`
  - Create a `TrackpadAgent.app` bundle (Info.plist with bundle id and `LSUIElement` unset so the terminal output stays visible or documented, plus the published files) and ad-hoc codesign it so the Accessibility permission sticks to a stable identity
  - Add a `scripts/build-mac-agent.sh` that repeats the publish, bundle and sign steps, and a short `agent/README.md` covering run steps, Accessibility and firewall prompts, and the Wi-Fi-only limitation
  - Verify the published binary starts and prints a Pairing_Code
  - _Requirements: 9.4, 9.5_

- [x] 15. Build the Android APK
  - Run `flutter build apk --release` (fall back to `--debug` if release signing or Gradle setup blocks it) and fix any Gradle, manifest, or minSdk problems that the plugins (`flutter_blue_classic`, `nsd`, `permission_handler`, `flutter_secure_storage`) cause
  - Copy the resulting APK to `dist/android/trackpad.apk` and report its size and signing type
  - Add the build steps to a short `README.md` section on installing the APK and pairing with the Mac agent
  - _Requirements: 1.1, 2.1_

- [x] 16. Fix the three-finger swipe app switch
  - Reproduce the failure in unit tests, then find the root cause in the Android pipeline (`GestureClassifier` three-finger detection, finger-count transitions, thresholds, `InputPipeline` encoding) and the agent side (`EventDispatcher` app-switch mapping, `MacInputInjector` Command+Tab handling)
  - Fix the cause and add regression tests for a three-finger horizontal swipe, including fingers landing one at a time
  - Rebuild the APK to `dist/android/trackpad.apk` and the Mac agent via `scripts/build-mac-agent.sh`
  - _Requirements: 7.5_

- [x] 17. Remove pinch zoom
  - Stop `GestureClassifier` from detecting pinch so a two-finger move is always a scroll, and remove the pinch threshold config and its tests
  - Remove zoom handling from the pipeline, dispatcher and both injectors (`Zoom` on `IInputInjector`, Windows Ctrl+wheel, Mac Cmd+`=`/`-`) and update the affected tests
  - Keep the wire format unchanged: leave the `ZoomEvent` type tag in both codecs so the golden vectors stay valid, and have the agent ignore it
  - Rebuild the APK to `dist/android/trackpad.apk` and the Mac agent via `scripts/build-mac-agent.sh all`
  - _Requirements: 7.4_

- [x] 18. Add an app-switch button to the trackpad screen
  - Add a button next to the left and right buttons that sends the same `AppSwitchEvent` as the three-finger swipe (tap = switch to next app; include a previous-app direction if the event supports it)
  - Route it through `InputPipeline` and `TransportManager.send`, and add a widget test and a pipeline test
  - Keep the three-finger swipe working
  - Rebuild the APK to `dist/android/trackpad.apk`
  - _Requirements: 6.5, 7.5_

- [-] 19. Publish the project to a public GitHub repository
  - Audit the working tree for anything that must not be public (keystores, `key.properties`, `local.properties`, `.pfx` certificates, paired-host files, tokens, personal paths) and fix `.gitignore` for Flutter, Android and .NET build output (`bin/`, `obj/`, `build/`, `dist/`)
  - Initialize git if needed, make a clean initial commit, and create a public repository with `gh repo create` (name `trackpad`) and push
  - Report the repository URL, or stop and report if `gh` is not installed or not authenticated
  - _Requirements: 9.4_

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties; unit tests validate specific examples and edge cases
- The design allows C#/.NET or C++ on Windows and Swift on macOS. This plan uses one .NET solution for both agents (shared core, per-OS injectors) so each agent property is tested once. Switch macOS to Swift if a native agent is preferred.
- Sensitivity is not carried in the wire protocol. This plan scales pointer deltas on the Android side before encoding (task 8.6), and the agent dispatcher accepts a Sensitivity parameter (default 1.0) so Property 12 still applies.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2.1", "3.1", "3.5"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "2.5", "3.2", "3.3", "3.4", "3.6", "4.1", "5.1"] },
    { "id": 3, "tasks": ["4.2", "4.3", "4.4", "4.5", "4.6", "4.7", "4.8", "5.2", "5.3", "5.4"] },
    { "id": 4, "tasks": ["4.9", "4.10", "4.11"] },
    { "id": 5, "tasks": ["6"] },
    { "id": 6, "tasks": ["7.1", "7.4"] },
    { "id": 7, "tasks": ["7.2", "7.3", "7.5", "7.6", "7.7"] },
    { "id": 8, "tasks": ["7.8"] },
    { "id": 9, "tasks": ["7.9", "7.10", "7.11", "7.12", "8.1", "8.2", "8.3", "8.4", "8.5"] },
    { "id": 10, "tasks": ["8.6"] },
    { "id": 11, "tasks": ["8.7"] },
    { "id": 12, "tasks": ["9"] },
    { "id": 13, "tasks": ["10.1", "10.8"] },
    { "id": 14, "tasks": ["10.2", "10.3", "10.4", "10.5", "10.6", "10.9", "10.10", "10.11", "10.12", "10.13", "10.14"] },
    { "id": 15, "tasks": ["10.7", "10.15", "10.16", "10.17", "10.18", "10.19", "11.1", "11.2"] },
    { "id": 16, "tasks": ["10.20", "11.3", "11.4", "11.5", "11.7"] },
    { "id": 17, "tasks": ["11.6"] },
    { "id": 18, "tasks": ["12.1", "12.2"] },
    { "id": 19, "tasks": ["13"] },
    { "id": 20, "tasks": ["14"] },
    { "id": 21, "tasks": ["15"] },
    { "id": 22, "tasks": ["16"] },
    { "id": 23, "tasks": ["17"] },
    { "id": 24, "tasks": ["18"] },
    { "id": 25, "tasks": ["19"] }
  ]
}
```
