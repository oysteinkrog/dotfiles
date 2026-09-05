# Mobile-Responsive Patterns

A growing share of support tickets get filed from phones — angry-tweet-while-on-the-bus tickets, mid-meeting "this isn't working" tickets, screenshot-and-describe tickets. The default desktop UX for support widgets and ticket forms collapses awfully on mobile. This file is the architectural pattern.

## Three Mobile Surfaces

1. **The floating widget** — must work on a small viewport without obstructing core product features
2. **The ticket-filing form** — text-heavy form with attachments
3. **The ticket-detail / conversation view** — read-and-reply

Each has distinct mobile considerations.

## Widget On Mobile

### Sizing

On viewports < 640px (Tailwind `sm:` breakpoint), the widget:
- Takes 56×56px instead of 64×64px (less screen real estate)
- Sits at `bottom-4 right-4` so the iOS bottom safe-area doesn't collide
- The expanded panel takes 90vw width (not a fixed 288px) and slides in from the bottom rather than expanding from the corner

```tsx
<div className={cn(
  "fixed z-50",
  "right-4 bottom-4 lg:right-6 lg:bottom-6",
  "pb-[env(safe-area-inset-bottom)]"   // iOS bottom-bar avoidance
)}>
  {/* widget */}
</div>

{/* Expanded panel on mobile slides up full-width */}
<div className={cn(
  "border-border bg-card mb-3 rounded-xl border shadow-xl",
  "w-[90vw] max-w-sm",
  "fixed inset-x-4 bottom-20 lg:relative lg:bottom-auto lg:right-auto lg:w-72",
)}>
```

### Z-Index Coordination

The widget z-index conflicts with the product's mobile nav (which usually sits at `bottom-0`). Coordinate:

```css
.product-bottom-nav { z-index: 40; }
.support-widget { z-index: 50; }      /* above nav */
.support-modal { z-index: 60; }       /* above widget */
```

When the support modal opens on mobile, dim the bottom nav to indicate focus shift.

### Hiding On Specific Routes

Some product surfaces should never show the widget (login, checkout, fullscreen video). Add a route allow/block list:

```tsx
function shouldShowWidget(pathname: string): boolean {
  const blocked = ["/login", "/signup", "/checkout", /^\/watch\//];
  return !blocked.some(b => typeof b === "string" ? pathname === b : b.test(pathname));
}
```

## Form On Mobile

### Input Modes

Mobile keyboards adapt based on input attributes. Use them:

```tsx
<input type="email" inputMode="email" autoComplete="email" />
<input type="tel" inputMode="tel" autoComplete="tel-national" />
<input type="text" inputMode="numeric" pattern="[0-9]*" />
```

The right keyboard for the field shaves seconds off filing.

### Avoiding 16px Font Trap

iOS zooms when an input has `font-size < 16px` and gains focus. The zoom is jarring and usually doesn't unzoom cleanly. **Always `font-size: 16px` minimum on inputs/textareas.**

```css
input, textarea, select {
  font-size: 16px;        /* prevents iOS auto-zoom on focus */
}
```

### Textarea Auto-Grow

Customers writing a paragraph on mobile shouldn't have to scroll within a 4-line textarea:

```tsx
function AutoGrowTextarea({ value, onChange, ...rest }) {
  const ref = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 400)}px`;
  }, [value]);
  return <textarea ref={ref} value={value} onChange={onChange} {...rest} />;
}
```

400px cap prevents the textarea from consuming the entire screen.

### Submit Button Always Visible

Mobile keyboards cover the bottom half of the screen. Submit button should sit ABOVE the bottom of the form's last input:

```tsx
<form className="flex flex-col">
  {/* fields */}
  <textarea ... />
  <div className="sticky bottom-0 bg-card pt-2 pb-[env(safe-area-inset-bottom)]">
    <button type="submit" className="w-full">Create Ticket</button>
  </div>
