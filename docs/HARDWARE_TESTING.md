# Hardware test checklist

Run on the iPad Pro 12.9" (M2) with a Release build (Edit Scheme → Run →
Build Configuration → Release) — Debug C++ is unoptimised and will glitch
where Release won't. Everything here is what the simulator can't show;
layout, persistence and the music-theory model are already covered by the
simulator pass and `Tests/`.

Mark each: ✅ fine · ⚠️ works but feels off (note how) · ❌ broken.

## 1. Install & first launch
- [ ] Installs with the free Apple ID (bundle `com.aniruth.Zitara`); cert trusted in Settings → General → VPN & Device Management
- [ ] Help overlay appears on first launch, not on the second
- [ ] Sound on the first tap — no silent start

## 2. Latency & feel (the most important section)
- [ ] Tap-to-sound feels immediate; fast repeated plucks on one cell don't smear or drop
- [ ] Compare against a percussive app you trust (e.g. GarageBand drums) — Zitara should feel no slower
- [ ] Meend: slow and fast slides across a full row — pitch follows the finger smoothly, no stepping or zipper noise
- [ ] Slide then hold — pitch settles on the finger, no drift
- [ ] Gamaka: quick back-and-forth wobble between two cells stays clean

## 3. Multi-finger technique
- [ ] Hammer-on: hold a note, add a finger further along the SAME row → pitch changes, no re-pluck
- [ ] Pull-off: lift the sounding finger → falls back to the most recent finger still down
- [ ] New note on a DIFFERENT row re-plucks (last-note priority)
- [ ] Three or four fingers down, lifted in random order — never a stuck note, never silence while a finger is still down
- [ ] Palm / accidental edge touches don't steal the voice in normal playing posture
- [ ] Sustain ring + vibrato thumb wobble while playing with the other hand

## 4. Apple Pencil
- [ ] Light vs hard pluck gives clearly different loudness
- [ ] Holding and pressing harder/softer swells and fades the sustaining note smoothly (no steps)
- [ ] Pencil slides behave like finger slides
- [ ] Fingers still play at full level while the Pencil is in use

## 5. Sound
- [ ] Each scale makes the taraf strings ring differently — compare Bhupali, Yaman, Bhairav, Malkauns on the same root
- [ ] Changing root re-tunes the taraf (listen to the sympathetic shimmer after a note)
- [ ] XY pad at all four corners: no instability, runaway feedback or harsh clipping (max buzz + max brightness especially)
- [ ] Faders swept while a note rings: no clicks
- [ ] Headphones: no hum, DC thump or crackle on silence

## 6. Robustness (audio session)
- [ ] Plug / unplug wired headphones mid-note — audio continues on the new route
- [ ] Connect / disconnect Bluetooth headphones (latency will be worse — expected — but no silence)
- [ ] Trigger Siri mid-play, then dismiss — sound returns
- [ ] Play audio in another app, return to Zitara — sound returns
- [ ] Background the app for >1 min, return — sound returns, settings intact
- [ ] Kill from the app switcher, relaunch — scale/root/tone/faders restored
- [ ] Low Power Mode on — still glitch-free

## 7. Endurance
- [ ] 20+ min continuous playing: no crackles creeping in, no thermal slowdown, battery drain reasonable
- [ ] Xcode → Debug Navigator while playing: CPU steady, memory flat (no growth over time)
- [ ] Rotate repeatedly while a note sustains — no crash, no stuck note

## Notes
Write down anything marked ⚠️/❌ with: what you did, what you heard/saw,
and whether it reproduces.
