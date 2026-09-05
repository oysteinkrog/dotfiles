#!/usr/bin/env node
/**
 * Record multiple smeared_life shader modes to video files.
 *
 * Usage: node record-smeared-modes.js [output-dir]
 *
 * Starts a local server, records each mode, then stops.
 */

const { spawn } = require('child_process');
const os = require('os');
const path = require('path');
const http = require('http');
const fs = require('fs');

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (error) {
  console.error('Error: playwright is required. Run `npm install` in .claude/skills/obs-youtube-music first.');
  process.exit(1);
}

const HTML_FILE = 'test-mode-capture.html';
const PROJECT_DIR_CANDIDATES = [
  process.env.OBS_PROJECT_DIR,
  process.env.SMEARED_LIFE_DIR,
  process.cwd(),
  '/Users/jemanuel/projects/smeared_life'
].filter(Boolean);
const SMEARED_LIFE_DIR = PROJECT_DIR_CANDIDATES.find((candidate) =>
  fs.existsSync(path.join(candidate, HTML_FILE))
) || PROJECT_DIR_CANDIDATES[0];

// Modes to test
const MODES = [
  'SpinGlassCA',
  'FloquetTopoCA',
  'OrbitalMobiusCA',
  'HyperbolicCA',
  'HyperbolicFracCA',
  'WassersteinCA',
  'GaugeFluxCA',
  'HodgeFlowCA'
];

// Simple static file server
function createServer(dir, port) {
  const mimeTypes = {
    '.html': 'text/html',
    '.js': 'application/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml'
  };

  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      let filePath = path.join(dir, req.url.split('?')[0]);
      if (filePath.endsWith('/')) filePath += 'index.html';

      const ext = path.extname(filePath);
      const contentType = mimeTypes[ext] || 'application/octet-stream';

      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(404);
          res.end('Not found');
          return;
        }
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
      });
    });

    server.once('error', reject);
    server.listen(port, () => {
      const address = server.address();
      const actualPort = typeof address === 'object' && address ? address.port : port;
      console.log(`Server running at http://localhost:${actualPort}/`);
      resolve({ server, port: actualPort });
    });
  });
}

async function recordMode(modeName, outputFile, browser, port, width, height, fps, durationMs) {
  console.log(`\n=== Recording ${modeName} ===`);

  const context = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: 1
  });

  const page = await context.newPage();

  page.on('console', msg => {
    if (msg.type() === 'error') {
      console.log(`Browser error: ${msg.text()}`);
    }
  });
  page.on('pageerror', err => console.log('Page error:', err.message));

  const url = `http://localhost:${port}/test-mode-capture.html?mode=${modeName}&width=${width}&height=${height}&fps=${fps}&duration=${durationMs}`;
  console.log(`Loading: ${url}`);

  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1000); // Let WebGL initialize

  // Check if mode loaded successfully
  const modeText = await page.textContent('#modeName');
  if (modeText.startsWith('ERROR')) {
    console.log(`Skipping ${modeName}: ${modeText}`);
    await context.close();
    return false;
  }

  // Start ffmpeg
  const ffmpeg = spawn('ffmpeg', [
    '-y',
    '-f', 'image2pipe',
    '-framerate', String(fps),
    '-i', '-',
    '-c:v', 'libx264',
    '-preset', 'fast',
    '-crf', '18',
    '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart',
    outputFile
  ], {
    stdio: ['pipe', 'inherit', 'inherit']
  });

  const expectedFrames = Math.ceil((durationMs / 1000) * fps);
  let frameCount = 0;
  const startTime = Date.now();

  console.log(`Target: ${expectedFrames} frames for ${durationMs/1000}s`);

  while (frameCount < expectedFrames) {
    const screenshot = await page.screenshot({
      type: 'png',
      omitBackground: false,
      timeout: 30000
    });

    const written = ffmpeg.stdin.write(screenshot);
    if (!written) {
      await new Promise(resolve => ffmpeg.stdin.once('drain', resolve));
    }

    frameCount++;

    if (frameCount % 30 === 0) {
      const elapsed = (Date.now() - startTime) / 1000;
      const realFps = frameCount / elapsed;
      console.log(`  Frame ${frameCount}/${expectedFrames}, ${realFps.toFixed(1)} fps`);
    }

    const complete = await page.evaluate(() => window.stepFrame());
    if (complete) break;
  }

  console.log(`  Captured ${frameCount} frames, finalizing...`);

  ffmpeg.stdin.end();
  await new Promise((resolve, reject) => {
    ffmpeg.on('close', code => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg exited with ${code}`));
    });
    ffmpeg.on('error', reject);
  });

  await context.close();

  const totalTime = (Date.now() - startTime) / 1000;
  console.log(`  Done! ${outputFile} (${totalTime.toFixed(1)}s)`);

  return true;
}

async function main() {
  const outputDir = path.resolve(
    process.argv[2] ||
    process.env.OBS_OUTPUT_DIR ||
    path.join(os.homedir(), 'Movies')
  );
  const width = 854;
  const height = 480;
  const fps = 30;
  const durationMs = 5000;
  const port = Number(process.env.OBS_PORT || 0);

  console.log(`Output directory: ${outputDir}`);
  console.log(`Resolution: ${width}x${height} @ ${fps}fps`);
  console.log(`Duration: ${durationMs/1000}s per mode`);
  console.log(`Modes to record: ${MODES.join(', ')}`);

  const htmlPath = path.join(SMEARED_LIFE_DIR, HTML_FILE);
  if (!fs.existsSync(htmlPath)) {
    throw new Error(`Could not find ${HTML_FILE}. Set OBS_PROJECT_DIR or SMEARED_LIFE_DIR.`);
  }

  fs.mkdirSync(outputDir, { recursive: true });

  // Start server
  let server;
  let listeningPort;
  let browser;
  const results = [];

  try {
    ({ server, port: listeningPort } = await createServer(SMEARED_LIFE_DIR, port));

    // Launch browser
    browser = await chromium.launch({
      headless: true,
      args: [
        '--disable-web-security',
        '--use-gl=swiftshader',
        '--enable-webgl',
        '--enable-webgl2',
        '--ignore-gpu-blocklist',
        '--disable-gpu-sandbox'
      ]
    });

    for (let i = 0; i < MODES.length; i++) {
      const modeName = MODES[i];
      const num = String(i + 1).padStart(2, '0');
      const outputFile = path.join(outputDir, `intro_test_${num}_${modeName}.mp4`);

      try {
        const success = await recordMode(modeName, outputFile, browser, listeningPort, width, height, fps, durationMs);
        results.push({ mode: modeName, file: outputFile, success });
      } catch (err) {
        console.error(`Error recording ${modeName}:`, err.message);
        results.push({ mode: modeName, error: err.message, success: false });
      }
    }
  } finally {
    if (browser) {
      await browser.close();
    }
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
  }

  console.log('\n=== Summary ===');
  results.forEach((r, i) => {
    const num = String(i + 1).padStart(2, '0');
    if (r.success) {
      console.log(`${num}. ${r.mode}: ${r.file}`);
    } else {
      console.log(`${num}. ${r.mode}: FAILED - ${r.error || 'unknown error'}`);
    }
  });
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