</form>
```

`sticky` keeps the button above the keyboard regardless of content height.

### Camera/Photo Library

Mobile attachment UX should leverage the device:

```tsx
<input
  type="file"
  accept="image/*"
  capture="environment"           // back camera on mobile
  multiple
  onChange={onFilesAdded}
/>
```

`capture="environment"` opens the camera directly. Customers can take a screenshot of the issue without leaving the form.

For paste-to-attach: works on iPad/Mac mobile Safari but not iOS Safari (clipboard-image API limited). Surface a paste button instead:

```tsx
<button onClick={async () => {
  const items = await navigator.clipboard.read();
  // ... process clipboard image
}}>
  Paste image from clipboard
</button>
```

## Conversation View On Mobile

### Threading UX

Long conversations are unscrollable on mobile. Collapse older messages:

```tsx
function ConversationView({ messages }) {
  const [showAll, setShowAll] = useState(false);
  const visible = showAll ? messages : messages.slice(-3);
  return (
    <div>
      {!showAll && messages.length > 3 && (
        <button onClick={() => setShowAll(true)}>
          Show {messages.length - 3} earlier messages
        </button>
      )}
      {visible.map(m => <MessageBubble key={m.id} message={m} />)}
    </div>
  );
}
```

Only the last 3 messages render by default; the "show earlier" button reveals more.

### Pull-To-Refresh

Mobile users expect pull-to-refresh on conversation views:

```tsx
useEffect(() => {
  let startY = 0;
  const onTouchStart = (e: TouchEvent) => { startY = e.touches[0].clientY; };
  const onTouchEnd = (e: TouchEvent) => {
    const endY = e.changedTouches[0].clientY;
    if (window.scrollY === 0 && endY - startY > 80) {
      refetch();
    }
  };
  document.addEventListener("touchstart", onTouchStart);
  document.addEventListener("touchend", onTouchEnd);
  return () => {
    document.removeEventListener("touchstart", onTouchStart);
    document.removeEventListener("touchend", onTouchEnd);
  };
}, [refetch]);
```

Or use a library like `react-pull-to-refresh`. Visual indicator while pulling.

### Message Bubbles, Not Tables

Desktop conversation views often use tables; mobile needs chat-bubble layout:

```tsx
function MessageBubble({ message }) {
  const fromYou = message.senderType === "customer";
  return (
    <div className={cn("flex mb-3", fromYou ? "justify-end" : "justify-start")}>
      <div className={cn(
        "max-w-[80%] rounded-2xl px-4 py-2",
        fromYou ? "bg-primary text-primary-foreground" : "bg-muted",
      )}>
        <p className="text-sm">{message.message}</p>
        <p className="text-xs opacity-60 mt-1">{formatRelative(message.createdAt)}</p>
      </div>
    </div>
  );
}
```

iMessage / WhatsApp pattern; mobile users grok it instantly.

### Reply Form Sticky Bottom

Reply textarea + send button stuck at the bottom of the screen:

```tsx
<div className="sticky bottom-0 bg-card border-t border-border p-3 pb-[env(safe-area-inset-bottom)]">
  <div className="flex gap-2">
    <AutoGrowTextarea value={reply} onChange={...} placeholder="Reply..." />
    <button onClick={onSend}>Send</button>
  </div>
