// Renders a lock-screen wallpaper (no hands; the iPhone's own clock shows the time on top).
// Usage: NODE_PATH=$(npm root -g) node ios/tools/render-wallpaper.cjs out.png
const path = require('path');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
const fonts = path.join(root, 'ios/MetalAlarm/Resources/Fonts');

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 3 });
  await p.goto('file://' + path.join(root, 'index.html'));
  await p.addStyleTag({ content: `
    @font-face { font-family: Cinzel; font-weight: 700; src: url("file://${fonts}/Cinzel.ttf"); }
    header, .readout, .actions, .panel, #night-exit, .lock-note, #hand-hour, #hand-min, #hand-sec { display: none !important; }
    .wrap { padding-block: 0 !important; height: 100%; justify-content: flex-start; }
    .stage { margin-top: 340px !important; width: 100% !important; }
    .drip, .drip i { animation-play-state: paused !important; }
  `});
  await p.evaluate(() => document.fonts.load('700 20px Cinzel'));
  await p.waitForTimeout(900);
  await p.screenshot({ path: process.argv[2] || 'wallpaper.png' });
  await b.close();
})();
