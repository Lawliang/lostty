const { chromium } = require('/Users/lawliang/projectrepos/aheadly/node_modules/playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const [w, n] of [[1440, 'd'], [400, 'm']]) {
    const p = await b.newPage({ viewport: { width: w, height: 800 }, colorScheme: 'dark' });
    await p.goto('file://' + process.argv[2]); await p.waitForTimeout(1500);
    await p.evaluate(() => {
      const z = window.__z, hero = document.querySelector('.hero');
      z.rows.forEach(q => { const d = document.createElement('div'); d.style.cssText = `position:absolute;left:${q.c0 * z.cw}px;top:${q.r0 * z.chh}px;width:${(q.c1 - q.c0 + 1) * z.cw}px;height:${z.chh}px;background:rgba(229,25,156,.28);pointer-events:none;z-index:5`; hero.appendChild(d); });
    });
    await p.screenshot({ path: (process.env.OUT || require('os').tmpdir()) + '/ov-' + n + '.png', clip: { x: 0, y: 56, width: w, height: 620 } });
  }
  process.exit(0);
})();
