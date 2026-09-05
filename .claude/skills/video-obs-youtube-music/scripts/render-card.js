#!/usr/bin/env node
/**
 * Render music card to WebM with alpha transparency.
 */

const { spawn } = require('child_process');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { pathToFileURL } = require('url');

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (error) {
  console.error('Error: playwright is required. Run `npm install` in .claude/skills/obs-youtube-music first.');
  process.exit(1);
}

const CARD_HTML = path.resolve(process.argv[2] || process.env.OBS_CARD_HTML || 'card.html');
const OUTPUT_FILE = path.resolve(process.argv[3] || process.env.OBS_CARD_OUTPUT || 'card.webm');
const WIDTH = 1900;
const HEIGHT = 480;
const FPS = 60;
const DURATION_S = 6;

async function main() {
  console.log(`Rendering card: ${CARD_HTML}`);
  console.log(`Output: ${OUTPUT_FILE}`);
  console.log(`Resolution: ${WIDTH}x${HEIGHT} @ ${FPS}fps`);
  console.log(`Duration: ${DURATION_S}s`);

  if (!fs.existsSync(CARD_HTML)) {
    throw new Error(`Card HTML not found: ${CARD_HTML}`);
  }

  fs.mkdirSync(path.dirname(OUTPUT_FILE), { recursive: true });

  const browser = await chromium.launch({ headless: true });
  const framesDir = fs.mkdtempSync(path.join(os.tmpdir(), 'obs-card-frames-'));
  const startTime = Date.now();

  try {
    const context = await browser.newContext({
      viewport: { width: WIDTH, height: HEIGHT },
      deviceScaleFactor: 1
    });

    const page = await context.newPage();

    page.on('console', msg => {
      if (msg.type() === 'error' || msg.text().includes('initialized')) {
        console.log(`Browser: ${msg.text()}`);
      }
    });

    await page.goto(pathToFileURL(CARD_HTML).href, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);

    const totalFrames = FPS * DURATION_S;

    console.log(`\nCapturing ${totalFrames} frames...`);

    for (let f = 0; f < totalFrames; f++) {
      const framePath = path.join(framesDir, `frame_${String(f).padStart(4, '0')}.png`);
      await page.screenshot({
        path: framePath,
        omitBackground: true  // Alpha transparency!
      });

      const complete = await page.evaluate(() => {
        if (typeof window.stepFrame !== 'function') {
          throw new Error('window.stepFrame() is not defined');
        }
        return window.stepFrame();
      });

      if ((f + 1) % 60 === 0) {
        const elapsed = (Date.now() - startTime) / 1000;
        const fps = (f + 1) / elapsed;
        console.log(`Frame ${f + 1}/${totalFrames} (${fps.toFixed(1)} fps)`);
      }

      if (complete) break;
    }

    await context.close();

    console.log(`\nEncoding to WebM with alpha...`);

    // Encode to WebM VP9 with alpha
    await new Promise((resolve, reject) => {
      const ffmpeg = spawn('ffmpeg', [
        '-y',
        '-framerate', String(FPS),
        '-i', path.join(framesDir, 'frame_%04d.png'),
        '-c:v', 'libvpx-vp9',
        '-pix_fmt', 'yuva420p',
        '-b:v', '2M',
        OUTPUT_FILE
      ], { stdio: 'inherit' });

      ffmpeg.on('error', reject);
      ffmpeg.on('close', code => {
        if (code === 0) resolve();
        else reject(new Error(`ffmpeg exited with ${code}`));
      });
    });
  } finally {
    await browser.close();
    fs.rmSync(framesDir, { recursive: true, force: true });
  }

  const stats = fs.statSync(OUTPUT_FILE);
  const totalTime = (Date.now() - startTime) / 1000;
  console.log(`\nDone!`);
  console.log(`Output: ${OUTPUT_FILE}`);
  console.log(`Size: ${(stats.size / 1024 / 1024).toFixed(1)} MB`);
  console.log(`Time: ${totalTime.toFixed(1)}s`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
