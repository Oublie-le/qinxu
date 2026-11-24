# Project working instructions

- This repository is a native SwiftUI piano practice app for iPad/iPhone. macOS is a shared-code development preview, not a replacement for the iOS goal.
- Read `docs/PLAN.md` and `docs/STATUS.md` before continuing. Keep the implemented scope and real-device verification status distinct.
- Keep score semantics and the deterministic practice state machine in `PianoCore`; UI, Core MIDI and audio-device lifecycle belong in `PianoApp`.
- Use monotonic time for note evaluation. MusicXML time is measured in quarter-note beats. Never silently ignore musical constructs that change evaluated pitch/timing.
- Keep microphone mode explicitly experimental and monophonic until a measured polyphonic implementation exists. Do not promise accuracy from synthetic signal tests.
- Run `swift test` for core changes. With full Xcode available, also build the iOS Simulator scheme. For new app source files run `python3 scripts/generate_project.py`.
- Preserve local user data; unsupported/corrupt stores must keep a recovery copy before writing new data.
- Update `docs/STATUS.md` with actual verification evidence and remaining work. No simulated result or UI placeholder counts as a completed hardware test.
