# workNrelax

Personal native macOS break-reminder app. It lives in the menu bar, supports repeating and fixed-time reminders, and displays a full-screen break screen.

## Download

No build tools needed — grab a ready-made app from the [Releases page](https://github.com/Royr9/WorknRelax/releases):

1. Download `workNrelax.zip` from the latest release and unzip it.
2. Drag `workNrelax.app` into `/Applications`.
3. On first launch, macOS may show a security prompt because the app is not notarized. Right-click the app and choose **Open**, or go to System Settings → Privacy & Security → **Open Anyway**. This is only needed once.

To cut a new release, run `./scripts/release.sh` (auto-increments the patch version, e.g. `v0.1.0` → `v0.1.1`). Pass `minor`, `major`, or an explicit version like `0.2.0` to change the bump. This pushes a `v<version>` tag, and GitHub Actions builds the app and publishes the release automatically.

## Requirements (building from source)

- macOS 14 or newer
- Swift 6 or Xcode

## Run

Build and launch as a proper macOS app bundle. This is required so macOS registers the menu-bar item reliably:

```bash
./scripts/build-app.sh
open dist/workNrelax.app
```

Opening `Package.swift` in Xcode works too, but run it as the packaged app for normal daily use.

## Use

Open the menu-bar icon, choose **Settings**, and add reminders. A reminder can repeat at an interval or run at a chosen time on selected weekdays. Every reminder has its own message and break duration.

When a reminder fires, workNrelax shows a full-screen countdown. Select **Dismiss** to end the break early. If the Mac locks or sleeps, the app calculates remaining time from the saved end date when it wakes, rather than pausing the break timer.

## Test

Full unit-test execution requires Xcode because the active Command Line Tools Swift runtime does not include XCTest or Swift Testing. The included test scenarios cover persistence, schedule calculation, disabled reminders, and sleep-safe break timing.

```bash
swift test
```

## MVP Limits

- Data is stored locally in macOS `UserDefaults`.
- No account, sync, backend, snooze, history, or forced break mode.
- `dist/` contains build output and is not source.