</div>
```

Keyboard pushes it up; thumb reaches it without stretch.

## Touch Targets

WCAG 2.5.5 requires touch targets ≥ 44×44px on mobile. Buttons, status pill clicks, message attachments — all must hit the minimum. Test with the dev tools device emulator + a thumb-shaped overlay.

## Performance On Mobile

Mobile users hit the support system on slower networks (carrier 4G, sometimes 3G). Be aggressive about:

- **Bundle size** — widget JS ≤ 25KB gz (per [PERFORMANCE-BUDGETS.md](PERFORMANCE-BUDGETS.md))
- **Lazy-load** modals on widget-open
- **Image optimization** — `<img loading="lazy" decoding="async" srcset="..." sizes="..." />`
- **Skeleton loaders** for slow networks (don't show spinner; show layout)
- **Optimistic updates** so UI doesn't wait for server confirmation

## Notification UX

Browser push notifications work on mobile. iOS 16.4+ supports web push via PWA install:

```ts
if ("Notification" in window && "serviceWorker" in navigator) {
  await Notification.requestPermission();
  // ... subscribe via push API
}
```

Don't request permission on first widget-open — too aggressive. Wait for: ticket created → "Want to be notified when we reply?" prompt.

## Offline Mode (Light)

Service worker caches static assets so the widget renders even offline:

```js
// sw.js
self.addEventListener("fetch", (e) => {
  if (e.request.url.endsWith("/api/support")) return;  // never cache API
  e.respondWith(
    caches.match(e.request).then(r => r || fetch(e.request))
  );
});
```

When user filing a ticket goes offline mid-typing:
- Save draft to IndexedDB
- Show banner: "📡 Offline. Your draft is saved; we'll send when you're back."
- On reconnect, retry POST automatically

## Testing Mobile

### Real Devices

Browser DevTools emulators are insufficient. Test on:
- iPhone 13/14 (iOS Safari)
- Pixel 6/7 (Android Chrome)
- iPad mini (different viewport class)

### Network Throttling

Chrome DevTools → Network → Throttling → "Slow 3G" before merging mobile changes. Acceptable: widget loads in ≤ 3s on Slow 3G.

### Touch Replay

Playwright supports mobile emulation:

```ts
test("widget filing on mobile", async ({ browser }) => {
  const ctx = await browser.newContext({
    ...devices["iPhone 13"],
    permissions: ["clipboard-read"],
  });
  const page = await ctx.newPage();
  await page.goto("/");
  await page.tap('[data-testid="support-widget"]');
  // ...
});
```

## Anti-Patterns

| ✗ | Why |
|---|---|
| Tiny 12px font on form inputs | iOS auto-zooms; jarring UX |
| Fixed-width 288px panel on mobile | Doesn't fit; horizontal scroll |
| Floating widget over bottom nav with same z-index | Click conflicts; user mistypes |
| Submit button absolutely positioned at form bottom | Hidden by mobile keyboard |
| Hover-to-reveal admin actions | No hover on touch |
| Tooltips on tap | Tap is also click; tooltip vanishes |
| Image upload without `capture="environment"` | Two-step: camera app → save → re-attach |
| Long tables on conversation view | Unscrollable on small screens |
| 200KB JS for the widget | 8s load on mobile data |
| Permission prompts on first open | Annoying; trains users to dismiss |
| No safe-area padding | Notch / home-indicator overlaps |

## Wire Points Checklist

- [ ] Widget responsive sizing (smaller, slide-from-bottom on mobile)
- [ ] `pb-[env(safe-area-inset-bottom)]` everywhere fixed-bottom UI sits
- [ ] All form inputs have `font-size: 16px` minimum
- [ ] `inputMode` and `autoComplete` set on every input
- [ ] Auto-grow textarea with cap
- [ ] Submit button sticky-bottom
- [ ] `capture="environment"` on file inputs
- [ ] Conversation view uses chat-bubble layout (not table)
- [ ] Sticky reply form at bottom
- [ ] Pull-to-refresh on detail view
- [ ] All touch targets ≥ 44×44px
- [ ] Bundle size budget enforced (≤ 25KB gz)
- [ ] Lazy-loaded modal contents
- [ ] Service-worker offline draft save
- [ ] Tested on real iOS + Android devices
- [ ] Tested with Slow-3G throttling
- [ ] Playwright mobile-emulation E2E tests
- [ ] Widget hidden on auth/checkout/fullscreen routes
- [ ] Push permission requested only after first ticket
