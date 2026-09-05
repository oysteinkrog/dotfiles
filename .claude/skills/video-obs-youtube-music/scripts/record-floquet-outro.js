#!/usr/bin/env node
/**
 * Record FloquetTopoCA outro video at 4K resolution
 * Uses step-driven animation for frame-perfect capture
 */

const { createServer } = require('http');
const { readFileSync, existsSync, mkdirSync, mkdtempSync, rmSync } = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (error) {
  console.error('Error: playwright is required. Run `npm install` in .claude/skills/obs-youtube-music first.');
  process.exit(1);
}

const HTML_FILE = 'outro-workflow-capture.html';
const PROJECT_DIR_CANDIDATES = [
  process.env.OBS_PROJECT_DIR,
  process.env.SMEARED_LIFE_DIR,
  process.cwd(),
  '/Users/jemanuel/projects/smeared_life'
].filter(Boolean);
const PROJECT_DIR = PROJECT_DIR_CANDIDATES.find((candidate) =>
  existsSync(path.join(candidate, HTML_FILE))
) || PROJECT_DIR_CANDIDATES[0];
const OUTPUT_DIR = path.resolve(process.env.OBS_OUTPUT_DIR || path.join(os.homedir(), 'Movies'));
const PORT = Number(process.env.OBS_PORT || 0);
const BROWSER_ARGS = process.platform === 'darwin'
  ? ['--disable-web-security', '--use-gl=angle', '--use-angle=metal']
  : [
      '--disable-web-security',
      '--use-gl=swiftshader',
      '--enable-webgl',
      '--enable-webgl2',
      '--ignore-gpu-blocklist',
      '--disable-gpu-sandbox'
    ];

// MIME types
const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

async function main() {
  const htmlPath = path.join(PROJECT_DIR, HTML_FILE);
  if (!existsSync(htmlPath)) {
    throw new Error(`Could not find ${HTML_FILE}. Set OBS_PROJECT_DIR or SMEARED_LIFE_DIR.`);
  }

  mkdirSync(OUTPUT_DIR, { recursive: true });

  // Create HTTP server for the project
  const server = createServer((req, res) => {
    let filePath = path.join(PROJECT_DIR, req.url === '/' ? HTML_FILE : req.url);

    if (!existsSync(filePath)) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }

    const ext = path.extname(filePath);
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    try {
      const content = readFileSync(filePath);
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
    } catch (err) {
      res.writeHead(500);
      res.end('Server error');
    }
  });

  let browser;
  const tempDir = mkdtempSync(path.join(os.tmpdir(), 'floquet-outro-'));
  let listeningServer;
  let port;

  try {
    ({ server: listeningServer, port } = await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(PORT, () => {
        const address = server.address();
        const actualPort = typeof address === 'object' && address ? address.port : PORT;
        console.log(`Server running at http://localhost:${actualPort}`);
        resolve({ server, port: actualPort });
      });
    }));

    // Launch browser
    browser = await chromium.launch({
      headless: true,
      args: BROWSER_ARGS,
    });

    const context = await browser.newContext({
      viewport: { width: 4096, height: 2304 },
      deviceScaleFactor: 1,
    });

    const page = await context.newPage();

    // Navigate to the page
    await page.goto(`http://localhost:${port}/${HTML_FILE}`);

    // Wait for initialization
    await page.waitForFunction(() => window.CONFIG !== undefined);

    // Get config
    const config = await page.evaluate(() => window.CONFIG);
    console.log(`Recording: ${config.width}x${config.height} @ ${config.fps}fps for ${config.duration / 1000}s`);

    const totalFrames = Math.ceil((config.duration / 1000) * config.fps);
    console.log(`Total frames: ${totalFrames}`);

    console.log('Recording frames...');
    const startTime = Date.now();

    for (let frame = 0; frame < totalFrames; frame++) {
      // Step the animation
      await page.evaluate(() => {
        if (typeof window.stepFrame !== 'function') {
          throw new Error('window.stepFrame() is not defined');
        }
        return window.stepFrame();
      });

      // Capture screenshot
      const framePath = path.join(tempDir, `frame_${String(frame).padStart(6, '0')}.png`);
      await page.screenshot({ path: framePath, type: 'png' });

      // Progress update every 60 frames
      if (frame > 0 && frame % 60 === 0) {
        const elapsed = (Date.now() - startTime) / 1000;
        const fps = frame / elapsed;
        const remaining = (totalFrames - frame) / fps;
        console.log(`  Frame ${frame}/${totalFrames} (${(frame / totalFrames * 100).toFixed(1)}%) - ${fps.toFixed(1)} fps - ETA: ${remaining.toFixed(0)}s`);
      }
    }

    const elapsed = (Date.now() - startTime) / 1000;
    console.log(`\nCapture complete in ${elapsed.toFixed(1)}s (${(totalFrames / elapsed).toFixed(1)} fps avg)`);

    await context.close();

    // Encode to video with FFmpeg
    const outputPath = path.join(OUTPUT_DIR, 'floquet_outro.mp4');
    console.log(`\nEncoding to ${outputPath}...`);

    const ffmpegArgs = [
      '-y',
      '-framerate', String(config.fps),
      '-i', `${tempDir}/frame_%06d.png`,
      '-c:v', 'libx264',
      '-preset', 'slow',
      '-crf', '18',
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      outputPath,
    ];

    const ffmpeg = spawn('ffmpeg', ffmpegArgs, { stdio: 'inherit' });

    await new Promise((resolve, reject) => {
      ffmpeg.on('error', reject);
      ffmpeg.on('close', (code) => {
        if (code === 0) {
          console.log(`\nOutro video created: ${outputPath}`);
          resolve();
        } else {
          reject(new Error(`FFmpeg exited with code ${code}`));
        }
      });
    });
  } finally {
    if (browser) {
      await browser.close();
    }
    if (listeningServer) {
      await new Promise((resolve) => listeningServer.close(resolve));
    }
    rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
