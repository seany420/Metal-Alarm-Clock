// Renders the web clock's SVG artwork into PNG layers for the iOS app.
// Usage: NODE_PATH=$(npm root -g) node ios/tools/render-art.cjs
const path = require('path');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
const fonts = path.join(root, 'ios/MetalAlarm/Resources/Fonts');
const out = path.join(root, 'ios/MetalAlarm/Resources/Art');

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 1200 }, deviceScaleFactor: 1 });
  await p.goto('file://' + path.join(root, 'index.html'));
  await p.waitForTimeout(300);
  await p.evaluate((fonts) => {
    const st = document.createElement('style');
    st.textContent = `
      @font-face { font-family: "Cinzel"; font-weight: 700; src: url("file://${fonts}/Cinzel.ttf"); }
      html, body { background: transparent !important; margin: 0; padding: 0; }
      .rim-drip { animation: none !important; transform: scaleY(.85); }
      #stage-out svg { display: block; }`;
    document.head.appendChild(st);
    window.__clock = document.querySelector('#clock').cloneNode(true);
    window.__mask = document.querySelector('.prop.mask').cloneNode(true);
    window.__knife = document.querySelector('.prop.knife').cloneNode(true);
    document.body.innerHTML = '<div id="stage-out"></div>';
  }, fonts);
  await p.evaluate(() => document.fonts.load("700 30px Cinzel"));

  const show = (fn) => p.evaluate(fn);
  const shot = async (name, size) => {
    await p.waitForTimeout(150);
    await p.locator('#stage-out svg').screenshot({ path: path.join(out, name), omitBackground: true });
    console.log('wrote', name, size || '');
  };
  const layers = {
    'face.png': ['#hand-hour', '#hand-min', '#hand-sec', ':scope > circle:nth-last-of-type(1)', ':scope > circle:nth-last-of-type(2)'],
    'hand-hour.png': 'hour', 'hand-min.png': 'min', 'hand-sec.png': 'sec', 'cap.png': 'cap'
  };
  for (const [name, spec] of Object.entries(layers)) {
    await p.evaluate(({ spec }) => {
      const s = window.__clock.cloneNode(true);
      s.removeAttribute('id'); s.setAttribute('viewBox', '-245 -245 490 490');
      s.setAttribute('width', 1200); s.setAttribute('height', 1200); s.style.width = s.style.height = '1200px';
      const kids = [...s.children].filter((c) => c.tagName !== 'defs');
      const caps = kids.filter((c) => c.tagName === 'circle').slice(-2);
      const keep = (els) => kids.forEach((c) => { if (!els.includes(c)) c.remove(); });
      if (Array.isArray(spec)) {
        ['#hand-hour', '#hand-min', '#hand-sec'].forEach((q) => s.querySelector(q).remove());
        caps.forEach((c) => c.remove());
      } else if (spec === 'cap') keep(caps);
      else keep([s.querySelector('#hand-' + spec)]);
      const o = document.querySelector('#stage-out'); o.innerHTML = ''; o.appendChild(s);
    }, { spec });
    await shot(name);
  }
  for (const [name, key, w] of [['mask.png', '__mask', 600], ['knife.png', '__knife', 300]]) {
    await p.evaluate(({ key, w }) => {
      const s = window[key].cloneNode(true);
      s.removeAttribute('class'); s.style.cssText = `width:${w}px;height:auto;rotate:0deg;position:static`;
      const o = document.querySelector('#stage-out'); o.innerHTML = ''; o.appendChild(s);
    }, { key, w });
    await shot(name);
  }
  // App icon: full-bleed, opaque, 1024px
  await p.setViewportSize({ width: 1024, height: 1024 });
  await p.goto('file://' + path.join(root, 'icon.svg'));
  await p.evaluate(() => {
    const s = document.querySelector('svg');
    s.setAttribute('width', 1024); s.setAttribute('height', 1024);
    s.querySelector('rect').setAttribute('rx', 0);
    document.documentElement.style.background = '#070405';
  });
  await p.screenshot({ path: path.join(root, 'ios/MetalAlarm/Assets.xcassets/AppIcon.appiconset/icon-1024.png'), omitBackground: false });
  console.log('wrote icon-1024.png');
  await b.close();
})();
