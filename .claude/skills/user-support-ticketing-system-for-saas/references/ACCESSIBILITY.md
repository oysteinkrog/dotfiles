# Accessibility (WCAG 2.2 AA)

A support system MUST work for users with disabilities. The customer who can't see your modal can't open a ticket; the customer who can't tab through the form can't tell you about the bug.

This file covers the WCAG 2.2 AA requirements that hit a support flow specifically. Not every WCAG criterion — just the ones that bite.

## Why This Matters

- Legal exposure: ADA / EU Accessibility Act / EN 301 549
- Reputation: "the support form doesn't work with my screen reader" → social media → trust loss
- Practical: 15-25% of users have temporary or permanent disabilities at any time

## The High-Leverage Fixes

If you only do five things:

1. Every form input has a `<label>` (visible or `aria-label`).
2. Focus is trapped in modals AND restored when closing.
3. All interactive elements are keyboard-reachable AND show a visible focus ring.
4. Status changes (ticket created, breach notice) announce via `aria-live`.
5. Color contrast ≥ 4.5:1 for text, ≥ 3:1 for UI components / large text.

## Component Checklist

### SupportWidget (Trigger Button)

```tsx
<button
  type="button"
  aria-haspopup="dialog"
  aria-expanded={open}
  aria-controls="support-dialog"
  onClick={() => setOpen(true)}
>
  <span aria-hidden="true">💬</span>
  <span className="sr-only">Open support</span>
</button>
```

The icon is decorative (`aria-hidden`). The screen-reader-only text gives the label.

### Support Dialog (Modal)

```tsx
<Dialog
  open={open}
  onOpenChange={setOpen}
  aria-labelledby="support-title"
  aria-describedby="support-desc"
>
  <DialogContent>
    <h2 id="support-title">Contact support</h2>
    <p id="support-desc">Tell us what's going on. We typically reply within 4 hours.</p>

    {/* Form */}
  </DialogContent>
</Dialog>
```

Use Radix UI `<Dialog>` (already does focus trap, ESC-to-close, focus restoration). Do not roll your own modal.

### Ticket Form

```tsx
<form aria-labelledby="form-heading">
  <h3 id="form-heading">New ticket</h3>

  <div>
    <label htmlFor="subject">
      Subject
      <span aria-label="required" className="text-red-600">*</span>
    </label>
    <input
      id="subject"
      name="subject"
      required
      aria-describedby={subjectError ? "subject-error" : undefined}
      aria-invalid={!!subjectError}
    />
    {subjectError && (
      <p id="subject-error" role="alert" className="text-red-600">
        {subjectError}
      </p>
    )}
  </div>

  <div>
    <label htmlFor="body">Describe the issue</label>
    <textarea
      id="body"
      name="body"
      rows={6}
      aria-describedby="body-help"
      required
    />
    <p id="body-help" className="text-sm text-gray-600">
      Include any error messages, what you tried, and what you expected.
    </p>
  </div>

  <fieldset>
    <legend>Priority</legend>
    {/* radios with proper grouping */}
  </fieldset>

  <button type="submit">Submit ticket</button>
</form>
```

**Don't** use `<div onClick>` instead of `<button>`. Don't use `placeholder` as the only label.

### Ticket List (User Side)

```tsx
<ul role="list" aria-label="Your support tickets">
  {tickets.map(t => (
    <li key={t.id}>
      <a href={`/support/tickets/${t.id}`}>
        <h3>{t.subject}</h3>
        <p>
          <span className="sr-only">Status: </span>
          <span aria-label={statusLabel(t.status)}>
            <StatusIcon status={t.status} aria-hidden />
            {statusLabel(t.status)}
          </span>
        </p>
        <time dateTime={t.createdAt.toISOString()}>
          {timeAgo(t.createdAt)}
        </time>
      </a>
    </li>
  ))}
</ul>
```

The status icon is decorative; the text label carries semantics.

### Ticket Detail (Message Thread)

```tsx
<article aria-labelledby="thread-title">
  <h1 id="thread-title">{ticket.subject}</h1>

  <ol role="list" aria-label="Conversation history">
    {messages.map(m => (
      <li key={m.id}>
        <article aria-labelledby={`msg-${m.id}-author`}>
          <header>
            <span id={`msg-${m.id}-author`}>
              {m.senderType === "support" ? "Support team" : "You"}
            </span>
            <time dateTime={m.createdAt.toISOString()}>
              {formatDate(m.createdAt)}
            </time>
          </header>
          <div>{m.message}</div>
        </article>
      </li>
    ))}
  </ol>

  {/* Reply form, if open */}
</article>
```

### Admin Dashboard

The admin UI is internal but accessibility still matters — staff with disabilities need it too.

Critical for the admin queue:
- Keyboard navigation through the ticket list
- Filter chips operable by keyboard (Radix `<Tabs>` / `<ToggleGroup>`)
- Status / priority dropdowns: native `<select>` or Radix `<Select>` (which is accessible)
- Tables: real `<table>` with `<th scope="col">`, not divs

## Status Announcements

When a ticket is created, replied-to, or its status changes, announce it:

