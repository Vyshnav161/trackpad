# Requirements Document

## Introduction

Android Remote Input turns an Android phone into a wireless trackpad and keyboard for a Mac or Windows computer. The Android_App (a Flutter application) captures touch gestures and keystrokes. It sends them as input events to a Desktop_Agent running on the computer, over Wi-Fi or Bluetooth. The Desktop_Agent injects the events into the operating system as mouse and keyboard input.

## Glossary

- **Android_App**: The Flutter application on the Android phone that provides the Trackpad_Surface and the Keyboard_Input.
- **Desktop_Agent**: The application running on the Mac or Windows computer that receives Input_Events and injects them into the operating system.
- **Host**: The Mac or Windows computer controlled by the Android_App.
- **Connection**: An active, authenticated communication session between the Android_App and the Desktop_Agent.
- **Transport**: The communication medium of a Connection, either Wi-Fi or Bluetooth.
- **Trackpad_Surface**: The touch area of the Android_App that is interpreted as a trackpad.
- **Keyboard_Input**: The Android_App component that captures key presses, including the Android on-screen keyboard and special keys.
- **Input_Event**: A message describing one pointer movement, click, scroll, or key action.
- **Protocol_Codec**: The component that serializes Input_Events to bytes and parses bytes to Input_Events.
- **Pairing_Code**: A one-time code of 6 decimal digits shown by the Desktop_Agent and entered in the Android_App to authorize a new Host.
- **Paired_Host**: A Host that has completed pairing with the Android_App and is stored for later reconnection.
- **Sensitivity**: A user-configurable multiplier applied to pointer movement, with a range of 0.5 to 5.0.

## Requirements

### Requirement 1: Discover Hosts

**User Story:** As a user, I want to see the computers available near me, so that I can pick the one I want to control.

#### Acceptance Criteria

1. WHEN the user opens the host list, THE Android_App SHALL display Hosts discovered on the local Wi-Fi network and Bluetooth devices running the Desktop_Agent.
2. WHEN a Host is discovered, THE Android_App SHALL display the Host name, the operating system (macOS or Windows), and the Transport.
3. WHEN the user requests a refresh, THE Android_App SHALL repeat discovery and update the host list within 10 seconds.
4. IF no Host is discovered within 10 seconds, THEN THE Android_App SHALL display a message offering manual entry of a Host IP address.
5. IF the Android_App lacks the Android permissions required for Wi-Fi or Bluetooth discovery, THEN THE Android_App SHALL request the permissions and explain why each is needed.

### Requirement 2: Connect over Wi-Fi

**User Story:** As a user, I want to connect to my computer over Wi-Fi, so that I can control it from anywhere on my local network.

#### Acceptance Criteria

1. WHEN the user selects a Host discovered over Wi-Fi, THE Android_App SHALL establish a Connection to the Desktop_Agent using the Wi-Fi Transport.
2. WHEN the user enters a Host IP address manually, THE Android_App SHALL establish a Connection to that address using the Wi-Fi Transport.
3. WHEN a Wi-Fi Connection is established, THE Android_App SHALL display the connected state within 5 seconds of the user selecting the Host.
4. IF a Wi-Fi Connection attempt fails, THEN THE Android_App SHALL display the failure reason.

### Requirement 3: Connect over Bluetooth

**User Story:** As a user, I want to connect to my computer over Bluetooth, so that I can control it without a shared Wi-Fi network.

#### Acceptance Criteria

1. WHEN the user selects a Host discovered over Bluetooth, THE Android_App SHALL establish a Connection to the Desktop_Agent using the Bluetooth Transport.
2. WHEN a Bluetooth Connection is established, THE Android_App SHALL display the connected state within 10 seconds of the user selecting the Host.
3. IF Bluetooth is turned off on the Android device, THEN THE Android_App SHALL prompt the user to turn Bluetooth on.
4. IF a Bluetooth Connection attempt fails, THEN THE Android_App SHALL display the failure reason.

### Requirement 4: Pair and Authenticate Hosts

**User Story:** As a user, I want only my phone to be able to control my computer, so that nobody else can send input to it.

#### Acceptance Criteria

