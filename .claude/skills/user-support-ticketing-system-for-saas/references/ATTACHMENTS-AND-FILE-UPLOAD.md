# Attachments And File Upload

Customer screenshots, log files, video reproductions — attachments are the difference between "I can't reproduce" and "I see exactly what's wrong." But they're also the highest-risk surface in the support system: file upload, persistence, retrieval, retention, scanning, signed URLs, leakage. This file is the architectural pattern.

## Schema

The canonical implementation stores attachments as a JSONB array on the message row:

```ts
attachments: jsonb("attachments").$type<{ name: string; url: string; type: string }[]>(),
```

That works for small N (max 5 enforced at the validation layer). For projects with heavier attachment usage, normalize into a `support_attachments` table:

```ts
export const supportAttachments = pgTable("support_attachments", {
  id: uuid().primaryKey().defaultRandom(),
  ticketId: uuid().references(() => supportTickets.id, { onDelete: "cascade" }).notNull(),
  messageId: uuid().references(() => supportMessages.id, { onDelete: "cascade" }),
  uploaderId: uuid().references(() => users.id).notNull(),
  uploaderType: text().notNull(),                 // 'customer' | 'support'

  // Storage
  storageBucket: text().notNull(),                // 'support-attachments'
  storageKey: text().notNull(),                   // 'tickets/abc123/screenshot-456.png'

  // File metadata
  filename: text().notNull(),                     // user-provided name
  contentType: text().notNull(),                  // sniffed, not user-claimed
  sizeBytes: integer().notNull(),
  checksum: text().notNull(),                     // sha256 hash

  // Lifecycle
  scanStatus: text().default("pending").notNull(),  // pending | clean | infected | quarantined
  scanRanAt: timestamp({ withTimezone: true }),
  retentionUntil: timestamp({ withTimezone: true }).notNull(),

  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("support_attachments_ticket_idx").on(t.ticketId),
  index("support_attachments_scan_idx").on(t.scanStatus),
  index("support_attachments_retention_idx").on(t.retentionUntil),
]);
```

**Key choice:** the persisted URL is the bucket key, not a public URL. Public access is via *fresh* signed URLs generated per request. Attachments are never publicly addressable.

## Upload Flow (Two-Step)

Single-request multipart uploads are slow and brittle for files > 5MB. Use a **two-step signed-URL upload**:

```
Client                        Server                        S3/R2
  │                              │                            │
  │── POST /uploads/sign ────────│                            │
  │  { filename, type, size }    │                            │
  │                              │── auth check, validate ────│
  │                              │                            │
  │←── { uploadUrl, key } ───────│                            │
  │                              │                            │
  │── PUT uploadUrl ─────────────│────────────────────────────│
  │                              │                            │
  │← 200 ────────────────────────│────────────────────────────│
  │                              │                            │
  │── POST /messages with key ───│                            │
  │                              │── verify object exists ────│
  │                              │── enqueue virus scan ──────│
  │                              │── insert attachment row ───│
  │                              │                            │
  │←── { messageId, attachments }│                            │
```

### Step 1 — Sign

```ts
// POST /api/uploads/sign
const signSchema = z.object({
  filename: z.string().max(255).refine(
    (n) => !/[\\/<>"|?*:\x00-\x1f]/.test(n),
    "Invalid filename"
  ),
  contentType: z.string().refine(
    (t) => ALLOWED_CONTENT_TYPES.has(t),
    "Unsupported file type"
  ),
  sizeBytes: z.number().int().positive().max(MAX_UPLOAD_BYTES),
});

const ALLOWED_CONTENT_TYPES = new Set([
  "image/png", "image/jpeg", "image/gif", "image/webp",
  "application/pdf",
  "text/plain", "text/csv", "application/json",
  "video/mp4", "video/webm",
  "application/zip", "application/x-tar", "application/gzip",
]);
const MAX_UPLOAD_BYTES = 25 * 1024 * 1024;  // 25MB

// SVG is deliberately excluded by default. It is scriptable content, not just
// an image. Enable only if you sanitize it, serve with attachment disposition,
// and never inline it in the admin/customer UI.

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.success) return auth.response;
  const body = signSchema.parse(await request.json());

  const key = `tickets/uploads/${auth.user.userId}/${randomUUID()}-${sanitize(body.filename)}`;
  const uploadUrl = await getSignedPutUrl(BUCKET, key, {
    contentType: body.contentType,
    contentLengthRange: [1, body.sizeBytes],   // upper-bound enforcement
    expiresIn: 600,                             // 10 minutes
  });

  return NextResponse.json({ key, uploadUrl, expiresAt: new Date(Date.now() + 600_000).toISOString() });
}
```

