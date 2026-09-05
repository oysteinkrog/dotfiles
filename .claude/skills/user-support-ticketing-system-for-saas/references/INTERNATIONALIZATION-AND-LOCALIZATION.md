# Internationalization And Localization

A SaaS that grows past its first market starts getting tickets in languages the team doesn't speak, from timezones the team doesn't work, with tone expectations the team doesn't share. This file is the architectural pattern for handling that gracefully.

## Three Distinct Concerns

1. **Internationalization (i18n)** — system code that handles any locale (dates, currencies, plural rules, RTL)
2. **Localization (l10n)** — translation of strings (UI, emails, KB)
3. **Cultural calibration** — tone, formality, expectations that differ by audience

## The Locale Resolution Order

Per request, resolve locale in this order:

1. URL query param `?lang=fr-FR` (admin-controlled, debug)
2. Customer's `users.preferredLanguage` column
3. `Accept-Language` HTTP header
4. Org default
5. System default (typically `en-US`)

```ts
async function resolveLocale(req: Request, user?: User, org?: Organization): Promise<Locale> {
  const url = new URL(req.url);
  const fromQuery = url.searchParams.get("lang");
  if (fromQuery && isSupportedLocale(fromQuery)) return fromQuery;
  if (user?.preferredLanguage && isSupportedLocale(user.preferredLanguage)) return user.preferredLanguage;
  const fromHeader = pickBestLocale(req.headers.get("accept-language"), SUPPORTED_LOCALES);
  if (fromHeader) return fromHeader;
  if (org?.defaultLanguage) return org.defaultLanguage;
  return DEFAULT_LOCALE;
}
```

Persist resolved locale on the ticket at create time (`metadata.locale`) — used for response language and tone.

## Customer-Facing Strings

Every UI string passes through a translation function:

```tsx
import { useTranslations } from "next-intl";

function NewTicketForm() {
  const t = useTranslations("support.newTicket");
  return (
    <form>
      <label>{t("subjectLabel")}</label>
      <input placeholder={t("subjectPlaceholder")} />
      <button>{t("submitLabel")}</button>
    </form>
  );
}
```

Translation files per locale:

```
locales/
  en-US.json
  es-ES.json
  fr-FR.json
  de-DE.json
  ja-JP.json
  pt-BR.json
```

Where `en-US.json` is the source of truth; others are translations. Track translation completeness; UI in untranslated locales falls back to en-US per-key (not whole-file).

## Email Templates Per Locale

Email subject and body localized:

```
src/emails/templates/transactional/
  ticket-created.en-US.tsx
  ticket-created.es-ES.tsx
  ticket-created.fr-FR.tsx
  ...
```

Or single template with dictionary lookup:

```tsx
function TicketCreatedEmail({ locale, ticket, sla }) {
  const t = getMessages(locale).ticketCreated;
  return (
    <html lang={locale}>
      <body>
        <h1>{t.greeting(displayName)}</h1>
        <p>{t.confirmationBody(ticket.id, sla.hours)}</p>
        ...
      </body>
    </html>
  );
}
```

The `<html lang={locale}>` is critical for accessibility (screen readers pick the right voice).

## Date / Time / Number Formatting

Never hand-format dates. Use `Intl.DateTimeFormat`:

```ts
function formatTicketTime(date: Date, locale: string, timezone: string): string {
  return new Intl.DateTimeFormat(locale, {
    timeZone: timezone,
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

// "Apr 27, 2026, 9:30 AM"  (en-US)
// "27 avr. 2026, 09:30"     (fr-FR)
// "2026年4月27日 9:30"     (ja-JP)
```

Currency:

```ts
new Intl.NumberFormat(locale, { style: "currency", currency: "USD" }).format(19.99);
// "$19.99"   (en-US)
// "19,99 $US" (fr-CA)
```

Plural rules:

```ts
function formatTicketCount(n: number, locale: string): string {
  const pr = new Intl.PluralRules(locale);
  const messages = {
    en: { one: "1 ticket", other: `${n} tickets` },
    ru: { one: `${n} тикет`, few: `${n} тикета`, many: `${n} тикетов`, other: `${n} тикета` },
  };
  const lang = locale.split("-")[0];
  return messages[lang][pr.select(n)] ?? messages.en.other;
}
```

