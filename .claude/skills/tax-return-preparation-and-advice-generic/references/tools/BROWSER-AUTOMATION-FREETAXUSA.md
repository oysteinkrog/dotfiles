# FreeTaxUSA Browser Automation with Playwright — Battle-Tested Guide

> **Source:** Lessons extracted from complete MFJ filing sessions (Federal + State) via
> Playwright MCP tools. Every gotcha below was encountered in live filing.

## Overview

FreeTaxUSA is a strong low-cost profile for many individual returns, especially when combined
with Playwright browser automation via MCP. It can handle many common forms used in complex
1040 work, but coverage should still be verified against the actual return before treating it as
the default filing path. Product pricing and state coverage change, so verify those live too.

## Architecture

```
Claude Code + Playwright MCP
    ↓ browser_snapshot (accessibility tree — preferred over screenshots)
    ↓ browser_click / browser_fill_form / browser_type
    ↓ browser_press_key (for select-all + replace)
    ↓ browser_navigate (for direct URL jumps)
FreeTaxUSA web app (freetaxusa.com)
```

**Key principle:** Use `browser_snapshot` (accessibility tree) for navigation, NOT
`browser_take_screenshot`. The snapshot gives exact `ref` IDs for every interactive
element. Screenshots are only useful for visual verification of final results.

## Session Management

### Login
The user must log in manually — the agent should NEVER handle credentials. After login,
the session cookie persists. FreeTaxUSA sessions expire after ~30 minutes of inactivity.

### Session Expiration
If FreeTaxUSA shows a login page unexpectedly, the session expired. Ask the user to
log back in manually, then resume navigation. All previously-saved data persists — just
navigate back to where you were.

### Navigation Strategy
FreeTaxUSA uses a sidebar with major sections: Personal, Income, Deductions/Credits,
Misc, Summary, State, Final Steps. Within each section, "Save and Continue" advances
to the next page. You can also click sidebar buttons to jump between sections.

**CRITICAL:** Always click "Save and Continue" (not just navigate away) to persist
data on the current page. Navigating away without saving loses unsaved changes.

## Data Entry Patterns

### Text Fields
```
1. browser_snapshot → find the field's ref ID
2. browser_click on the field (ref)
3. browser_press_key("Control+a") to select all existing text
4. browser_type with the new value
```

For currency fields, enter numbers WITHOUT dollar signs or commas — FreeTaxUSA
formats them automatically. Enter `4919` not `$4,919`.

### Radio Buttons
Click the label/container element, not the radio input directly. The snapshot shows
radio buttons with their labels — click the parent `generic` element that contains both.

### Checkboxes
Click directly on the checkbox `ref`. Verify state changed with a follow-up snapshot.

### Dropdown/Combobox
Use `browser_fill_form` with `type: "combobox"` and `value` set to the visible option text.
Example: `{"type": "combobox", "value": "New York"}`.

### Date Fields
Enter as `mm/dd/yyyy` string. FreeTaxUSA validates the format.

### Form Fill (Multiple Fields)
Use `browser_fill_form` to fill multiple fields at once:
```json
[
  {"name": "First Name", "type": "textbox", "ref": "e123", "value": "John"},
  {"name": "Last Name", "type": "textbox", "ref": "e456", "value": "Smith"},
  {"name": "State", "type": "combobox", "ref": "e789", "value": "California"}
]
```

## Section-by-Section Navigation

### Personal Info
- Filing status, names, SSNs, DOBs, address, dependents
- SSNs: enter as 9 digits, no dashes
- For dependents, the CTC qualification questions matter materially; verify the current-year CTC
  and ACTC figures from the IRS before relying on memory

### Income — W-2
- Enter EXACTLY as shown on W-2, box by box
- For multi-state W-2s: enter state info in the W-2 state section, not separately
- FreeTaxUSA auto-handles state wage allocation
- **Watch for:** When a W-2 has local (city) wages in a separate state/local group from
  state wages, enter both groups. FreeTaxUSA may warn about "multiple state groups" — OK

