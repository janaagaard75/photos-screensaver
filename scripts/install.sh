#!/bin/bash
# Builds the screensaver, installs it in ~/Library/Screen Savers and starts it.
#
# Usage: scripts/install.sh [Debug|Release]   (default: Debug)

set -euo pipefail

configuration="${1:-Debug}"
if [[ "$configuration" != "Debug" && "$configuration" != "Release" ]]; then
  echo "Usage: $0 [Debug|Release]" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

product="build/Build/Products/$configuration/PhotosScreensaver.saver"
install_dir="$HOME/Library/Screen Savers"

echo "Building $configuration…"
xcodebuild build \
  -project PhotosScreensaver.xcodeproj \
  -scheme PhotosScreensaver \
  -configuration "$configuration" \
  -derivedDataPath build \
  -quiet

# macOS keeps the previous build loaded until these processes exit.
echo "Stopping the screensaver host and System Settings…"
killall legacyScreenSaver 2>/dev/null || true
killall "System Settings" 2>/dev/null || true

echo "Installing in $install_dir…"
mkdir -p "$install_dir"
rm -rf "$install_dir/PhotosScreensaver.saver"
cp -R "$product" "$install_dir/"

echo "Starting the screensaver…"
open -a ScreenSaverEngine
