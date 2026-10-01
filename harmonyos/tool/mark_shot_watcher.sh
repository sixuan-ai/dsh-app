#!/usr/bin/env bash
# Watches the emulator app's flutter logcat stream for MARK <name> lines from
# the integration walkthrough and captures a real framebuffer screenshot at
# each. Always targets the emulator (-s) so a USB-connected phone is never
# touched.
set -u
export PATH="/home/x/Android/Sdk/platform-tools:$PATH"
OUT="$1"
SER=emulator-5554
mkdir -p "$OUT"
adb -s "$SER" logcat -c 2>/dev/null
adb -s "$SER" logcat -s flutter 2>/dev/null | while read -r line; do
  name=$(printf '%s' "$line" | sed -n 's/.*MARK \([A-Za-z0-9_]*\).*/\1/p')
  if [ -n "$name" ]; then
    adb -s "$SER" exec-out screencap -p > "$OUT/$name.png" 2>/dev/null
    echo "captured $name"
  fi
done
