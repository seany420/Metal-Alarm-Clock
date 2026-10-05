# Metal Alarm Clock

Two versions live here: a native iPhone app in `ios/` that rings with the phone locked, and the original web version (`index.html`).

A phone clock with sword and dagger hands, blood oozing off the top of the screen, a hockey mask and a bloody knife flanking the face. The alarm rotates through a metal setlist: every morning plays the next song down the list.

## Use it

1. Open `index.html` on your phone (see "Put it on your phone" below).
2. **The Summoning:** set the time, pick the days, tap **Arm it**.
3. **The Setlist:** tap **Load** on each song and pick the audio file from your phone. Default slots: For Whom the Bell Tolls, Raining Blood, Domination, (sic), Blackened, Blind, Epic, Master of Puppets, Iron Man. Add more with **Add more songs** (files named `Band - Title.mp3` get split automatically).
4. **The Backdrop:** optional picture behind the clock. Any slasher still or album art you've saved works.
5. Before bed, plug in and tap **Nightstand mode**. It keeps the screen awake and hides the controls.

When it goes off: **Snooze** gives 9 minutes. **Hold to kill it** takes a 2-second hold.

No songs loaded? It plays a built-in drop-tuned chug riff with a tolling church bell.

## Put it on your phone

Turn on GitHub Pages: repo **Settings → Pages → Deploy from a branch**, pick this branch and `/ (root)`. Open the URL it gives you on your phone, then:

- **iPhone (Safari):** Share → Add to Home Screen
- **Android (Chrome):** ⋮ → Add to Home screen / Install app

## Limits

- It's a web app, so the page has to be **open and on screen** when the alarm time hits. Phones freeze background tabs. Nightstand mode exists for this.
- Songs aren't included. Load files you own; they stay on your phone (browser storage) and never upload anywhere.
- The hockey mask and knife are generic drawings. Use The Backdrop for actual movie stills.

## Files

- `index.html`: the whole app (clock, alarm, setlist, synth riff)
- `manifest.webmanifest`, `icon.svg`, `sw.js`: home-screen install and offline support

---

# iPhone app (`ios/`)

Same sword-handed clock, same rotating setlist, but it rings with the phone locked. Needs iOS 26 or later.

## How it rings when locked

Two layers:

1. **Full song.** While the alarm is armed, the app quietly holds an audio session open in the background (other music still plays over it). iOS leaves it running, so at alarm time it blasts the whole song, locked or not. Pausing from the lock screen counts as snooze. Killing it takes a 2-second hold inside the app.
2. **Backup iPhone alarm.** In case iOS or you close the app, it also sets real iPhone alarms (Apple's AlarmKit) for the next 6 wake-ups. Those break through silent mode and Focus and play a 30-second clip of the song that's next in the rotation. Tap **Full song** on that alarm and the app opens and plays the whole thing.

When the app is alive it cancels the backup a few seconds early, so you only hear one alarm.

Set where each song's 30-second clip starts in **The Setlist → tap a song → Lock-screen clip**.

## Getting songs onto the phone

Save the MP3/M4A files into the Files app (AirDrop, iCloud Drive, a download), then tap a song in The Setlist and pick its file. Songs bought on iTunes work. Apple Music streaming downloads are DRM-locked and won't load.

## Installing without a Mac

Every push to `ios/` builds the app on GitHub's Mac servers (**Actions → iOS app**). Apple only lets you install apps that are signed to an Apple account, so pick one:

### Option A: TestFlight ($99/year Apple Developer account, no computer needed)

1. Join the Apple Developer Program at developer.apple.com.
2. In App Store Connect, create an app with bundle ID `com.seany420.metalalarm` (or your own; see step 4).
3. App Store Connect → Users and Access → Integrations → **App Store Connect API** → generate a key with **App Manager** access. Download the `.p8` file once.
4. In this GitHub repo: **Settings → Secrets and variables → Actions**
   - Variables: `TEAM_ID` (10 characters, from developer.apple.com → Membership), optionally `BUNDLE_ID`
   - Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (paste the whole `.p8` file)
5. Re-run the **iOS app** workflow. It signs the build and uploads it to TestFlight.
6. Install the TestFlight app on your iPhone and accept the build. Builds last 90 days; push again for a fresh one.

### Option B: Free Apple ID + a Windows or Linux PC (re-sign every 7 days)

1. Download `MetalAlarm-unsigned-ipa` from the latest **iOS app** run under Actions.
2. Install it with Sideloadly (Windows/Mac) or AltStore/SideStore using your Apple ID.
3. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID. Turn on Developer Mode if asked.
4. Free signing expires after 7 days. Re-sideload, or let SideStore refresh it.

## First night checklist

- Open the app, allow **Alarms** and **Notifications** when asked.
- Load at least one song, arm the alarm.
- Tap **Test alarm** (full song, app open), then **Test locked** and lock the phone (backup alarm in 1 minute).
- Volume up. The app warns you if it's under 50%.

## Rebuilding the artwork and sound

- `ios/tools/render-art.cjs` renders the web clock's SVG into the PNG layers in `ios/MetalAlarm/Resources/Art` (needs Playwright).
- `ios/tools/make-riff.py` synthesizes the built-in bell-and-chug alarm.
- Fonts are Metal Mania, UnifrakturMaguntia, and Barlow Condensed, all SIL Open Font License (licenses next to the fonts).
