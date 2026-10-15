# Zitara — Project Context for Claude Code

## What this app is

A monophonic, sitar-style digital lead instrument for iPad (classical fusion).
The player performs on a LinnStrument-style grid (rows offset in fourths) with
continuous pitch slides (meend/gamaka) between cells, and rides timbre live
with an XY modulation pad. Long-term goal: App Store release marketed to
musicians / multi-instrumentalists.

## Target & constraints

- Device: iPad Pro 12.9" 6th gen (M2). Deployment target: iPadOS 16.0. iPad only, portrait + landscape (layout adapts; see `ContentView`).
- Signing: FREE Apple ID provisioning. Do NOT add entitlements that require a
  paid account (iCloud, push, App Groups, etc.). 7-day signing expiry is expected.
- No third-party dependencies. Raw AVAudioEngine + custom C++ DSP by design.

## Architecture (do not casually restructure)

Touch/UI (main thread)  ->  atomics in SynthParams  ->  C++ render (RT thread)

- `Sources/UI/GridSurfaceView.swift` — UIKit playing surface. Raw UITouch
  handling for latency. Monophonic, LAST-NOTE PRIORITY (new touch steals voice)
  over a stack of held fingers: a new touch on the SAME row as the sounding
  note is a hammer-on (no re-pluck); lifting the sounding finger pulls off to
  the most recent finger still down. Attack is pitch-quantized to the cell;
  horizontal slides are continuous (row locked at touch-down). Emits closures:
  onNoteOn(midiDouble, velocity), onSlide(midiDouble),
  onLegato(midiDouble, LegatoKind, velocity), onPressure(0...1), onNoteOff().
  Apple Pencil pressure sets pluck velocity and live per-note dynamics
  (`expression` in SynthParams); fingers always report pressure 1.
- `Sources/Audio/AudioEngine.swift` — AVAudioEngine + AVAudioSourceNode (mono,
  Float32, hardware sample rate, ~5 ms IO buffer). Forwards events to the bridge.
  Recovers from interruptions, route/config changes (re-prepares the synth at
  the new rate) and media-services resets; reports failures via `onFailure`.
- `Sources/Audio/Bridge/` — Obj-C++ wrapper (`SitarSynthBridge`) exposed to
  Swift via bridging header. Setters write atomics only; render is RT-only.
- `Sources/Audio/DSP/SitarSynth.{hpp,cpp}` — the instrument:
  - Extended Karplus-Strong string, fractional delay for continuous pitch,
    ~4 ms portamento smoothing (`glideCoef`).
  - "Jawari" bridge nonlinearity (tanh-based, small-signal-gain compensated —
    see `jawari()` — keep loop gain <= 1 for stability).
  - 7 sympathetic string resonators, retuned by the UI to the selected scale
    (`AppState.retuneSympatheticStrings`). This is a signature feature: the
    selected scale shapes the SOUND, not just the visuals.
- `Sources/Model/` — scales (Hindustani / Carnatic / Western names, shown in
  that order; `Scale.name` is the persisted identity — never rename one), fourths grid
  layout (row 0 = bottom, `midi = base + row*5 + col`), scale coloring,
  `AppState` (ObservableObject, owns AudioEngine; persists scale/root/tone/
  faders to UserDefaults on backgrounding, plus the first-launch help flag).
- Layout: `ContentView` picks portrait bar / landscape column, and a compact
  variant for every iPad smaller than 12.9"/13" (faders collapse into a
  "Shape" popover). Check new chrome on the iPad mini simulator.
- `Sources/PrivacyInfo.xcprivacy` — declares UserDefaults (CA92.1), no
  tracking, no data collected. Update it if you add required-reason APIs.

## Real-time safety rules (NON-NEGOTIABLE)

On the audio render thread (`SitarSynth::render`, everything it calls):
- NO locks, NO heap allocation, NO Objective-C messaging beyond the single
  bridge render call, NO Swift runtime calls, NO logging, NO file I/O.
- UI -> audio communication is ONLY via `std::atomic` in `SynthParams`
  (relaxed ordering is fine — values are independent). Note triggering uses
  the `pluckCount` / `legatoCount` increment-and-detect pattern.
- `DelayLine::resize()/clear()` only before engine start.
- UI params arrive once per block; anything that shapes the sound
  continuously must be smoothed per sample (see `paramCoef`) or it clicks.
- Exactly ONE AVAudioSourceNode may render the synth: `buildAndStart()`
  detaches the previous node before attaching a new one.
- If a feature needs richer messaging (e.g., polyphony events), introduce a
  lock-free SPSC ring buffer — never a mutex.

## Design decisions already made (don't relitigate without asking the user)

- Synth-first; MIDI/MPE OUTPUT comes later (v2) — architecture keeps note
  events as an internal stream so MPE becomes a second consumer.
- Monophonic solo instrument in v1. Polyphony is v2+.
- XY pad v1 mapping: X = brightness (damping), Y = jawari buzz intensity.
  Keep parameters generic so remapping stays cheap.
- Continuous pitch slides in v1; microtonal TUNING SYSTEMS (22-shruti, n-EDO,
  custom cents) are a later feature.
- Grid: base E2 (MIDI 40), fourths. Note names in cell corners.
- Visual theme "rosewood" (see `Sources/UI/Theme.swift`): minimal, royal,
  crafted-instrument feel. Dark wood ground; root (Sa) = brass, in-scale =
  ivory, out-of-scale = near-invisible; garnet reserved for vibrato only.
  Serif type. No idle glows/particles — light appears only where touched.

## Build & run

```bash
brew install xcodegen   # once
xcodegen                # regenerate Zitara.xcodeproj after project.yml changes
open Zitara.xcodeproj
```

- In Xcode: target Zitara -> Signing & Capabilities -> set your personal
  team (free Apple ID), change bundleIdPrefix in project.yml if collisions.
- iPad: Settings -> Privacy & Security -> Developer Mode ON; trust the Mac;
  first run requires trusting the developer cert in Settings -> General ->
  VPN & Device Management.
- CLI build check: `xcodebuild -project Zitara.xcodeproj -scheme Zitara -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
  (useful for compile-error iteration without a device attached).

## Roadmap

v1 (current): grid + slides + scale highlighting + XY pad + sitar DSP — playable.
v1.x polish: velocity feel, slide snap option, visual touch feedback on cells,
  drone (tanpura-style sa-pa), preset save.
v2: polyphony, MPE/MIDI out, custom tunings (cents/shruti), recording/export,
  AUv3 plugin target, App Store prep (paid dev account needed then).

## Conventions

- Swift 5, SwiftUI for chrome, UIKit only where latency demands it.
- C++17, headers-as-modules style under `Sources/Audio/DSP/`.
- Keep files small and single-purpose. Comment WHY, not what.
- When changing DSP, describe the audible intent in the commit message
  (e.g., "soften jawari knee — less harsh at high buzz").
