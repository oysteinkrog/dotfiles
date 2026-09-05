#!/usr/bin/env node
/**
 * Record intro animation to video using Playwright and ffmpeg.
 *
 * Usage: node record-intro.js <html-file> <output.mp4> [fps] [width] [height]
 *
 * Captures frames from the browser at a consistent FPS and pipes them to ffmpeg.
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

let chromium;
try {
    ({ chromium } = require('playwright'));
} catch (error) {
    console.error('Error: playwright is required. Run `npm install` in .claude/skills/obs-youtube-music first.');
    process.exit(1);
}

async function main() {
    const args = process.argv.slice(2);

    if (args.length < 2) {
        console.error('Usage: record-intro.js <html-file> <output.mp4> [fps] [width] [height]');
        process.exit(1);
    }

    const htmlFile = path.resolve(args[0]);
    const outputFile = path.resolve(args[1]);
    const fps = parseInt(args[2]) || 60;
    const width = parseInt(args[3]) || 1920;
    const height = parseInt(args[4]) || 1080;

    if (!fs.existsSync(htmlFile)) {
        throw new Error(`HTML file not found: ${htmlFile}`);
    }

    fs.mkdirSync(path.dirname(outputFile), { recursive: true });

    console.log(`Recording ${htmlFile}`);
    console.log(`Output: ${outputFile}`);
    console.log(`Resolution: ${width}x${height} @ ${fps}fps`);

    // Launch browser with WebGL support
    let browser;
    try {
        browser = await chromium.launch({
            headless: true,
            args: [
                '--disable-web-security',
                '--use-gl=swiftshader',     // Software OpenGL for headless
                '--enable-webgl',
                '--enable-webgl2',
                '--ignore-gpu-blocklist',
                '--disable-gpu-sandbox'
            ]
        });

        const context = await browser.newContext({
            viewport: { width, height },
            deviceScaleFactor: 1
        });

        const page = await context.newPage();

        // Log any page errors
        page.on('console', msg => {
            if (msg.type() === 'error' || msg.type() === 'warning') {
                console.log(`Browser ${msg.type()}: ${msg.text()}`);
            }
        });
        page.on('pageerror', err => console.log('Page error:', err.message));

        // Load the HTML file
        await page.goto(pathToFileURL(htmlFile).href, { waitUntil: 'networkidle' });

        // Wait a moment for WebGL to initialize
        await page.waitForTimeout(500);

        // Get the expected duration from the page config
        const durationMs = await page.evaluate(() => window.CONFIG?.duration || 5000);
        const expectedFrames = Math.ceil((durationMs / 1000) * fps);

        console.log(`Starting synchronized frame capture (target: ${expectedFrames} frames for ${durationMs/1000}s)...`);

        // Start ffmpeg process to receive frames via stdin
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

        let frameCount = 0;
        let startTime = Date.now();
        const ffmpegDone = new Promise((resolve, reject) => {
            ffmpeg.on('error', reject);
            ffmpeg.on('close', (code) => {
                if (code === 0) {
                    resolve();
                } else {
                    reject(new Error(`ffmpeg exited with code ${code}`));
                }
            });
        });

        // Synchronized capture loop: screenshot first, then step animation
        // This ensures the animation only advances when we're ready for the next frame
        while (frameCount < expectedFrames) {
            const screenshot = await page.screenshot({
                type: 'png',
                omitBackground: false,
                timeout: 120000
            });

            const written = ffmpeg.stdin.write(screenshot);
            if (!written) {
                await new Promise(resolve => ffmpeg.stdin.once('drain', resolve));
            }

            frameCount++;

            if (frameCount % 30 === 0) {
                const elapsed = (Date.now() - startTime) / 1000;
                const realFps = frameCount / elapsed;
                const remaining = expectedFrames - frameCount;
                const eta = remaining / realFps;
                console.log(`Frame ${frameCount}/${expectedFrames}, ${realFps.toFixed(2)} fps, ETA: ${eta.toFixed(0)}s`);
            }

            const complete = await page.evaluate(() => {
                if (typeof window.stepFrame !== 'function') {
                    throw new Error('window.stepFrame() is not defined');
                }
                return window.stepFrame();
            });
            if (complete) {
                console.log(`Animation complete after ${frameCount} frames`);
                break;
            }

            if (frameCount > fps * 60) {
                console.log('Max frame limit reached');
                break;
            }
        }

        console.log(`Captured ${frameCount} frames, finalizing video...`);

        ffmpeg.stdin.end();
        await ffmpegDone;

        await context.close();

        const totalTime = (Date.now() - startTime) / 1000;
        console.log(`\nRecording complete!`);
        console.log(`Frames: ${frameCount}`);
        console.log(`Duration: ${(frameCount / fps).toFixed(2)}s`);
        console.log(`Capture time: ${totalTime.toFixed(1)}s`);
        console.log(`Output: ${outputFile}`);
    } finally {
        if (browser) {
            await browser.close();
        }
    }
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