## RTL Support

Arabic, Hebrew, Persian, Urdu read right-to-left. Set `dir` attribute and use logical CSS properties:

```tsx
<html lang={locale} dir={isRtl(locale) ? "rtl" : "ltr"}>
```

```css
/* ❌ Hard-coded directional */
.message { margin-left: 1rem; }

/* ✅ Logical properties */
.message { margin-inline-start: 1rem; }
```

Test the admin queue and conversation view in RTL — flex direction, padding, icons (chevron, arrow) all need flipping.

## Auto-Translate For Admin Convenience

Admin gets a French ticket; admin doesn't speak French. Provide one-click auto-translate:

```tsx
function MessageBubble({ message, customerLocale }) {
  const [translated, setTranslated] = useState<string | null>(null);
  const adminLocale = useAdminLocale();
  const showTranslate = customerLocale && customerLocale !== adminLocale && !translated;
  return (
    <div>
      <p>{translated ?? message.message}</p>
      {showTranslate && (
        <button onClick={async () => {
          const t = await translateText(message.message, customerLocale, adminLocale);
          setTranslated(t);
        }}>
          🌐 Translate from {languageName(customerLocale)}
        </button>
      )}
      {translated && <span className="text-xs text-muted">Translated by {translationProvider}</span>}
    </div>
  );
}
```

The translation is *visible only to the admin* — the original ticket and customer-facing reply remain in the customer's language. Translation is a tool for the admin, not a substitute for human reply.

## Reply In Customer's Language

For text agents reply in the customer's language. AI-assisted draft can help:

```tsx
<button onClick={async () => {
  const draft = await generateDraftReply({
    ticketId,
    instruction: "Apologize and acknowledge",
    targetLocale: ticket.metadata.locale,
  });
  setReply(draft);  // populates the textarea with the drafted text in target locale
}}>
  ✨ Draft reply in {languageName(ticket.metadata.locale)}
</button>
```

`/de-slopify` runs against the target locale (separate AI-tell catalog per language). The admin reviews the draft and edits — never auto-sent.

## Tone And Formality Calibration

Different cultures expect different formality:

| Locale | Default Formality | Example |
|---|---|---|
| en-US | Casual ("Hi") | "Hey, thanks for reaching out!" |
| en-GB | Mid ("Hello") | "Hello, thanks for getting in touch." |
| de-DE | Formal ("Sehr geehrte/r") | "Sehr geehrte Frau Müller, vielen Dank..." |
| ja-JP | Honorific (敬語) | "お問い合わせいただきありがとうございます。" |
| fr-FR | Formal-default | "Bonjour, merci de votre message..." |

Per-locale templates encode the default tone. Customer's preference can override:

```ts
interface UserCommunicationPrefs {
  formality: "casual" | "default" | "formal";  // overrides locale default
}
```

## Right-To-Left Email Templates

Email clients vary wildly in RTL support. Test:
- Gmail (good)
- Outlook (varies by version)
- Apple Mail (good)
- Yahoo (mixed)

Use `dir="rtl"` on the `<table>` (most common email layout container) and flip flex / float properties.

## Translation QA Workflow

Before shipping a new translation:

1. **Native review** — a native speaker (contractor, customer-success rep, or volunteer) reads every string for accuracy
2. **Pluralization spot-check** — n=0, 1, 2, 5, 22 in the language's plural rules
3. **Length check** — German strings are typically 30% longer than English; UI must accommodate
4. **Variable preservation** — `{name}`, `{count}` placeholders survive translation
5. **Date/currency ground truth** — sample ticket renders as expected

Translation services to consider:
- **Crowdin / Lokalise / Phrase** — managed platforms with translator workflow
- **DeepL / Google Translate API** — for auto-translate
- **Native human contractors** — for high-stakes locales where machine translation embarrasses

## Locale-Aware Spam Detection

