// Renders an SVG file to a PNG of a given pixel size, with a transparent background.
// Usage: node render.js <in.svg> <out.png> <pixels>   (needs Playwright with Chromium)
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [input, output, px] = process.argv.slice(2);
  const size = parseInt(px, 10);
  let svg = fs.readFileSync(input, 'utf8').replace(/width="\d+" height="\d+"/, `width="${size}" height="${size}"`);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await page.locator('svg').screenshot({ path: output, omitBackground: true });
  await browser.close();
})();
