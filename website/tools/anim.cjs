const { chromium } = require('/Users/lawliang/projectrepos/aheadly/node_modules/playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const hash of ['', '#download', '#docs']) {
    const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
    const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
    await p.goto('file://' + process.argv[2] + hash); await p.waitForTimeout(1500);
    if (hash) { await p.evaluate(() => { location.hash = 'top'; }); await p.waitForTimeout(800); }
    const snap = () => p.evaluate(() => { const c = document.getElementById('field'); const x = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let h = 0; for (let i = 0; i < x.length; i += 97) h = (h * 31 + x[i]) | 0; return h + ':' + c.width + 'x' + c.height; });
    const a = await snap(); await p.waitForTimeout(1200); const c = await snap();
    console.log(JSON.stringify(hash || '(home)'), 'changing:', a !== c, a, c, 'errors:', errs.join(' | ') || 'none');
  }
  process.exit(0);
})();
