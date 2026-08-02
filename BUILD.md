# Build & Run

This is a small hand-rolled monorepo (no melos) — five independent pub packages that happen
to live in one git repo and reference each other via `path:` dependencies. See the main
[README](README.md) for what each one does; this document just covers getting them running.

## Prerequisites

- **Flutter SDK** — this project was built against Flutter 3.38.5 (stable channel), which
  bundles Dart 3.10.4. Run `flutter --version` to check yours; anything reasonably close
  should work.
- **Platform toolchains**, only for the platforms you actually target:
  - **macOS/iOS** (Printer app on macOS; Client app on iOS/macOS): Xcode, plus
    [CocoaPods](https://guides.cocoapods.org/using/getting-started.html#installation)
    (`brew install cocoapods` or `sudo gem install cocoapods`). Flutter plugins (this project
    uses [`bonsoir`](https://pub.dev/packages/bonsoir) for mDNS) won't build without it.
  - **Android** (Client app): Android SDK via Android Studio. `flutter create` may warn about
    Java/AGP version compatibility the first time you build — see
    [Troubleshooting](#troubleshooting) below.
  - **Linux desktop** (Printer or Client app): `clang`, `cmake`, `ninja-build`, `pkg-config`,
    `libgtk-3-dev` — see Flutter's
    [Linux desktop docs](https://docs.flutter.dev/platform-integration/linux/building).
  - **Windows desktop**: Visual Studio with the "Desktop development with C++" workload.

Run `flutter doctor` to confirm your machine is ready for whichever targets you plan to use.

## Repository layout

```
packages/ipp         pure Dart      — IPP wire codec + HTTP transport
packages/fwupdate     pure Dart      — FWUPDATE vocabulary (depends on ipp)
packages/discovery    Flutter package — bonsoir mDNS wrapper
apps/printer          Flutter app    — depends on ipp, fwupdate, discovery
apps/client           Flutter app    — depends on ipp, fwupdate, discovery;
                                        also depends on apps/printer as a
                                        dev-only (test-time) dependency
```

Because the apps reference the packages via `path:` dependencies, editing a package takes
effect immediately in both apps — no publishing or version bumping needed. You do still need
to fetch each package's own dependencies before working in it, though.

## Bootstrap

From the repo root, fetch dependencies for every package/app:

```bash
(cd packages/ipp && dart pub get)
(cd packages/fwupdate && dart pub get)
(cd packages/discovery && flutter pub get)
(cd apps/printer && flutter pub get)
(cd apps/client && flutter pub get)
```

Order doesn't matter for correctness — `path:` dependencies resolve against the filesystem,
not a build graph — this is just fetch-everything-once.

## Running the apps

```bash
# Printer app — desktop only (see README's Architecture section for why)
cd apps/printer
flutter devices            # confirm a desktop target is available
flutter run -d macos       # or -d linux / -d windows

# Client app — mobile-first, desktop also supported
cd apps/client
flutter devices
flutter run -d <device-id>
```

The Printer app binds to an ephemeral port and shows its `ipp://host:port` on its Home tab.
The Client app finds it automatically via mDNS on the same LAN/Wi-Fi, or you can use its
"Connect manually" button to type in `host:port` directly — useful if mDNS is blocked on your
network, or before you've approved macOS's "Local Network" permission prompt.

## Building release artifacts

```bash
# Printer app
cd apps/printer
flutter build macos      # -> build/macos/Build/Products/Release/fwupdate_printer.app
flutter build linux      # -> build/linux/x64/release/bundle/
flutter build windows    # -> build/windows/x64/runner/Release/

# Client app
cd apps/client
flutter build apk        # -> build/app/outputs/flutter-apk/app-release.apk
flutter build ios        # requires a signing Team configured in Xcode first
flutter build macos / linux / windows   # if you also want a desktop Client build
```

## Testing

```bash
(cd packages/ipp && dart test)
(cd packages/fwupdate && dart test)
(cd apps/printer && flutter test)
(cd apps/client && flutter test)
```

All 32 tests currently pass across the four suites (6 + 6 + 15 + 5). `apps/printer`'s suite
includes a real end-to-end loopback test (a real `IppServer` talked to over real HTTP);
`apps/client`'s suite drives a real `PrinterEngine` from the Printer app the same way.

## Troubleshooting

- **`flutter build ios` fails**: it needs a valid Apple Developer signing configuration —
  open `apps/client/ios/Runner.xcworkspace` in Xcode and set a Team under *Signing &
  Capabilities*, then retry from the command line.
- **Android Java/AGP version warning**: either point Flutter at a compatible JDK
  (`flutter config --jdk-dir=<path>`) or bump the AGP version in
  `apps/client/android/build.gradle` per the message Flutter prints.
- **CocoaPods not installed**: `flutter build macos`/`ios` will stop with "CocoaPods not
  installed or not in valid state." Install it (see Prerequisites above) and re-run; this is
  also why this project's own development environment could only verify the Printer/Client
  apps via `flutter analyze` and the test suites above, not a full desktop build.
