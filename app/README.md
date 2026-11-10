# Siber Neo for macOS

Technical documentation for building, releasing, and understanding the Siber Neo app.

Siber Neo is an interactive notch app for macOS. The notch area at the top of the MacBook screen becomes a compact panel for music, lyrics, a focus timer, to-dos, agenda, a file shelf, clipboard history, prayer times, and privacy and network security monitoring. The panel opens when the cursor moves to the notch and closes automatically when it moves away.

Built natively with Swift, SwiftUI, and AppKit. No web engine, no account, no analytics.

## Requirements

- Mac with Apple silicon
- macOS 14 Sonoma or later
- Xcode or Command Line Tools (Swift 5.9+)
- A MacBook with a notch is recommended. On Macs without a notch, the app shows a virtual notch at the center of the menu bar.

Install the Command Line Tools if needed:

```bash
xcode-select --install
```

## Build and Install

From this folder:

```bash
chmod +x build.sh
./build.sh --install
```

This compiles the app, assembles the `Siber Neo.app` bundle, installs it to the Applications folder, and launches it.

To build without installing:

```bash
./build.sh
open "build/Siber Neo.app"
```

## DMG Installer

To create a distributable installer:

```bash
./build.sh --dmg
```

The result is `build/Siber-Neo-<version>.dmg`. Users open it and drag Siber Neo into the Applications folder.

For public distribution without Gatekeeper warnings, use an Apple Developer ID certificate and notarization:

```bash
DEVELOPER_ID="Developer ID Application: PT Siber Shop Teknologi Indonesia (TEAMID)" NOTARY_PROFILE="siber-notary" ./build.sh --dmg
```

`NOTARY_PROFILE` is created once with `xcrun notarytool store-credentials`.

## Releasing a New Version

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Update the feature list in `Sources/SiberNeo/Views/WhatsNewView.swift` (the `ReleaseNotes` section).
3. Build the installer with `./build.sh --dmg`.
4. Upload the DMG to `https://neo.sibershopstore.com/`.
5. Update `Distribution/latest.json` (version, DMG link, release notes) and upload it to `https://neo.sibershopstore.com/latest.json`.

Once `latest.json` is updated, every user is notified within 12 hours or the next time the app launches.

## Permissions

| Permission | Purpose |
|---|---|
| Automation (Spotify / Music / Chrome) | Read track or video position and control play, pause, next, and seek |
| Bluetooth | Show AirPods and headphone status |
| Notifications | Reminders for tasks, events, end of focus sessions, and prayer times |
| Calendars | Show events and meeting links (requested when the Agenda tab is opened) |
| Desktop (or screenshot folder) | Watch for new screenshots to add to the Shelf |
| Location (optional) | Required by macOS to read the Wi-Fi name in the Security tab |

Permissions are requested one at a time during onboarding. All of them can be changed in System Settings → Privacy & Security.

Note: local builds use ad-hoc signing. After each rebuild, macOS may ask for Automation permission again. This is expected for apps not signed with an Apple Developer ID.

## Features

**Onboarding with Neo.** On first launch, Neo walks through four short steps: introduction, how to use the app, required permissions (requested one at a time with an explanation), and finishing touches such as Neo's color, city, and launch at login. Onboarding can be reopened from the menu bar.

**Two languages.** The entire interface is available in Indonesian and English and follows the primary macOS language automatically. The language can also be chosen manually from the Bahasa / Language menu.

**Greetings.** Neo greets the user by name based on the time of day when the Mac is opened or wakes from sleep, at most once per part of the day. Special occasions include a message: Ramadan, Eid al-Fitr, Eid al-Adha, Islamic New Year, Mawlid, New Year, Lunar New Year, Christmas, August 17, and Friday.

**Polished interface.** The notch expands with a smooth spring animation, panel content fades in with a soft blur, the tab indicator slides to the selected tab, and tab content moves in the direction of the change. While music plays, the notch glows with the dominant color of the album artwork, and the progress bar and equalizer follow the same color. Album artwork flips like a card when the song changes. When a charger is connected, the notch shows a battery filling slowly with a green glow. Optional, subtle interface sounds can be enabled from the menu.