### Income — Schedule C (Business Income)
- Each business entered separately with its own Edit/Add section
- Sections within each business: Basic Info, Income, Common Expenses, Vehicle,
  Health Insurance, Home Office, Depreciable Assets, QBI, Less Common Expenses
- **Business code:** Use 6-digit NAICS code (e.g., 541611 management consulting,
  711510 musicians, 721310 short-term lodging, 541511 software development)
- **Gross receipts:** Enter total gross income, NOT net
- **1099-NEC linkage:** If the business received 1099-NECs, add them in the Income section.
  Cosmetic — helps FreeTaxUSA match income to IRS records but doesn't change tax

### Income — Schedule C: Common Expenses
| Field | Notes |
|-------|-------|
| Contract Labor | 1099 payments to subcontractors |
| Repairs and Maintenance | Includes de minimis safe harbor items (<$2,500) |
| Insurance | Business insurance (NOT health insurance) |
| Taxes and Licenses | Property tax on business property, business licenses |
| Supplies | Consumable business supplies |
| Utilities | Business portion of utilities |
| Mortgage Interest | For business property |
| Advertising | Marketing, platform fees |

**De Minimis Safe Harbor (CRITICAL):** When asked about de minimis safe harbor election,
answer YES. This lets you expense items under $2,500 immediately as repairs/maintenance
instead of capitalizing them as long-term depreciable assets. Example: a $2,100 bathroom
repair goes to "Repairs and Maintenance" (full deduction this year) instead of being
depreciated over 27.5 years (~$76/year). The de minimis election saves ~$530 in Year 1
on that single item.

### Income — Schedule C: Depreciable Assets
- Each asset entered separately with description, date placed in service, cost, asset type
- **CRITICAL — description restrictions:** No parentheses allowed! Use hyphens instead.
  - BAD: `Rental unit (residential property)`
  - GOOD: `Rental unit - residential property`
- **Asset types available:** Buildings, Land improvements, Computers, Equipment, etc.
- **Section 179:** Can be elected per-asset. Use this when FreeTaxUSA doesn't auto-apply
  100% bonus depreciation (e.g., for 15-year land improvements under OBBBA)
- **Review requirement:** After adding assets, they must be "reviewed" or a red error
  blocks e-filing. Click Edit → Save and Continue through ALL pages for each asset.
  If an asset's review state won't stick, consider deleting and re-adding it.

### Income — Schedule C: Home Office (Form 8829)
- Each business can have its own home office
- For mid-year moves, add TWO home offices per business (one for each address)
- **Fields needed:** Home square footage, office square footage, months used, expenses

**CRITICAL — FreeTaxUSA auto-subtracts from Schedule A:** When it says "Enter ALL
mortgage interest/property taxes — we'll subtract the business portion," it means
enter the FULL amount on Schedule A. FreeTaxUSA handles the business-use subtraction
automatically. Do NOT manually reduce mortgage interest or property taxes before entering.

**CRITICAL — Multiple businesses sharing a home:** Each spouse's office is measured
separately from TOTAL home square footage. Do not double-count!
- Example: 3,000 sqft livable home. Spouse A uses 300 sqft, Spouse B uses 350 sqft.
- Spouse A: 300/3,000 = 10.0%. Spouse B: 350/3,000 = 11.67%.
- NOT: 650/3,000 = 21.67% split between them.
- Each Form 8829 is independent.

**CRITICAL — Use LIVABLE square footage:** Exclude unfinished basement, garage, attic,
utility closets from the denominator. A 4,000 sqft house with 1,000 sqft of unfinished
space means 3,000 sqft livable. Office of 300 sqft = 10.0%, NOT 7.5%.

**Time outside home:** Percentage of time the business owner works outside the home.
Consultant working primarily from home: ~10-15%. Music teacher with in-home lessons: ~15%.
Real estate agent mostly out: ~60-70%.

**Operating expense carryover:** If a prior year's Form 8829 Line 43 shows a carryover,
claim it on the current year's 8829 Line 25. Verify it wasn't dropped in an intervening
year — check each year's return.