1. WHEN the Android_App connects to a Host that is not a Paired_Host, THE Desktop_Agent SHALL display a Pairing_Code.
2. WHEN the user enters a Pairing_Code that matches the displayed code, THE Desktop_Agent SHALL accept the Connection and THE Android_App SHALL store the Host as a Paired_Host.
3. IF the user enters a Pairing_Code that does not match, THEN THE Desktop_Agent SHALL reject the Connection and THE Android_App SHALL display an incorrect-code message.
4. IF 3 consecutive incorrect Pairing_Codes are entered, THEN THE Desktop_Agent SHALL invalidate the displayed Pairing_Code and refuse new pairing attempts for 60 seconds.
5. WHEN the Android_App connects to a Paired_Host, THE Desktop_Agent SHALL accept the Connection without requesting a Pairing_Code.
6. WHILE a Connection is not authenticated, THE Desktop_Agent SHALL discard all received Input_Events.
7. THE Android_App and THE Desktop_Agent SHALL encrypt all Input_Events exchanged over a Connection.
8. WHEN the user removes a Paired_Host in the Android_App, THE Android_App SHALL delete the stored pairing data for that Host.

### Requirement 5: Move the Pointer

**User Story:** As a user, I want to move the computer's pointer by sliding my finger, so that I can aim at things on the screen.

#### Acceptance Criteria

1. WHEN the user slides one finger on the Trackpad_Surface, THE Android_App SHALL send pointer-movement Input_Events with relative X and Y displacement.
2. WHEN the Desktop_Agent receives a pointer-movement Input_Event, THE Desktop_Agent SHALL move the Host pointer by the displacement multiplied by the Sensitivity.
3. WHILE a Connection is established, THE Android_App SHALL send pointer-movement Input_Events at a rate of at least 60 events per second during continuous finger movement.
4. WHILE a Connection is established over Wi-Fi, THE Desktop_Agent SHALL apply a pointer-movement Input_Event within 50 ms of the Android_App sending the event, measured on a local network with no more than 20 ms round-trip time.
5. WHEN the user changes the Sensitivity, THE Android_App SHALL apply the new value to subsequent pointer movement without requiring reconnection.
6. THE Desktop_Agent SHALL keep the Host pointer within the bounds of the Host display area.

### Requirement 6: Click and Drag

**User Story:** As a user, I want to click, right-click, and drag, so that I can operate buttons, menus, and windows.

#### Acceptance Criteria

1. WHEN the user taps once on the Trackpad_Surface with one finger, THE Desktop_Agent SHALL perform a left click on the Host.
2. WHEN the user taps once on the Trackpad_Surface with two fingers, THE Desktop_Agent SHALL perform a right click on the Host.
3. WHEN the user double-taps on the Trackpad_Surface with one finger, THE Desktop_Agent SHALL perform a double left click on the Host.
4. WHEN the user taps and then immediately touches and holds on the Trackpad_Surface and slides one finger, THE Desktop_Agent SHALL hold the left button down and move the pointer until the finger is lifted.
5. THE Android_App SHALL display dedicated left-button and right-button controls below the Trackpad_Surface.
6. WHEN the user presses a dedicated button control, THE Desktop_Agent SHALL press the corresponding mouse button on the Host, and WHEN the user releases the control, THE Desktop_Agent SHALL release the button.

### Requirement 7: Scroll and Gestures

**User Story:** As a user, I want to scroll and use multi-finger gestures, so that I can browse documents and switch between windows.

#### Acceptance Criteria

1. WHEN the user slides two fingers vertically on the Trackpad_Surface, THE Desktop_Agent SHALL scroll the Host content vertically by the corresponding distance.
2. WHEN the user slides two fingers horizontally on the Trackpad_Surface, THE Desktop_Agent SHALL scroll the Host content horizontally by the corresponding distance.
3. WHERE natural scrolling is enabled in the Android_App settings, THE Android_App SHALL invert the scroll direction of scroll Input_Events.
4. (Removed: pinch-to-zoom is not supported. A two-finger move is always a scroll. The number is kept so criteria 7.5 and later references stay stable.)
5. WHEN the user slides three fingers horizontally on the Trackpad_Surface, THE Desktop_Agent SHALL trigger the Host application-switch action: Command+Tab on macOS and Alt+Tab on Windows.

### Requirement 8: Type with the Keyboard

**User Story:** As a user, I want to type on my phone's keyboard and have the text appear on my computer, so that I can enter text without a physical keyboard.

#### Acceptance Criteria

