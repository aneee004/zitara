# SitarGrid

A monophonic sitar-style grid instrument for iPad. LinnStrument-style fourths
layout, continuous pitch slides (meend), scale-aware sympathetic strings, and a
live XY timbre pad. Physical-modeling synthesis — no samples, no dependencies.

## First-time setup (Mac)

1. **Install XcodeGen** (generates the Xcode project from `project.yml`):
   ```bash
   brew install xcodegen
   ```
2. **Edit `project.yml`** — change `bundleIdPrefix: com.yourname` to something
   unique to you.
3. **Generate and open the project:**
   ```bash
   cd SitarGrid
   xcodegen
   open SitarGrid.xcodeproj
   ```
4. **Signing:** select the SitarGrid target -> Signing & Capabilities ->
   check "Automatically manage signing" -> Team: add your Apple ID
   (Xcode -> Settings -> Accounts -> +). A free Apple ID works.

## First run on the iPad

1. On the iPad: **Settings -> Privacy & Security -> Developer Mode -> On**
   (reboots the iPad).
2. Connect the iPad via USB-C, unlock it, tap **Trust** when prompted.
3. In Xcode, select your iPad as the run destination and press **Run**.
4. First launch will be blocked: on the iPad go to
   **Settings -> General -> VPN & Device Management** and trust your
   developer certificate. Run again.
5. Play. Bottom-left cell is E2; rows ascend in fourths. Slide fingers
   horizontally for meend. Ride the orange ball with your other hand.

> Free-account note: the app's signature expires after 7 days — just press
> Run from Xcode again to refresh it.

## Continuing development with Claude Code

This repo contains a `CLAUDE.md` with the full spec, architecture, and
real-time-safety rules. Install Claude Code and start it in this directory:

```bash
curl -fsSL https://claude.ai/install.sh | bash
cd SitarGrid
claude
```

It will pick up the project context automatically.
