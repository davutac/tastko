# App

This App is going to be a Accessibility keyboard with Ai features like text prediction. It’s going to use the latest technology to achieve this.

## Project Instructions

- The minimum supported deployment target is macOS 27.
- Prefer the latest available macOS and SwiftUI APIs when implementing features.
- Use the Observation framework (`@Observable`, `@State`, and `@Bindable`) instead of `ObservableObject`, `@Published`, `@StateObject`, or `@ObservedObject`.
- Use `// MARK: - <name>` comments above views and functions.
- Do not use `@available` checks for APIs that are available in macOS 27 or later.
- The project builds in the Swift 6 language mode. Shared Swift settings live in the project-level build configurations; the app target alone defaults to `MainActor` isolation. Keep `script/swift_flags.sh` in sync with them.
- Mark pure value types, math helpers, and their extensions `nonisolated` so tests and background work can use them.
- Mark framework callbacks that run on a background queue `@Sendable`, or they inherit `MainActor` isolation and trap at runtime.
- Use `isolated deinit` when a main-actor class cleans up its state.
