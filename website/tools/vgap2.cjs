const { chromium } = require('/Users/lawliang/projectrepos/aheadly/node_modules/playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const w of [1440, 1000, 400]) {
    const p = await b.newPage({ viewport: { width: w, height: 900 } });
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    await p.goto('file://' + process.argv[2]); await p.waitForTimeout(1500);
    const out = await p.evaluate(() => {
      const c = document.createElement('canvas').getContext('2d');
      const ink = el => { const tw = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); let t, top = Infinity, bot = -Infinity; const cs = getComputedStyle(el); c.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily; const m = c.measureText(el.textContent.trim()); while ((t = tw.nextNode())) { if (!t.nodeValue.trim()) continue; const rg = document.createRange(); rg.selectNodeContents(t); for (const r of rg.getClientRects()) { if (r.width < 1) continue; top = Math.min(top, r.top + m.fontBoundingBoxAscent - m.actualBoundingBoxAscent); bot = Math.max(bot, r.bottom - (m.fontBoundingBoxDescent - m.actualBoundingBoxDescent)); } } return { top, bottom: bot }; };
      const h = ink(document.querySelector('#hero-copy h1')), d = ink(document.querySelector('#hero-copy .lede > p')), u = ink(document.querySelector('#hero-copy .hero-points'));
      const cta = document.querySelector('#hero-copy .hero-cta').getBoundingClientRect(), hero = document.querySelector('.hero').getBoundingClientRect();
      return `title->desc ${(d.top - h.bottom).toFixed(1)}  desc->bullets ${(u.top - d.bottom).toFixed(1)}  bullets->buttons ${(cta.top - u.bottom).toFixed(1)}  buttons end ${(cta.bottom - hero.top).toFixed(0)} / hero ${hero.height.toFixed(0)}`;
    });
    console.log(w, out, errs.join(';'));
  }
  process.exit(0);
})();
