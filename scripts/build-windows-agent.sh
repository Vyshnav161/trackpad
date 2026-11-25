#!/usr/bin/env bash
# Cross-publish the Windows agent (self-contained, win-x64) from macOS/Linux/Windows
# and zip it. Output: dist/windows-agent/ and dist/release/trackpad-agent-windows-x64.zip
# Note: the result has not been tested on a real Windows machine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$ROOT/dist/windows-agent"
OUT="$ROOT/dist/release"
rm -rf "$PUB"
(cd "$ROOT/agent" && dotnet publish Agent.Windows -c Release -r win-x64 --self-contained -o "$PUB")
test -f "$PUB/Agent.Windows.exe"
mkdir -p "$OUT"
rm -f "$OUT/trackpad-agent-windows-x64.zip"
(cd "$PUB" && zip -qr "$OUT/trackpad-agent-windows-x64.zip" .)
echo "==> $OUT/trackpad-agent-windows-x64.zip"