### Income — Capital Gains (Schedule D / Form 8949)
- Enter brokerage 1099-Bs individually or as summary totals
- **Box codes matter:** Box A/B (short-term, basis reported/not), Box D/E (long-term)
- **Zero-basis crypto:** Enter $0 as cost basis — FreeTaxUSA will warn
  (IRS1099B_BASISZERO_SUM) but this is correct if that's the elected position
- **Capital loss carryforward:** Entered on the Schedule D screen, separated into
  short-term and long-term amounts. FreeTaxUSA auto-applies the $3,000 allowable loss.
- **File attachments:** FreeTaxUSA requires PDF attachments of 1099-B/1099-DA summary
  statements. Upload via the File Attachments page in Final Steps. If the file chooser
  modal gets cancelled, it can leave persistent "Please Try Again" errors — navigate
  away and back, then retry the upload.

### Income — K-1 Partnerships
- **PTP (Publicly Traded Partnerships):** FreeTaxUSA may not fully support PTP-specific
  K-1 handling. For small amounts (<$500 income), entering as non-PTP partnerships
  produces the same tax result.
- **CRITICAL — Partnership name restrictions:** No periods in names!
  - BAD: `Acme Partners L.P.`
  - GOOD: `Acme Partners LP`

### Income — Interest & Dividends
- Enter per-1099 from each institution
- Separate qualified dividends from ordinary dividends
- Section 199A dividends go in their own field (flows to QBI)
- Payments in Lieu (PILs) from securities lending: report as other income, NOT dividends

### Deductions/Credits — Itemized Deductions (Schedule A)
- **SALT:** Enter full state/local taxes paid. FreeTaxUSA applies the cap ($40K MFJ OBBBA).
  Include: state income tax, city income tax, property taxes, state disability/family leave.
- **Mortgage interest:** Enter the FULL amount from ALL 1098 forms. If the mortgage was
  transferred between servicers mid-year, you'll have multiple 1098s — sum them ALL.
  FreeTaxUSA subtracts the Form 8829 business-use portion automatically.
- **Prepaid interest from closing disclosure:** If you bought a home, prepaid interest from
  closing date to month-end may NOT appear on any 1098. Add it manually from the closing
  disclosure/settlement statement. This is a commonly-missed deduction.
- **Points:** Fully deductible in purchase year if all Pub 936 conditions are met
  (main home acquisition, customary in area, stated on closing disclosure, paid from
  buyer funds). Points on refinance must be amortized over the loan life.

### Deductions/Credits — IRA Contributions
- **Backdoor Roth (CRITICAL):** If doing Traditional IRA → Roth conversion, ONLY enter the
  Traditional contribution on this year's return. The conversion goes on the year it happens
  via Form 8606. Entering as Roth contribution at high income triggers excess contribution
  errors and potential penalties.

### Deductions/Credits — SEP-IRA
- **CRITICAL — Self-employed rate is 20%, NOT 25%.** The formula is:
  `plan rate / (1 + plan rate) = 25%/125% = 20%`. The 25% rate applies ONLY to W-2
  employees of corporations. Overcontributing triggers a 10% excise tax on the excess.
- Contribution limit: 20% × (net SE income × 0.9235) up to $70,000

### Deductions/Credits — QBI (Form 8995)
- FreeTaxUSA auto-calculates QBI from Schedule C data
- **QBI loss carryforward:** Entered on the QBI screen. Reduces current-year QBI deduction.
- **SSTB businesses (consulting, etc.):** QBI phases out above $394,600 MFJ and is fully
  eliminated above $494,600 MFJ.
  Rental income (non-SSTB) is not automatically zeroed out at high income, but above the
  threshold the W-2/UBIA limitation can still constrain the deduction.

### State Returns
- Each state has different screens and fields
- **Part-year city tax (NYC, Philadelphia, etc.):** Additional forms may be required.
  Verify income allocation matches actual income during city residence period.
- **County/school district:** Get the EXACT district name. Some states use specific codes.
- **State credits:** Many credits phase out at high AGI — check before spending time on them.

### Final Steps — Tax Return Alerts
- **Red errors** must be fixed before e-filing:
  - "Review Business Assets" — click Edit → Save and Continue through ALL pages
  - "State Payment More than Tax Owed" — update payment amount
  - "Please Try Again" — retry file upload
