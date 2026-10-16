const { chromium } = require('/Users/lawliang/projectrepos/aheadly/node_modules/playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const [w, h, n, cs] of [[1440, 1100, 'd', 'dark'], [400, 1500, 'm', 'light']]) {
    const p = await b.newPage({ viewport: { width: w, height: h }, colorScheme: cs });
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    await p.goto('file://' + process.argv[2] + '#download'); await p.waitForTimeout(1200);
    await p.screenshot({ path: (process.env.OUT || require('os').tmpdir()) + '/dl-' + n + '.png' });
    // round trip: home and back
    await p.evaluate(() => { location.hash = 'why'; }); await p.waitForTimeout(300);
    const homeShown = await p.evaluate(() => !document.querySelector('#home-view').hidden && document.querySelector('#download-view').hidden);
    await p.evaluate(() => { location.hash = 'docs'; }); await p.waitForTimeout(300);
    const docsShown = await p.evaluate(() => !document.querySelector('#docs-view').hidden && document.querySelector('#download-view').hidden);
    console.log(n, 'home ok', homeShown, 'docs ok', docsShown, 'errors', errs.join(';') || 'none', 'hscroll', await p.evaluate(() => document.documentElement.scrollWidth > innerWidth));
  }
  process.exit(0);
})();
