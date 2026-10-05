# Metal Alarm Clock

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