1. WHEN the user opens the keyboard in the Android_App, THE Android_App SHALL display the Android on-screen keyboard and direct all key input to the Keyboard_Input.
2. WHEN the user types a character, THE Android_App SHALL send a key Input_Event, and THE Desktop_Agent SHALL type the same character on the Host.
3. WHEN the user presses Backspace, Enter, Tab, Escape, Delete, or an arrow key, THE Desktop_Agent SHALL perform the corresponding key action on the Host.
4. THE Android_App SHALL provide on-screen toggle keys for Shift, Control, Alt, and the platform key (Command on macOS, Windows key on Windows).
5. WHEN the user activates a modifier toggle key and then types a character, THE Desktop_Agent SHALL perform the key action with the modifier applied.
6. THE Android_App SHALL provide a row of function keys F1 to F12.
7. WHEN the user types a character outside the basic ASCII range, THE Desktop_Agent SHALL type that Unicode character on the Host.
8. WHILE a Connection is established over Wi-Fi, THE Desktop_Agent SHALL apply a key Input_Event within 100 ms of the Android_App sending the event, measured on a local network with no more than 20 ms round-trip time.

### Requirement 9: Adapt to Host Operating System

**User Story:** As a user, I want shortcuts and keys to behave correctly on both Mac and Windows, so that I do not need to remember platform differences.

#### Acceptance Criteria

1. WHEN the Android_App connects to a Host, THE Desktop_Agent SHALL report the Host operating system to the Android_App.
2. WHILE the Host is running macOS, THE Android_App SHALL label the platform key as Command.
3. WHILE the Host is running Windows, THE Android_App SHALL label the platform key as Windows.
4. THE Desktop_Agent SHALL run on macOS and on Windows.
5. IF the Desktop_Agent lacks the operating system permission required to inject input, THEN THE Desktop_Agent SHALL display instructions for granting the permission.

### Requirement 10: Serialize Input Events

**User Story:** As a developer, I want a well-defined message format for Input_Events, so that the Android_App and Desktop_Agent interoperate reliably over both Transports.

#### Acceptance Criteria

1. THE Protocol_Codec SHALL serialize each Input_Event to a binary message that includes a protocol version, an event type, and the event payload.
2. WHEN the Protocol_Codec receives a valid binary message, THE Protocol_Codec SHALL parse the message into an Input_Event.
3. IF the Protocol_Codec receives a malformed message, THEN THE Protocol_Codec SHALL return a descriptive error and THE Desktop_Agent SHALL discard the message.
4. IF the Protocol_Codec receives a message with an unsupported protocol version, THEN THE Protocol_Codec SHALL return a version-mismatch error.
5. THE Protocol_Codec SHALL provide a pretty printer that formats an Input_Event as human-readable text for logging.
6. FOR ALL valid Input_Events, serializing then parsing then serializing SHALL produce an equivalent Input_Event (round-trip property).
7. THE Protocol_Codec SHALL use the same message format for the Wi-Fi Transport and the Bluetooth Transport.

### Requirement 11: Manage Connection Lifecycle

**User Story:** As a user, I want the connection to recover or end cleanly, so that the pointer and keys never get stuck.

#### Acceptance Criteria

1. WHILE a Connection is established, THE Android_App SHALL display the connected Host name and Transport.
2. WHEN the user selects disconnect, THE Android_App SHALL close the Connection within 2 seconds.
3. IF the Connection is lost unexpectedly, THEN THE Android_App SHALL display a disconnected state and attempt to reconnect to the Paired_Host every 3 seconds for up to 30 seconds.
4. IF the Desktop_Agent receives no data or heartbeat for 10 seconds, THEN THE Desktop_Agent SHALL close the Connection.
5. WHEN a Connection closes, THE Desktop_Agent SHALL release all mouse buttons and modifier keys that the Connection held down.
6. WHILE a Connection is established and the Android_App is in the background, THE Android_App SHALL keep the Connection open for 60 seconds before closing the Connection.

### Requirement 12: Configure Settings

**User Story:** As a user, I want to adjust the trackpad behavior, so that it matches my preferences.

#### Acceptance Criteria

1. THE Android_App SHALL provide settings for Sensitivity, natural scrolling, and tap-to-click.
2. WHEN the user changes a setting, THE Android_App SHALL persist the value across application restarts.
3. WHERE tap-to-click is disabled, THE Android_App SHALL send click Input_Events only from the dedicated button controls.
4. IF the user enters a Sensitivity outside the range 0.5 to 5.0, THEN THE Android_App SHALL reject the value and retain the previous Sensitivity.
