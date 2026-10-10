# Tastko

A floating accessibility keyboard for macOS. Type into other apps without taking focus, use custom Panel Editor layouts, and get word suggestions from macOS or Apple Intelligence.

![Tastko accessibility keyboard with an English layout](docs/images/tastko-keyboard.webp)

## Install

Requires an Apple Silicon Mac running macOS 27 or later.

1. [Download the latest release](https://github.com/davutac/tastko/releases/latest), open the DMG, and drag Tastko into Applications.
2. Open Tastko and allow it in System Settings → Privacy & Security → Accessibility.
3. Open Panel Editor from Tastko's panel menu, save a keyboard, and reload profiles.
4. Select a text field in another app and click the keys to type.

Apple Intelligence suggestions require Apple Intelligence to be enabled and its model downloaded. macOS suggestions work without it.

## Build

Requires Xcode with the macOS 27 SDK or later. Open `Tastko.xcodeproj`, or run from the repository root:

```sh
./script/build_and_run.sh
```

The `Tastko` scheme runs and tests **Debug**; profiling and archiving use **Release**. The project uses the Swift 6 language mode.

To run the unit tests, as CI does on every pull request:

```sh
xcodebuild test -project Tastko.xcodeproj -scheme Tastko -destination 'platform=macOS' -only-testing:TastkoTests
```
The app identities are defined in `Configuration/Debug.xcconfig` and `Configuration/Release.xcconfig`:

| Configuration | App | Bundle ID |
| --- | --- | --- |
| Debug | Tastko Debug.app | `com.davutcaliskan.Tastko.debug` |
| Release | Tastko.app | `com.davutcaliskan.Tastko` |

Enable each app separately in **System Settings → Privacy & Security → Accessibility**, and Input Monitoring if requested. Keep Debug's Apple Development signing identity and app location stable across rebuilds to retain permissions.

Debug has separate preferences and imported sounds, uses no production App Group, and disables Sparkle updates. Both apps read keyboards from macOS Panel Editor.

The script defaults to Debug and stops only the selected app. To build and run Release locally:

```sh
TASTKO_BUILD_CONFIGURATION=Release ./script/build_and_run.sh
```

To build Debug, stop the running Debug app, replace `/Applications/Tastko Debug.app`, and launch the installed copy:

```sh
./script/install_debug.sh
```

The installer stages the build before stopping Debug and verifies launch from `/Applications`. Release stays running.

## Documentation

- [App updates and releases](docs/app-updates.md)
- [Text prediction](docs/text-prediction-performance.md)
- [AI providers and Debug requests](docs/ai-providers.md)
- [Login-window keyboard](docs/login-window-keyboard.md)
- [Experimental lock-screen keyboard](docs/lock-screen-display.md)
- [Design system](docs/design-system.md)

Keyboard sounds from [tplai/kbsim](https://github.com/tplai/kbsim), used under the [MIT license](Tastko/Resources/KeyboardSounds/LICENSE-kbsim.txt).