```tsx
// src/components/a11y/LiveRegion.tsx
"use client";
import { useEffect, useState } from "react";

export function LiveRegion({ message, urgency = "polite" }: {
  message: string;
  urgency?: "polite" | "assertive";
}) {
  return (
    <div role="status" aria-live={urgency} aria-atomic="true" className="sr-only">
      {message}
    </div>
  );
}
```

Wire into the form:

```tsx
const [announcement, setAnnouncement] = useState("");

const submit = async (data: TicketInput) => {
  const ticket = await createTicket(data);
  setAnnouncement(`Ticket created. Reference number: ${ticket.id.slice(0, 8)}.`);
  // Reset after a beat
  setTimeout(() => setAnnouncement(""), 5000);
};

return (
  <>
    <LiveRegion message={announcement} />
    {/* form */}
  </>
);
```

## Keyboard Tests

Test these flows with the keyboard alone:

```
□ Tab through the trigger → opens dialog
□ Tab through the form → all fields reachable in logical order
□ Submit with Enter / Space on submit button
□ Tab to "Close" or press ESC → dialog closes, focus returns to trigger
□ Tab through the ticket list → each row reachable as a link
□ Tab through the message thread → reply textarea is reachable
□ Filter chips on admin: arrow keys move between them, Enter activates
□ Table headers do NOT receive Tab focus (they're not interactive)
□ Status dropdown opens with Space / Down arrow
```

If any fail, fix before shipping.

## Color Contrast

Set a CSS rule and audit:

```css
/* Body text against background */
:root {
  --text: #0a0a0a;        /* against white: 19.86:1 */
  --text-muted: #525252;  /* against white: 7.55:1 */
  --primary: #2563eb;     /* against white: 5.46:1, AA */
  --error: #dc2626;       /* against white: 4.51:1, AA */
}
```

Don't hand-pick "looks fine" colors. Use a contrast checker. WCAG AA = 4.5:1 normal text, 3:1 large.

For status colors, never rely on color alone:

```tsx
{/* BAD */}
<span className={status === "open" ? "text-red" : "text-green"}>•</span>

{/* GOOD */}
<span>
  <span aria-hidden className={status === "open" ? "text-red" : "text-green"}>●</span>
  <span className="sr-only">Status: </span>
  {statusLabel}
</span>
```

## Reduced Motion

Honor `prefers-reduced-motion`:

```css
.dialog-enter {
  animation: dialog-fade 200ms;
}

@media (prefers-reduced-motion: reduce) {
  .dialog-enter {
    animation: none;
  }
}
```

For Framer Motion / similar:

```tsx
const reduceMotion = useReducedMotion();
<motion.div
  initial={reduceMotion ? false : { opacity: 0 }}
  animate={{ opacity: 1 }}
/>
```

## Screen-Reader Sanity Check

Run NVDA (Windows, free) or VoiceOver (Mac, built-in) through the support flow:

```
Open SupportWidget → Should hear: "Open support, button"
Click → "Contact support, dialog. Tell us what's going on..."
Tab → "Subject, required, edit text"
Type → as expected
Tab to body → "Describe the issue, edit text, multi-line"
Tab to submit → "Submit ticket, button"
Activate → "Ticket created. Reference number: ..."
```

If anything is unannounced or confusingly announced, fix it.

## Common Failures

| Failure | Fix |
|---|---|
| `<div onClick>` instead of `<button>` | Use `<button>` |
| `placeholder` as label | Add `<label>` |
| Custom dropdown with no keyboard support | Use Radix `<Select>` |
| Modal traps but doesn't restore focus | Use Radix `<Dialog>` |
| Status icon with no text label | Add `<span className="sr-only">` |
| Color-only error indicator | Add icon + text |
| Auto-focus on page load | Don't (disorients screen readers) |
| `tabindex="3"` and similar | Don't override DOM order |
| Inaccessible CAPTCHA | Use hCaptcha or Turnstile, not text-based |

## Tooling

- **Lint**: `eslint-plugin-jsx-a11y` (mandatory)
- **Test**: `@axe-core/react` in development; jest-axe in test suite
- **CI**: `pa11y-ci` against staging URLs
- **Manual**: NVDA / VoiceOver for the support flow specifically

```bash
# In CI:
npx pa11y-ci --sitemap https://staging.example.com/sitemap.xml
```

## ARIA Cheat Sheet (For This Domain)

```html
<!-- Dialog -->
role="dialog" aria-modal="true" aria-labelledby aria-describedby

<!-- Status changes (e.g., "Ticket created") -->
role="status" aria-live="polite"  -- non-urgent
role="alert" aria-live="assertive"  -- error / urgent

<!-- Form errors -->
aria-invalid="true" aria-describedby="field-error"

<!-- Required field -->
required aria-required="true"

<!-- Buttons that toggle disclosure -->
aria-expanded="true|false" aria-controls="target-id"

<!-- Loading spinners -->
role="progressbar" aria-busy="true" aria-label="Loading tickets"

<!-- Hidden but readable -->
class="sr-only"  -- visible to screen readers, not visually
aria-hidden="true"  -- hidden from screen readers (decorative)
```

## Companion Refs

- [USER-UI.md](USER-UI.md) — widget + form components
- [ADMIN-UI.md](ADMIN-UI.md) — admin queue accessibility
- `/ux-audit` skill — Nielsen heuristics + a11y audit
- `/frontend-design` plugin skill — for design-system-level fixes