- **Yellow warnings** are informational — review but can proceed

### Final Steps — E-File Signature
- **Prior Year AGI:** Must match exactly (Form 1040 Line 11 from prior year)
- **Self-Select PINs:** Any 5-digit numbers, one per spouse/taxpayer
- **Consent checkboxes:** All required disclosures must be checked
- **IRREVERSIBLE:** "Send Tax Return" cannot be undone

## Known FreeTaxUSA Gotchas

| Issue | Workaround |
|-------|------------|
| Parentheses in asset descriptions | Use hyphens: `building - type` |
| Periods in partnership names | Remove: `LP` not `L.P.` |
| PTP K-1s not fully supported | Enter as non-PTP for small amounts |
| File upload modal cancelled → persistent errors | Navigate away and back, retry |
| Asset review state doesn't stick | Delete and re-add the asset |
| Section 179 not auto-applied for some types | Manually elect Section 179 per-asset |
| Session expires ~30min inactivity | User re-logs in; all data persists |
| Payment exceeds tax owed after changes | Update on State Direct Debit page |
| "Enter ALL mortgage interest" confusion | Enter FULL amount — 8829 subtraction auto |
| Home office % double-counting | Measure each office independently from total sqft |
| De minimis safe harbor election | Must answer YES to expense items under $2,500 |
| SEP-IRA rate confusion | 20% self-employed rate, NOT 25% |
| Backdoor Roth entered as Roth | Enter as Traditional only; conversion separate year |
| Multiple 1098s from servicer transfer | Sum ALL 1098s + prepaid interest from closing |

## Playwright-Specific Tips

1. **Always snapshot before acting.** The ref IDs change on every page load.
2. **Use `browser_fill_form` for multi-field pages** — more efficient than individual clicks.
3. **For replacing text in a field:** Click → Ctrl+A → type new value.
4. **Modal dialogs:** Some actions open modals. Buttons have own ref IDs in snapshot.
5. **Header bar shows running totals** (Federal Refund/Owed, State Due) — sanity check
   after each major section.
6. **Save frequently:** Click "Save and Continue" to persist.
7. **Tax Alert overlay:** When navigating from Final Steps alerts to a section, a floating
   panel persists. Close with X or "Back to Final Steps."

## Optimal Filing Workflow

```
PREPARATION (Phases 1-3 of the tax skill):
1. Complete intake, document analysis, cross-year error detection, optimization
2. Gather all source documents
3. Create FREETAXUSA_DATA_ENTRY_GUIDE.md with every line item and dollar amount
   — this is the single source of truth during filing

FILING (Phase 4):
4. User logs into FreeTaxUSA manually
5. Agent reads data entry guide as source of truth
6. Agent drives data entry section-by-section:
   a. Personal Info → b. W-2 → c. Schedule C × N → d. Capital gains
   e. K-1s → f. Interest/dividends → g. Itemized deductions (FULL amounts)
   h. IRA/SEP → i. Other credits → j. Summary verification
   k. State section → l. Final Steps (alerts, signatures, submit)
7. Download PDFs for records

VALIDATION (Phase 5):
8. Create analysis of filed return
9. Verify carryforward amounts for next year
10. Archive all documents
```

## Aiwyn as Cross-Check

Use Aiwyn Tax Engine calculations as a REFERENCE to validate FreeTaxUSA numbers,
not as the primary filing path. Known Aiwyn limitations:
- Form 8829 may be simplified (flat amount vs actual expenses)
- Part-year city tax computation may be missing or simplified
- Some state-specific forms may not be fully supported

**Workflow:** Calculate with Aiwyn when its live namespace coverage is confirmed →
enter into FreeTaxUSA → compare totals → investigate discrepancies → trust the
chosen filing product for transmission, and trust Aiwyn only within the scope its
current-year form coverage actually supports.

## Alternative: Codex CLI with Playwright

Codex (GPT) supports Playwright through its `js_repl` tool with `codex.emitImage()`
for visual verification. Useful for:
- Screenshot audit trail of every page
- Complex JS-heavy UI interaction
- Cross-validating Claude's data entry with a second model
