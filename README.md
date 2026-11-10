<p align="center">
  <img src="app/Resources/AppIcon.png" width="128" height="128" alt="Siber Neo">
</p>

<h1 align="center">Siber Neo</h1>

<p align="center">
  An interactive notch app for macOS by Siber Group.<br>
  <a href="https://neo.sibershopstore.com/en/">neo.sibershopstore.com</a>
</p>

---

Siber Neo turns the MacBook notch into a small hub for music and lyrics, a focus timer, to-dos, agenda, a file Shelf, clipboard history, prayer times, weather, and privacy and network security indicators. The panel opens when the cursor moves to the notch and closes automatically when it moves away, accompanied by Neo, a mascot that reacts to everything happening on the Mac.

Built natively with Swift, SwiftUI, and AppKit. No web engine, no account, no ads, and no tracking analytics.

## Highlights

- **Music and lyrics.** Spotify, Apple Music, and YouTube and YouTube Music in Chrome, Brave, Edge, and Arc, with synced lyrics from LRCLIB.
- **Focus and to-dos.** Pomodoro in 25, 45, or 50 minute blocks with the remaining time in the notch, plus tasks with reminders.
- **Agenda.** The next meeting from the Calendar app, a countdown, and a join button for Zoom, Google Meet, Teams, and Webex.
- **Shelf and clipboard.** A resting place for files and screenshots, and a history of the last 20 clipboard texts.
- **Prayer times and weather.** Calculated on the device with Indonesian Ministry of Religious Affairs parameters for 21 cities, with hourly weather from Open-Meteo.
- **Security.** Camera and microphone indicators, unencrypted Wi-Fi alerts, and VPN status.
- **Neo.** A mascot with five colors, weather outfits, seasonal accessories, and accessories earned through good habits.
- **Automatic updates.** Version checks from `neo.sibershopstore.com/latest.json` over HTTPS.
- **Two languages.** English and Indonesian.

## Requirements

- Mac with Apple silicon (M1 or later)
- macOS 14 Sonoma or later
- Xcode or Command Line Tools (Swift 5.9+) to build from source

## Download

The official installer is available at [neo.sibershopstore.com](https://neo.sibershopstore.com/en/) and in [Releases](https://github.com/sibershopstore/siber-neo/releases).

## Uninstall

Siber Neo runs in the background without a Dock icon, so quit it first: move the cursor to the notch, click the gear icon, and choose Quit (or stop `SiberNeo` in Activity Monitor). Then remove it from System Settings → General → Login Items if listed, and drag Siber Neo from Applications to the Trash.

To remove the app together with its local data, settings, caches, and granted permissions in one step, run this in Terminal:

```bash
osascript -e 'quit app "Siber Neo"' 2>/dev/null; pkill -x SiberNeo 2>/dev/null; defaults delete id.sibergroup.neo 2>/dev/null; rm -rf "/Applications/Siber Neo.app" ~/Library/Application\ Support/SiberNeo ~/Library/Caches/id.sibergroup.neo ~/Library/HTTPStorages/id.sibergroup.neo ~/Library/Preferences/id.sibergroup.neo.plist; tccutil reset All id.sibergroup.neo; echo "Siber Neo removed"
```

## Build from source

```bash
cd app
chmod +x build.sh
./build.sh --install
```

This compiles the app, assembles `Siber Neo.app`, installs it to the Applications folder, and launches it. Other options:

```bash
./build.sh
./build.sh --dmg
```

A plain build produces `build/Siber Neo.app`, while `--dmg` produces the installer `build/Siber-Neo-<version>.dmg`. Developer ID signing and notarization are available through the `DEVELOPER_ID` and `NOTARY_PROFILE` variables. See [`app/README.md`](app/README.md) for the full guide.

## Releasing a new version

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `app/Resources/Info.plist`.
2. Run `./build.sh --dmg`.
3. Update `app/Distribution/latest.json` (version, URL, and release notes), then upload the DMG and `latest.json` to the official site.

## Privacy

Personal data stays on the Mac. The only outbound connections are to LRCLIB for lyrics, Spotify oEmbed for album artwork, Open-Meteo for weather in the selected city, and `neo.sibershopstore.com` for version checks. Full details are in the [Privacy Policy](https://neo.sibershopstore.com/en/privacy/).

## Support development

Siber Neo is free. Voluntary support through [PayPal](https://paypal.me/sibergroupid) helps cover server costs, the Apple developer certificate, and work on upcoming features.

## License

Siber Neo is **source-available**, not open source. The code may be viewed, studied, and built for personal use, but may not be redistributed, sold, or used commercially without written permission. See [LICENSE](LICENSE) for the full terms.

The official installer is available only at [neo.sibershopstore.com](https://neo.sibershopstore.com/en/).

## Contact

PT Siber Shop Teknologi Indonesia
[sibershopstore.com](https://sibershopstore.com), Instagram [@sibergroup.id](https://www.instagram.com/sibergroup.id/), TikTok [@sibershopstore](https://www.tiktok.com/@sibershopstore)

&copy; 2026 PT Siber Shop Teknologi Indonesia. All rights reserved.
