# Debugging & Verification

## Step 1: Check if the image endpoint returns data

```bash
curl -s -w "SIZE: %{size_download} bytes\n" -o /dev/null "https://yoursite.com/page/opengraph-image"
```

If SIZE is 0, the ImageResponse is crashing silently. Review Satori rules in SKILL.md.

## Step 2: Download and verify the PNG

```bash
curl -s -o /tmp/og_test.png "https://yoursite.com/page/opengraph-image"
file /tmp/og_test.png  # Should say "PNG image data, 1200 x 630"
```

## Step 3: Verify meta tags include cache-bust params

```bash
curl -s "https://yoursite.com/page" | grep -i 'og:image\|twitter:image'
```

**Good** (file convention working):
```
og:image: https://yoursite.com/page/opengraph-image?a1b2c3d4
twitter:image: https://yoursite.com/page/twitter-image?e5f6g7h8
```

**Bad** (explicit metadata overriding):
```
og:image: https://yoursite.com/page/opengraph-image
twitter:image: https://yoursite.com/page/opengraph-image
```

## Step 4: Compare with a working page

If another page's OG image works, diff the meta tag patterns:
```bash
curl -s "https://yoursite.com/working-page" | grep 'og:image'
curl -s "https://yoursite.com/broken-page" | grep 'og:image'
```

Working pages will have `?hash` query params; broken ones won't.

## Step 5: Verify on social platforms

Platforms cache aggressively. Force refresh after deploying:
- **Twitter/X**: [Card Validator](https://cards-dev.twitter.com/validator) or re-paste URL
- **Facebook/Messenger**: [Sharing Debugger](https://developers.facebook.com/tools/debug/)
- **Telegram**: Delete and re-paste the link in chat
- **LinkedIn**: [Post Inspector](https://www.linkedin.com/post-inspector/)

## Diagnostic Checklist

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| 0-byte response | Satori crash | Check for `.map()` in SVG, `<polygon>`, `<text>`, WebP |
| Image renders but platforms don't show it | Missing cache-bust hash | Remove explicit `openGraph`/`twitter` from page metadata |
| Twitter shows OG image not twitter-image | Explicit `twitter.images` in metadata | Remove it; let file convention handle |
| Image worked before, now stale | Platform cache | Use platform debugger tools above |
| `TypeError: u2 is not iterable` | WebP image | Convert to PNG or JPEG |
