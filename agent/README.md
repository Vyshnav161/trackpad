# Trackpad Desktop Agent (macOS)

## Build

```sh
scripts/build-mac-agent.sh [arm64|x64|all]   # default: arm64
```

Outputs (relative to the repo root, git-ignored):

- `dist/mac-agent-<arch>/`: self-contained publish (no .NET install needed)
- `dist/<arch>/TrackpadAgent.app`: bundle (`com.trackpad.agent`), ad-hoc signed

## Run

- Double-click `TrackpadAgent.app`. The launcher opens Terminal and runs the agent there, because the agent prints the 6-digit **Pairing Code** to the console and Finder launches have no visible console.
- Or run directly: `dist/arm64/TrackpadAgent.app/Contents/MacOS/Agent.Mac`.
- Enter the code in the Android app. Press Ctrl+C (or close the Terminal window) to stop.

If the app is blocked as "unidentified developer", right-click it and choose Open once, or run `xattr -dr com.apple.quarantine TrackpadAgent.app`.

## Accessibility permission

Input injection needs Accessibility access. The agent prints a warning if it is missing.

1. System Settings > Privacy & Security > Accessibility.
2. Enable **Terminal** (the launcher runs the agent inside Terminal, so macOS attributes the permission to Terminal). If you run the binary from another terminal app, enable that app.
3. Restart the agent.

The app is signed ad hoc (`codesign --force --deep -s -`) so its identity stays stable across launches. Rebuilding changes the code hash, so you may need to re-grant permission after a rebuild.

## Firewall prompt

On first start macOS may ask whether `Agent.Mac` may accept incoming network connections. Choose **Allow**; the Android app connects to the agent's Wi-Fi port (printed at startup) and discovers it with mDNS.

## Limitations

- **Wi-Fi only on macOS.** Bluetooth RFCOMM is not implemented on macOS, so the agent logs "Bluetooth disabled" and the phone and Mac must be on the same Wi-Fi network (or enter the Mac's IP manually).
