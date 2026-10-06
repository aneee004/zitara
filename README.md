# Zitara

A sitar you play with your fingertips. Zitara is a monophonic, sitar-style lead
instrument for iPad, built for classical-fusion players: a LinnStrument-style
grid tuned in fourths, continuous pitch slides (meend), hammer-ons and
pull-offs, and a physically modelled string with a buzzing jawari bridge and
sympathetic strings that retune to the selected raga.

No samples, no third-party dependencies — AVAudioEngine plus custom C++ DSP.

## Features

- **Fourths grid.** Bottom-left is E2; each row is a "string" a fourth above
  the last. Sa (the root) is brass with its octave marked, in-scale notes are
  ivory, everything else recedes.
- **Meend.** Slide sideways to bend pitch continuously. Every cell sharing the
  sounding pitch lights up, so you can see where else the phrase can go.
- **Hammer-ons and pull-offs.** A second finger on the same row changes the
  note without re-plucking; lift it to fall back to the finger still down.
- **Sustain and vibrato.** Hold the ring to keep a note ringing; wobble your
  thumb on it for vibrato (sideways sets rate, distance sets depth).
- **Tone pad.** X = brightness, Y = jawari buzz, ridden live with the other hand.
- **Apple Pencil.** Touch-down pressure sets the pluck; pressure while held
  swells or fades the note.
- **Raga-aware sound.** Seven sympathetic (taraf) strings retune to the chosen
  scale and root, so the scale shapes the sound, not just the colours.
  Scales are listed by raga name first (Mohanam, Shankarabharanam, Kharaharapriya…).
- **Shape faders.** Decay, Glide, Taraf and Room. Double-tap any fader to reset.
- **Live readout.** Note, octave and a ±50¢ meter for landing bends in tune.
- Portrait and landscape, every iPad size from mini to 13". Settings persist
  between launches.

## Requirements

- iPad running iPadOS 16 or later (developed on iPad Pro 12.9" M2).
- Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Build and run

The Xcode project is generated from `project.yml` — edit that, not the
`.xcodeproj`, and regenerate after changes (including adding or removing files).

```bash
brew install xcodegen        # once
xcodegen                     # generates Zitara.xcodeproj
open Zitara.xcodeproj
```

**Signing:** select the Zitara target → Signing & Capabilities → enable
automatic signing and pick your team. A free Apple ID works for running on your
own iPad (the signature expires after 7 days; press Run again to refresh).
Change `bundleIdPrefix` in `project.yml` to something unique to you.

**Compile check without a device:**

```bash
xcodebuild -project Zitara.xcodeproj -scheme Zitara \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

### First run on an iPad

1. On the iPad: **Settings → Privacy & Security → Developer Mode → On** (reboots).
2. Connect via USB-C, unlock, tap **Trust**.
3. Choose the iPad as the run destination in Xcode and press **Run**.
4. The first launch is blocked until you trust your certificate:
   **Settings → General → VPN & Device Management**. Run again.

> Judge audio on the device. The Simulator doesn't honour the app's 5 ms audio
> buffer and shares your Mac's CPU, so it can crackle where the iPad won't.

## Project layout

```
Sources/
  App/        ZitaraApp, ContentView (portrait/landscape + compact layouts)
  UI/         Grid surface (UIKit, raw touches), touch feedback, control panel,
              sustain button, tone pad, faders, root keyboard, scale menu,
              pitch readout, help overlay, Theme (palette + type)
  Model/      AppState (single source of truth, persistence), scales and grid
              layout, pitch readout state
  Audio/
    AudioEngine.swift   AVAudioEngine graph, session handling and recovery
    Bridge/             Obj-C++ wrapper exposing the synth to Swift
    DSP/                SitarSynth (Karplus-Strong string, jawari, taraf,
                        room reverb) and DelayLine
  PrivacyInfo.xcprivacy
project.yml   XcodeGen spec (targets, Info.plist keys, orientations)
CLAUDE.md     Full spec, architecture and real-time rules
```

## Architecture in one line

```
Touch / UI (main thread)  →  std::atomic params  →  C++ render (audio thread)
```

The grid emits a small stream of note events — note on, slide, legato
(hammer-on / pull-off), pressure, note off — which the audio engine forwards to
the synth as atomic writes. The render thread never locks, allocates, logs or
calls into Swift. See **Real-time safety rules** in `CLAUDE.md` before touching
anything under `Sources/Audio/`.

## Roadmap

- **v1.x:** scale-aware slide snap, tanpura drone (Sa–Pa), presets.
- **v2:** MIDI/MPE output, polyphony, microtonal tunings (22-shruti, custom
  cents), recording/export, AUv3 plugin.

App Store release is in preparation (paid developer account, final bundle ID
and store listing still to do).

## Working on it with Claude Code

`CLAUDE.md` holds the spec, design decisions and real-time rules, and is picked
up automatically:

```bash
cd Zitara
claude
```
