const { chromium } = require('/Users/lawliang/projectrepos/aheadly/node_modules/playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const [w,h,n,cs] of [[1440,780,'dd','dark'],[1440,780,'dl','light'],[400,860,'md','dark']]) {
    const p = await b.newPage({ viewport: { width: w, height: h }, colorScheme: cs });
    const errs=[]; p.on('pageerror', e => errs.push(e.message));
    await p.goto('file://' + process.argv[2]); await p.waitForTimeout(7300);
    await p.screenshot({ path: (process.env.OUT || require('os').tmpdir()) + '/qn-' + n + '.png' });
    if (errs.length) console.log(n, errs);
  }
  await b.close();
})();
