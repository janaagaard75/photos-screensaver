# Photos Screensaver

A macOS screensaver that shows the photos in a folder of your choice. Photos slowly zoom and pan (the "Ken Burns" effect) and crossfade into each other, like the built-in screensaver, but you choose how long each photo stays on screen.

- Choose any folder. Subfolders are included.
- Choose the time per photo, from 5 seconds to 10 minutes. The default is 30 seconds.
- JPEG, PNG and HEIC/HEIF files are supported.
- Photos are shown in random order. Every photo is shown once before the order is reshuffled.
- Each display runs its own slideshow.

Requires macOS 14 Sonoma or later.

## Build and install

1. Open `PhotosScreensaver.xcodeproj` in Xcode.
2. Build with Product → Build (⌘B).
3. Right-click the product under Products → Show in Finder, and double-click `PhotosScreensaver.saver` to install it.
4. Open System Settings → Screen Saver, select Photos Screensaver, and click Options… to choose a folder and the time per photo.

Or from the command line:

```sh
xcodebuild -project PhotosScreensaver.xcodeproj -scheme PhotosScreensaver -configuration Release -derivedDataPath build
open build/Build/Products/Release/PhotosScreensaver.saver
```

The bundle is ad-hoc signed. If macOS refuses to open it, allow it under System Settings → Privacy & Security.

## Development notes

- **Logs.** The screensaver logs to the unified log. Follow it in a second Terminal window while the screensaver runs:

  ```sh
  log stream --level debug --predicate 'subsystem == "net.aagaard.PhotosScreensaver"'
  ```

  Crash reports show up in Console.app under Crash Reports, filed under `legacyScreenSaver`.
- **Debug builds use a sample folder.** When no folder has been chosen, they show the photos in a hard-coded sample folder (see `Settings.swift`). Release builds show a message asking you to choose a folder.
- **Reinstalling may show the old version.** macOS keeps running the screensaver host after you install a new build. Run `killall legacyScreenSaver` (and close System Settings) before testing a new build.
- **Where settings are stored.** The screensaver runs in Apple's sandboxed `legacyScreenSaver` host, so settings are saved in `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/`.