**Critical guards:**
- Filename sanitization to prevent path traversal.
- `contentType` whitelist; reject MIME types not on the list. (Sniff post-upload to verify.)
- `sizeBytes` cap enforced at signing time AND at the S3 policy level (`contentLengthRange`).
- Signed URL expires in 10 minutes — stalled uploads must restart.

### Step 2 — Confirm

After client uploads to the signed URL, the client posts the message with the storage key:

```ts
// POST /api/support/tickets/[id]/messages
const addMessageSchema = z.object({
  message: z.string().min(1).max(10000),
  attachments: z.array(z.object({
    name: z.string(),
    storageKey: z.string().regex(/^tickets\/uploads\/[^/]+\/.+/),  // owner prefix required
    contentType: z.string(),
    sizeBytes: z.number().int().positive(),
  })).max(5).optional(),
});

// In the handler:
for (const a of attachments) {
  const expectedPrefix = `tickets/uploads/${auth.user.userId}/`;
  if (!a.storageKey.startsWith(expectedPrefix)) {
    return validationError({ attachments: "Attachment key does not belong to this user" });
  }
  // Verify the object actually exists in storage (not a forged key)
  const head = await s3.send(new HeadObjectCommand({ Bucket: BUCKET, Key: a.storageKey }));
  if (!head) return validationError({ attachments: "Object not found" });
  if (head.ContentLength !== a.sizeBytes) return validationError({ attachments: "Size mismatch" });
  // Sniff content type
  const sniffedType = await sniffContentType(BUCKET, a.storageKey);
  if (sniffedType !== a.contentType) return validationError({ attachments: "Type mismatch" });
  // Insert row, enqueue scan
  await db.insert(supportAttachments).values({...});
  await enqueueVirusScan(a.storageKey);
}
```

The `HEAD` check prevents an attacker from POSTing a key for an object they didn't upload — they'd have to know the storage key, but defense-in-depth requires the verification.
The owner-prefix check is equally important: a guessed or leaked key for another
user must not be attachable to the current user's ticket.

## Virus Scanning

All uploaded files are scanned before they're served to anyone. Default to ClamAV via a queue:

```ts
async function scanAttachment(attachmentId: string) {
  const att = await getAttachment(attachmentId);
  const stream = await getObject(att.storageBucket, att.storageKey);
  const result = await clamavScan(stream);  // 'clean' | 'infected' | 'error'
  await db.update(supportAttachments).set({
    scanStatus: result === "clean" ? "clean" : "quarantined",
    scanRanAt: new Date(),
  }).where(eq(supportAttachments.id, attachmentId));
  if (result === "infected") {
    await alertSecurity({ attachmentId, ticketId: att.ticketId, uploaderId: att.uploaderId });
  }
}
```

**Until scan completes**, the attachment is `pending`:
- UI shows "🔍 Scanning..." badge.
- Download / signed-URL endpoint refuses to generate URLs for `pending` attachments.
- Customer is told "Your file is being scanned; admins will see it shortly."

**Quarantine** does NOT delete the file (preserved for forensics) but blocks all access. Security team reviews quarantined files.

## Signed URL Generation On Read

The `attachments[].url` field returned to the client is **never the persisted storage URL**. Each read generates a fresh signed URL with short expiry:

```ts
// In the message-list endpoint:
const enrichedMessages = await Promise.all(messages.map(async (m) => ({
  ...m,
  attachments: await Promise.all((m.attachments ?? []).map(async (a) => ({
    name: a.name,
    type: a.contentType,
    url: await getSignedGetUrl(BUCKET, a.storageKey, {
      expiresIn: 3600,                        // 1h
      contentDisposition: `attachment; filename="${safeDownloadName(a.name)}"`,
    }),
  }))),
})));
```

If a customer forwards the email containing the attachment URL to a third party two hours later, the URL is dead. Re-clicking from the original email regenerates a fresh URL on the next page load.

## Per-Sender-Type Retention

Different attachments have different retention policies:

| Source | Retention | Rationale |
|---|---|---|
| Customer-uploaded | 90 days after ticket close | Keep for short-term issue re-investigation |
| Support-uploaded (e.g. annotated screenshots) | 1 year | Knowledge for similar future tickets |
| Content-moderation snapshots | 7 years | Legal compliance |
| Quarantined (infected) | Indefinite | Forensic |

Cron sweeps `retentionUntil < now() AND scanStatus != 'quarantined'` and deletes both DB row and storage object.

## Customer Privacy Defaults

When a customer requests data deletion (GDPR), their attachments are deleted *immediately* from storage (not retained for the standard window) UNLESS:
- The ticket is content-moderation (legal hold)
- Active investigation flagged on ticket

