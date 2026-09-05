#!/usr/bin/env node
/**
 * Screenshot or record video of an HTML file using Playwright.
 *
 * Usage:
 *   Screenshot: ./screenshot-html.js <html-file> <output.png> [width] [height]
 *   Video:      ./screenshot-html.js <html-file> <output.webm> [width] [height] [duration_ms]
 */

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
        console.error('Usage: screenshot-html.js <html-file> <output.(png|webm)> [width] [height] [duration_ms]');
        process.exit(1);
    }

    const htmlFile = path.resolve(args[0]);
    const outputFile = path.resolve(args[1]);
    const width = parseInt(args[2]) || 2280;
    const height = parseInt(args[3]) || 480;
    const durationMs = parseInt(args[4]) || 6000;  // Default 6 seconds for video

    const isVideo = outputFile.endsWith('.webm');

    if (!fs.existsSync(htmlFile)) {
        throw new Error(`HTML file not found: ${htmlFile}`);
    }

    fs.mkdirSync(path.dirname(outputFile), { recursive: true });

    let browser;
    let context;

    try {
        browser = await chromium.launch();
        context = await browser.newContext({
            viewport: { width, height },
            // Required for video recording
            recordVideo: isVideo ? {
                dir: path.dirname(outputFile),
                size: { width, height }
            } : undefined
        });

        const page = await context.newPage();
        await page.goto(pathToFileURL(htmlFile).href, { waitUntil: 'networkidle' });

        if (isVideo) {
            // Get video reference BEFORE closing the page
            const video = page.video();

            // Wait for animation to complete
            await page.waitForTimeout(durationMs);

            // Close page to finalize video
            await page.close();

            // Now get the video path and move to desired output
            if (!video) {
                throw new Error('No video was recorded');
            }

            const videoPath = await video.path();
            try {
                fs.renameSync(videoPath, outputFile);
            } catch (e) {
                fs.copyFileSync(videoPath, outputFile);
                fs.unlinkSync(videoPath);
            }
            console.log(`Video saved: ${outputFile}`);
        } else {
            await page.screenshot({
                path: outputFile,
                omitBackground: true  // Preserve transparency
            });
            console.log(`Screenshot saved: ${outputFile}`);
        }
    } finally {
        if (context) {
            await context.close().catch(() => {});
        }
        if (browser) {
            await browser.close().catch(() => {});
        }
    }
}

main().catch(err => {
    console.error(err.message || err);
    process.exit(1);
});