**Music and lyrics.** Supports Spotify, Apple Music, and YouTube and YouTube Music in Chrome, Brave, Edge, and Arc (title, artist, artwork, progress, controls). For YouTube, enable once in the browser: View → Developer → Allow JavaScript from Apple Events. Synced lyrics come from LRCLIB; click any line to jump to it. While music plays, the closed notch shows the album artwork and a small equalizer.

**Focus timer.** Pomodoro with 4 sessions per cycle, 5-minute short breaks, and a 15-minute long break. Focus durations of 25, 45, or 50 minutes. The remaining time is shown in the notch while the timer runs.

**To-dos with reminders.** Tasks can have a reminder time. When it arrives, the notch shows a brief notification together with a system notification.

**Shelf and clipboard.** Drag files into the notch to hold them, then drag them out to a chat, an email, or another folder. The Shelf stores file locations only, never copies. Clipboard history keeps the last 20 text entries.

**Prayer times.** Calculated on the device using Indonesian Ministry of Religious Affairs parameters (Fajr 20°, Isha 18°, Shafi'i Asr, 2-minute ihtiyat). Includes 21 Indonesian cities, automatic reminders, and an option to pause music at prayer time.

**Neo the mascot.** A tiny robot with a screen for a face and small headphones that appears in the notch when nothing else is happening. Neo blinks, glances around, follows the cursor with its eyes, gets sleepy after 1 minute of inactivity, falls asleep after 2.5 minutes, and greets the user happily on return. Neo reacts to clicks, dances to music, looks tired when the battery drops below 20%, and celebrates every completed focus session. It opens its mouth when a file is dragged onto the notch and "swallows" it into the Shelf, drinks water or sips coffee when logged in the Daily tab, yawns late at night, closes its eyes contentedly when petted (cursor resting on it), and gets dizzy after five quick clicks. Neo dresses for the weather: an umbrella in the rain, sunglasses in bright sun, and a scarf when it is cold. Seasonal accessories include a peci during Ramadan, Eid al-Fitr, and Eid al-Adha, a party hat at New Year, and a red and white ribbon around August 17. During focus sessions, Neo works seriously at a tiny laptop and never falls asleep. At Pomodoro breaks, or after one hour of continuous activity, Neo stretches and invites the user to stretch for 30 seconds. The user's birthday can be set during onboarding or from the menu; on that day Neo wears a party hat, brings a cake, and the notch rains confetti. The mascot's name can be changed and is used throughout the interface. Good habits unlock collectible accessories: glasses (10 focus sessions), a flower (7 days meeting the water goal), a graduation cap (25 focus sessions), and a crown (50 focus sessions), which can be worn from the Security tab. Five colors are available: Navy, Red, Graphite, Frost White, and Violet. Neo can be turned off from the menu bar.

**System overlays.** Volume, display brightness, Caps Lock, and keyboard input source changes appear in the notch with a level bar.

**Privacy indicator.** The notch shows a red dot while the camera is in use and an orange dot while the microphone is in use, along with the name of the app using the microphone. Siber Neo only reads device status from the system and never accesses the camera or microphone.

**Network security.** Automatic alerts when the Mac joins an unencrypted or weakly encrypted (WEP) Wi-Fi network, notifications when a VPN connects or disconnects, and a status summary in the Security tab.

**Agenda.** The next event from the Calendar app (including Google, iCloud, and Exchange accounts already added), a countdown, a join button for Zoom, Google Meet, Teams, and Webex, and a reminder 5 minutes before the event starts.

**Weather.** Temperature and conditions appear compactly at the top of the notch. Click for details: feels-like temperature, humidity, and an hourly forecast with chance of rain. The location follows the city selected for prayer times, so Location permission is not required. Siber Neo also alerts the user when rain is likely within the next 1–2 hours.

**Screenshots to Shelf.** Every new screenshot goes straight to the Shelf with an image preview, ready to drag into a chat, email, or document. Follows the macOS screenshot location and can be turned off from the Shelf tab.

**Daily log.** The Daily tab logs water, coffee, snacks, and cigarettes with a single click, with a 7-day chart. Water has a daily goal and periodic reminders between 08:00 and 21:00 (adjustable from 30 to 120 minutes, or off). Snacks have reminders at 10:00 and 15:00. Coffee and cigarettes have adjustable daily limits with alerts when the limit is reached or exceeded. Data is stored locally for 30 days.

**Smart tabs.** When the notch opens, Siber Neo shows the most relevant tab: Agenda if a meeting starts within 10 minutes or has just started, Focus if a timer is running, Music if a song is playing, or Daily right after a water or snack reminder. Otherwise, the notch opens the last used tab.

**Presentation mode.** Notifications, live view, and notch sounds are hidden automatically when the display is mirrored to a projector or when an app runs full screen, such as a Keynote, PowerPoint, or Google Slides slideshow or full-screen video. It can also be enabled manually with the eye icon at the top of the notch.

**Energy saving mode.** Enabled automatically when Low Power Mode is on or when the battery is below 20% and not charging. Idle animations stop and monitoring frequency is reduced. Can be turned off from the menu.

**Automatic updates.** Siber Neo checks the official site for a new version at launch and every 12 hours. When one is available, the notch shows a notification and a blue download button at the top. Updates can also be checked manually from the menu or skipped for a specific version. Download links are accepted only from `neo.sibershopstore.com` over HTTPS.

**What's New window.** After an update, a short window lists the new features in that version, once. It can be reopened from the menu.

**Device status.** Brief notifications when a charger is connected and when AirPods or Bluetooth headphones connect or disconnect.

## Settings

Click the shield icon in the menu bar to:

- Enable launch at login
- Turn Neo on or off
- Choose Neo's color
- Rename the mascot and set a birthday
- Configure smart tabs and presentation mode
- Choose the language
- Reopen onboarding
- View what's new and check for updates
- Choose the prayer times city
- Configure prayer time reminders
- Configure pausing music at the call to prayer
- Quit the app

## Privacy and Security

- Tasks, Shelf items, and settings are stored locally in `~/Library/Application Support/SiberNeo`.
- Clipboard history is kept in memory only and cleared when the app quits.
- Clipboard entries marked as concealed by password managers (1Password, Bitwarden, and similar apps following the nspasteboard.org convention) are never recorded.
- Browser access is used only to read and control YouTube tabs, not other sites.
- Weather data comes from Open-Meteo using the coordinates of the selected city, not the device location.
- Update checks only download `latest.json` from `neo.sibershopstore.com`, sending no user data other than the app version.
- The only other outbound connections are to LRCLIB (song title, artist, and duration to find lyrics) and Spotify oEmbed (track ID to fetch album artwork).
- Prayer times are calculated entirely offline.
- Calendar events and camera, microphone, and network status are processed only on the device and never sent anywhere.

## Known Limitations

- **Browser players.** Since macOS 15.4, Apple restricts "Now Playing" information for third-party apps. YouTube in Chromium-based browsers is still supported through Allow JavaScript from Apple Events; Safari and other streaming sites are not supported yet.
- **Other apps' notifications.** macOS does not allow third-party apps to read notifications from other apps, so this feature is not available.
- **Built-in macOS overlays.** The built-in macOS volume and brightness indicators still appear alongside the notch display.
- **VPN detection.** VPNs are recognized from tunnel-type network services (IKEv2, WireGuard, OpenVPN, L2TP). Some proxy-based VPNs may not be detected.
- **Full screen.** The notch is hidden automatically while an app runs in full-screen mode.

## Project Structure

```
app/
├── Package.swift
├── build.sh
├── Distribution/
│   └── latest.json
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.png
│   ├── SiberNeo.entitlements
│   ├── en.lproj/
│   └── id.lproj/
└── Sources/SiberNeo/
    ├── App/          entry point, AppDelegate, notch window, state
    ├── Services/     media, lyrics, focus, to-dos, agenda, shelf, clipboard, prayer times, privacy, network, system overlays, mascot
    ├── Support/      local storage, notifications, AppleScript, localization, effects
    └── Views/        SwiftUI views for every mode and tab
```

## Roadmap

- Checking clipboard links for threats via Siber API
- Additional widgets (world clock, countdown)
- Developer ID signing and notarization for public distribution

---

© 2026 PT Siber Shop Teknologi Indonesia