Document this in your privacy policy.

## Image-Specific Considerations

### EXIF Stripping

Customer screenshots may contain GPS coordinates, device serial numbers, original creation timestamps. Strip EXIF on upload:

```ts
async function stripExif(bucket: string, key: string) {
  const buffer = await getObjectAsBuffer(bucket, key);
  const stripped = await sharp(buffer).rotate().withMetadata({ exif: undefined }).toBuffer();
  await putObject(bucket, key, stripped);
}
```

Run as part of the post-upload pipeline (after virus scan, before marking `clean`).

### Thumbnail Generation

For images, generate a smaller thumbnail asynchronously and store at `${storageKey}.thumb`. The admin UI lists attachments with thumbnails — clicking opens the full-size signed URL. Reduces bandwidth for queue browsing.

## Video Considerations

Videos can be huge. Defaults:
- Max size: 100MB (separate from attachments cap)
- Auto-transcode to a standardized format (MP4/H.264) for cross-browser playback
- Generate poster image for thumbnail
- Streaming via signed URLs with `Range` support

## Sensitive-Content Detection (Optional)

For consumer-facing SaaS, run uploaded images through a sensitive-content classifier (NSFW / violence / CSAM). On detection:
- CSAM → immediate hard stop: block all access, alert legal counsel/trust-and-safety, follow the jurisdiction-specific reporting path (for U.S. providers, NCMEC), and suspend the uploader pending review. Do not expose it to admins or keep extra copies; preservation/retention is a legal procedure, not a support feature.
- NSFW → flag in admin queue with content warning; show pixelated by default; admin click-through to view.
- Violence → similar to NSFW.

This requires legal review per jurisdiction. Don't ship without it.

## Drag-And-Drop UI

The new-ticket form and reply form both support drag-and-drop:

```tsx
<div onDrop={handleDrop} onDragOver={(e) => e.preventDefault()}>
  {dragActive && <p className="text-muted">Drop files to attach</p>}
  {attachments.map(a => (
    <AttachmentChip key={a.id} attachment={a} onRemove={() => removeAttachment(a.id)} />
  ))}
  <input type="file" multiple onChange={handleFileInput} />
</div>
```

Show progress per file; allow removal before submission.

## Paste-To-Attach

A feature customers love: paste an image from clipboard directly. Web `paste` event with `clipboardData.items`:

```tsx
useEffect(() => {
  function onPaste(e: ClipboardEvent) {
    for (const item of e.clipboardData?.items ?? []) {
      if (item.type.startsWith("image/")) {
        const blob = item.getAsFile();
        if (blob) startUpload(blob);
      }
    }
  }
  textareaRef.current?.addEventListener("paste", onPaste);
  return () => textareaRef.current?.removeEventListener("paste", onPaste);
}, []);
```

Especially useful for screenshot-driven bug reports.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Storing public URL on the message row | URL leaks last forever; can't revoke access |
| Trusting client-supplied `contentType` | MIME spoofing; sniff post-upload |
| No size cap | DOS risk; storage cost balloon |
| No virus scanning | Distributing malware to support agents |
| Synchronous virus scan in upload path | UI hangs for 30+ seconds |
| Same retention for all attachments | Compliance and storage costs misaligned |
| Returning storage URLs in API responses | Defeats signed-URL pattern |
| Not stripping EXIF | Customer privacy regression |
| Permanent signed URLs with 7-day expiry | Default to 1 hour; force regeneration |
| Sharing one bucket across tenants without prefix isolation | Cross-tenant access via key enumeration |

## Wire Points Checklist

- [ ] Two-step upload: `/api/uploads/sign` returns short-lived signed PUT URL
- [ ] Storage key sanitized; `contentType` whitelisted; `sizeBytes` capped at signing
- [ ] Confirm route does HEAD verification on the storage key
- [ ] Content type sniffed post-upload, mismatches rejected
- [ ] Virus scan enqueued; UI surfaces "scanning" state
- [ ] EXIF stripped on images
- [ ] Thumbnails generated for images
- [ ] Storage key persisted; signed URLs generated per-request with ≤ 1h expiry
- [ ] Per-sender-type retention policy applied
- [ ] Quarantined files preserved but inaccessible
- [ ] CSAM detection (if consumer-facing)
- [ ] GDPR-deletion handler removes attachments immediately (with legal-hold exceptions)
- [ ] Drag-and-drop + paste-to-attach in the UI
- [ ] Test: signed URL expires; subsequent fetch fails
- [ ] Test: forged storage key (uploader didn't own) rejected
- [ ] Test: oversized upload rejected at policy level