The spam classifier defaults assume English text. Test against samples in other locales; tune patterns. A "all caps" check fires on Cyrillic shouting; a "phone number regex" doesn't catch French/UK formats.

## Search Across Locales

Customer-side ticket search and KB search need locale-aware tokenizers:

- English: simple whitespace + stemming
- German: compound-word splitting (Donaudampfschifffahrtsgesellschaft → 4 tokens)
- Japanese: morphological analysis (no spaces)
- Arabic: stem extraction with prefix/suffix handling

Postgres `tsvector` supports many locales via dictionaries:

```sql
CREATE INDEX support_tickets_search_de_idx
ON support_tickets USING gin (to_tsvector('german', subject || ' ' || description))
WHERE metadata->>'locale' LIKE 'de-%';
```

Or use a dedicated search engine (Meilisearch, Typesense, Elasticsearch) with per-locale config.

## Locale-Aware Notification Quiet Hours

Customer in Tokyo doesn't want a 3 AM email. Resolve their timezone:

```ts
function shouldSendNow(user: User, urgency: "transactional" | "marketing"): boolean {
  if (urgency === "transactional") return true;  // ticket replies always send
  const userTime = nowInTimezone(user.timezone);
  const hour = userTime.getHours();
  return hour >= 8 && hour < 21;
}
```

Marketing / digest emails respect quiet hours; transactional (ticket-created, response, resolved) always send.

## Organization-Level Defaults

Enterprise customers may standardize their org on a locale:

```ts
interface Organization {
  defaultLanguage: string;       // 'en-US'
  defaultTimezone: string;        // 'America/New_York'
  forceUserLocale: boolean;       // if true, all members use org language regardless of personal preference
}
```

`forceUserLocale = true` overrides individual preference — useful for compliance-driven customers who must communicate only in their primary language for audit.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Hard-coded English in code | Pretty obvious; but easy to slip in `<button>Save</button>` |
| Format dates with `toLocaleString()` and no `timeZone` option | Server-side formatting uses UTC; client expects user-tz |
| Concatenating translated strings | Word order varies by locale; "{X} tickets" vs "Tickets: {X}" |
| Reusing en-US plural code for other locales | Russian / Arabic / etc. have multiple plural forms |
| Email templates with `dir="ltr"` hardcoded | RTL emails break |
| Auto-translate rendered as if from the customer | Translated reply might mistranslate the customer's intent; the translation is for admin context only |
| AI draft in customer's locale without /de-slopify | Slop in French is still slop |
| Spam classifier tuned only for English | False negatives in non-English |
| No customer-locale preference | Customer always sees English; trust loss |
| Notifications without quiet-hour respect | 3 AM emails kill engagement |
| Translating internal admin UI strings into 12 locales | Huge upkeep; admin UI in English is fine for v1 |

## Wire Points Checklist

- [ ] Locale resolution function with priority order (query > user > header > org > default)
- [ ] Persisted `metadata.locale` on tickets at create
- [ ] Translation file per supported locale (`locales/<locale>.json`)
- [ ] Per-key fallback to `en-US` for missing translations
- [ ] Email templates per locale OR template with locale-aware dictionary
- [ ] `<html lang={locale}>` and `<html dir={...}>` set
- [ ] All dates / numbers / currencies via `Intl` APIs with explicit `timeZone`
- [ ] Plural rules using `Intl.PluralRules`
- [ ] Logical CSS properties (`margin-inline-start`, etc.) for RTL safety
- [ ] One-click auto-translate on customer messages (admin-only)
- [ ] AI-assisted draft in target locale + `/de-slopify` per locale
- [ ] Per-locale tone defaults; per-customer override
- [ ] Translation QA workflow (native review, pluralization spot-check, length check)
- [ ] Locale-aware search (Postgres `tsvector` per dictionary, or external search engine)
- [ ] Quiet-hour respect on non-transactional emails
- [ ] Customer locale preference UI; org default override
- [ ] Locale-aware spam-classifier tuning
- [ ] Test: ticket created in fr-FR routes through fr-FR template chain
- [ ] Test: RTL admin queue layout doesn't break
