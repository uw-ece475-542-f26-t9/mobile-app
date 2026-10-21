# Team 9 Mobile App — Fatigue Coach

Authors: Milo Ridenour, Bernardo Lin, Adi Bhagwani, James Lee  
ECE 475/542 Team 9

A Flutter app for our bicep-curl fatigue wearable (ESP32 + EMG + IMU). It
connects to the wearable over Bluetooth Low Energy (BLE), counts reps live,
shows fatigue and reps left, and keeps a history of your sets.

**Contents**

- [What the app does](#what-the-app-does)
- [Setup](#setup)
  - [1. Install the basics](#1-install-the-basics)
  - [2. Clone the repo](#2-clone-the-repo)
  - [3. Install Flutter and Java with mise](#3-install-flutter-and-java-with-mise)
  - [4. Get the packages and check your setup](#4-get-the-packages-and-check-your-setup)
  - [5. Optional: Android and iOS toolchains](#5-optional-android-and-ios-toolchains)
- [Running the app](#running-the-app)
- [Connecting to the wearable](#connecting-to-the-wearable)
- [Project layout](#project-layout)
- [Before you push: format, analyze, test](#before-you-push-format-analyze-test)
- [Git workflow](#git-workflow)
- [Troubleshooting](#troubleshooting)

---

## What the app does

The app has four parts:

1. **Splash screen.** An animated intro that plays when the app opens.
2. **Connect page.** Tap **Connect** to search for the wearable. Only devices
   advertising our firmware's BLE service are listed, so other Bluetooth
   devices nearby don't show up. Once connected, the card turns green and shows
   live sensor data. **No hardware? Try the demo wearable** simulates a set,
   so you can work on the UI without the ESP32.
3. **Home, Workout and History tabs.**
   - **Home** shows device status, a **Start a set** shortcut, this week's
     activity, and your most recent sets.
   - **Workout** runs a set: live rep count, a fatigue ring, reps left, an
     arm-motion graph, and a banner that turns amber, then red, as you near
     the end of the set. A set can't start unless a wearable is connected.
   - **History** lists every saved set with its reps, duration and peak
     fatigue.
4. **Connection chip.** The chip in the top-right corner shows whether the
   wearable is connected. Tap it to reconnect or disconnect.

> **Note:** the current firmware only streams IMU data. Rep counting works
> with the real device, but **fatigue % and reps left only appear with the
> demo wearable** until the firmware also sends the model's output. See
> [Connecting to the wearable](#connecting-to-the-wearable).

---

## Setup

The Flutter and Java versions are pinned in [`mise.toml`](mise.toml):
**Flutter 3.47** and **Java 17**. We use [mise](https://mise.jdx.dev) to
install exactly those versions, so everyone builds with the same toolchain.
You do **not** need a separate Flutter install.

### 1. Install the basics

| Tool | macOS | Windows | Linux |
|---|---|---|---|
| Git | `xcode-select --install` | [git-scm.com](https://git-scm.com/download/win) | `sudo apt install git` |
| mise | `curl https://mise.run \| sh` | `winget install jdx.mise` | `curl https://mise.run \| sh` |
| Google Chrome | [google.com/chrome](https://www.google.com/chrome/) | same | same |

Chrome is the quickest way to run the app (see
[Running the app](#running-the-app)). An editor with Flutter support helps:
[VS Code](https://code.visualstudio.com/) with the **Flutter** extension, or
Android Studio with the **Flutter** plugin.

> **macOS + Homebrew:** `brew install mise` fails if your Command Line Tools
> are out of date ("Your Command Line Tools are too outdated"). Use the
> `curl https://mise.run | sh` installer above instead; it downloads a
> prebuilt binary.

Next, **hook mise into your shell** so `flutter` and `java` are on your PATH
whenever you're inside the project folder.

macOS (zsh, the default):

```bash
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
```

Linux (bash):

```bash
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
```

Windows (PowerShell): add this line to your `$PROFILE`:

```powershell
(&mise activate pwsh) | Out-String | Invoke-Expression
```

Then **open a new terminal** so the change takes effect.

### 2. Clone the repo

```bash
git clone https://github.com/uw-ece475-542-f26-t9/mobile-app.git
```

```bash
cd mobile-app
```

### 3. Install Flutter and Java with mise

From inside `mobile-app`:

```bash
mise trust
```

```bash
mise install
```

`mise trust` tells mise it's OK to read this repo's `mise.toml`.
`mise install` downloads Flutter and Java 17. The Flutter download is about
2 GB, so the first install takes a few minutes.

Check that it worked:

```bash
flutter --version
```

You should see `Flutter 3.47.x` and `Dart 3.13.x`. If you get
`command not found`, your shell isn't activating mise yet. Open a new terminal
and make sure you're inside the `mobile-app` folder.

Optionally, turn off Flutter's usage analytics:

```bash
flutter --disable-analytics
```

### 4. Get the packages and check your setup

```bash
flutter pub get
```

```bash
flutter doctor
```

`flutter doctor` lists what is and isn't set up. **You only need the
`Flutter` and `Chrome` lines to be green** to run the app in a browser and
work on the UI. Red lines for Android or Xcode only matter if you want to run
on a phone (next step).

### 5. Optional: Android and iOS toolchains

To test with the **real wearable**, you need to run the app on a phone (or in
Chrome with Web Bluetooth; see [below](#connecting-to-the-wearable)).

**Android (any OS)**

1. Install [Android Studio](https://developer.android.com/studio).
2. Open it, go to **Settings → Languages & Frameworks → Android SDK**, and
   install the latest **SDK Platform** plus, on the **SDK Tools** tab,
   **Android SDK Command-line Tools** and **Android SDK Platform-Tools**.
3. Accept the licenses:

   ```bash
   flutter doctor --android-licenses
   ```

4. On your phone, turn on **Developer options → USB debugging**, plug it in,
   and accept the prompt on the phone. Confirm Flutter sees it:

   ```bash
   flutter devices
   ```

Java 17 for the Android build comes from mise, so you don't need to install
it separately.

**iOS / macOS (Mac only)**

1. Install **Xcode** from the Mac App Store and open it once so it can finish
   installing its components.
2. Point the command-line tools at it and accept the license:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

   ```bash
   sudo xcodebuild -license accept
   ```

3. Install CocoaPods:

   ```bash
   brew install cocoapods
   ```

4. To run on an iPhone, open `ios/Runner.xcworkspace` in Xcode, select the
   **Runner** target → **Signing & Capabilities**, and choose your Apple ID
   team. A free personal team is enough for running on your own phone.

Run `flutter doctor` again until the platforms you care about are green.

---

## Running the app

**In Chrome (fastest; good for UI work):**

```bash
flutter run -d chrome
```

While it's running, press `r` in the terminal to **hot reload** after saving
a file, `R` to restart the app, and `q` to quit. Use **No hardware? Try the
demo wearable** on the Connect page to see the full flow without the ESP32.

**On an Android phone or iPhone:**

```bash
flutter devices
```

```bash
flutter run -d <device-id>
```

**As a macOS desktop app** (needs Xcode):

```bash
flutter run -d macos
```

---

## Connecting to the wearable

The ESP32 firmware (`esp32_imu_ble.ino`, kept by the hardware side of the
team) advertises as **`ESP32-IMU`** with this BLE layout:

| | UUID |
|---|---|
| Service | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| IMU characteristic (notify) | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |

It sends a 16-byte little-endian packet every 20 ms (50 Hz):

| Bytes | Type | Field | Units |
|---|---|---|---|
| 0–3 | uint32 | timestamp | ms since boot |
| 4–9 | int16 ×3 | ax, ay, az | milli-g (1000 = 1 g) |
| 10–15 | int16 ×3 | gx, gy, gz | 0.1 °/s (10 = 1 °/s) |

These constants live in
[`lib/wearable/protocol.dart`](lib/wearable/protocol.dart). **If you change
the UUIDs or packet format in the firmware, change them there too.** The
tests in `test/wearable_test.dart` check the packet decoding.

To connect:

1. Flash the sketch to the ESP32 and power it on. With `USE_FAKE_DATA 1` it
   streams sine waves, so you can test without an IMU wired up.
2. In the app, tap **Connect**. Devices running our firmware appear under
   **Nearby wearables**; tap **Connect** next to one.
3. The status card turns green and **Sensor check** shows about 50
   packets/s.

Things to know:

- **Only one phone can be connected at a time.** If the wearable doesn't
  show up, make sure no one else's phone is connected to it.
- **Every team using the class tutorial firmware has the same name and
  UUIDs.** If you see several `ESP32-IMU` devices, pick the one with the
  strongest signal (closest to you), or rename yours in the sketch's
  `DEVICE_NAME`.
- **Phones:** the app asks for Bluetooth permission the first time you tap
  Connect. The permissions are already set up in `AndroidManifest.xml`,
  `Info.plist` and the macOS entitlements.
- **Chrome:** Web Bluetooth works in desktop Chrome on macOS and Windows.
  Tapping Connect opens Chrome's own device picker. It doesn't work in Safari
  or Firefox.
- **Fatigue and reps left:** the app is ready to display them
  (`FatigueEstimate` in `protocol.dart`), but the firmware doesn't send them
  yet. Once the on-board model is running, it needs another characteristic for
  its output, and `WearableController` needs to subscribe to it.

---

## Project layout

```
lib/
├── main.dart                   App entry, theme, navigation (splash → connect → home tabs)
├── screens/
│   ├── splash_screen.dart      Animated intro
│   ├── connect_screen.dart     Scan / connect / disconnect, live sensor check
│   ├── home_screen.dart        Dashboard: device, start a set, weekly activity, recent sets
│   ├── workout_screen.dart     Live set: reps, fatigue ring, advice banner, motion graph
│   └── history_screen.dart     All saved sets with stats and a reps chart
├── wearable/
│   ├── protocol.dart           BLE UUIDs and packet decoding (keep in sync with firmware)
│   ├── wearable_controller.dart  BLE scanning/connection via flutter_blue_plus
│   └── demo_wearable.dart      Simulated wearable for development without hardware
├── workout/
│   ├── rep_counter.dart        Counts curls from the forearm gyroscope
│   ├── workout_controller.dart Set state, fatigue advice, haptics
│   └── history_store.dart      Saves sets on the device (shared_preferences)
└── widgets/
    ├── charts.dart             Fatigue ring, motion line, bar charts
    └── tiles.dart              Stat tile and set row shared by Home and History
test/
├── wearable_test.dart          Packet decoding and rep counting
└── widget_test.dart            End-to-end UI flow using the demo wearable
```

Packages we use:
[`flutter_blue_plus`](https://pub.dev/packages/flutter_blue_plus) for BLE
(free under its license for educational use), and
[`shared_preferences`](https://pub.dev/packages/shared_preferences) for saving
history.

---

## Before you push: format, analyze, test

Run these three and make sure they're clean:

```bash
dart format lib test
```

```bash
flutter analyze
```

```bash
flutter test
```

`flutter analyze` should report **No issues found!** and `flutter test`
should end with **All tests passed!**

---

## Git workflow

1. Get the latest `main`:

   ```bash
   git checkout main
   ```

   ```bash
   git pull
   ```

2. Make a branch for your work:

   ```bash
   git checkout -b yourname/short-description
   ```

3. Commit as you go, then push your branch:

   ```bash
   git push -u origin yourname/short-description
   ```

4. Open a pull request into `main` on GitHub and ask a teammate to look at it.

Don't commit `build/`, `.dart_tool/` or other generated folders; `.gitignore`
already excludes them. `.gitattributes` marks images and fonts as binary, so
Git never changes their bytes. Keep it that way when adding new asset types.

---

## Troubleshooting

**`flutter: command not found`**  
mise isn't active in this shell. Check that the `mise activate` line is in
your shell config, open a new terminal, and `cd` into `mobile-app`. Running
`mise doctor` shows what's wrong.

**`mise install` says the config isn't trusted**  
Run `mise trust` inside the repo, then `mise install` again.

**Homebrew: "Your Command Line Tools are too outdated"**  
Install mise with `curl https://mise.run | sh` instead of Homebrew. To fix
Homebrew itself, update the tools with `softwareupdate --list` and install
the Command Line Tools update it lists (or update Xcode).

**`flutter doctor`: "Unable to locate Android SDK"**  
Install Android Studio and the SDK (see
[step 5](#5-optional-android-and-ios-toolchains)). You only need this to run
on Android.

**`flutter doctor`: "Xcode installation is incomplete" / "CocoaPods not installed"**  
Install the full Xcode app and CocoaPods (see step 5). You only need these
for iOS and macOS builds.

**The wearable never appears when scanning**  
Check that it's powered on and advertising (the serial monitor prints
`Advertising as ESP32-IMU`), that Bluetooth is on, and that no other phone is
connected to it. Tap **Connect** again; each scan lasts 8 seconds.

**"This device is not running the Team 9 firmware."**  
It connected, but the service or characteristic UUIDs don't match. Compare
the sketch's `#define`s with `lib/wearable/protocol.dart`.

**Weird `git status`: every image shows as modified**  
You're on an old checkout from before the `.gitattributes` fix. Pull `main`;
if it persists, run `git add --renormalize .` and check `git status` again.
