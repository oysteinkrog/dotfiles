# Aiwyn Tax Engine — Setup and Integration Reference

> **Purpose:** Aiwyn is a deterministic tax calculation engine accessed via the
> Model Context Protocol (MCP). It computes federal and state tax returns, generates
> IRS-ready PDFs, and enables scenario modeling. This document covers installation,
> tool reference, capabilities, limitations, and integration workflows.

---

## TABLE OF CONTENTS

1. [What Is Aiwyn?](#1-what-is-aiwyn)
2. [Installation](#2-installation)
3. [MCP Tools Reference](#3-mcp-tools-reference)
4. [Capabilities and Limitations](#4-capabilities-and-limitations)
5. [E-Filing Strategy](#5-e-filing-strategy)
6. [Discovery Workflow](#6-discovery-workflow)
7. [Full Return Calculation Workflow](#7-full-return-calculation-workflow)
8. [Formatting Rules and Data Conventions](#8-formatting-rules-and-data-conventions)

---

## 1. WHAT IS AIWYN?

Aiwyn (powered by Column API) is a deterministic tax calculation engine that:

- Computes federal Form 1040 and supporting schedules/forms
- Covers the federal return plus a live, queryable set of supported state jurisdictions
- Accepts structured input (taxpayer info, income, deductions, credits)
- Returns computed tax liability, refund/amount due, and all intermediate calculations
- Generates PDF tax returns suitable for filing
- Supports scenario modeling (compare different filing strategies)
- Discovers its own schema (what inputs it accepts, what forms it supports)

**Why it matters:** LLMs should never do raw tax math. Aiwyn provides deterministic,
auditable calculations. The LLM's role is gathering information, choosing strategies,
verifying coverage, and interpreting results — not computing tax liability.

---

## 2. INSTALLATION

### 2A. Claude Code

```bash
claude mcp add --transport http --scope user aiwyn-tax https://mcp.columnapi.com/mcp
```

This writes the MCP server configuration to `~/.claude.json` (the user-level config file).

**Important:** The config goes in `~/.claude.json`, NOT in `settings.json`. The `--scope user`
flag ensures this. This is a common mistake — if someone reports that the Aiwyn tools
are not available, check that the config is in the correct file.

**To verify installation:**
```bash
cat ~/.claude.json | grep -A 3 aiwyn
```

You should see something like:
```json
{
  "mcpServers": {
    "aiwyn-tax": {
      "type": "http",
      "url": "https://mcp.columnapi.com/mcp"
    }
  }
}
```

### 2B. OpenAI Codex CLI

```bash
codex mcp add aiwyn-tax --url https://mcp.columnapi.com/mcp
```

This registers the MCP server with Codex CLI. Codex will discover and present the
tools automatically.

### 2C. Gemini CLI

Add to your Gemini CLI settings file (typically `~/.gemini/settings.json`):

```json
{
  "mcpServers": {
    "aiwyn-tax": {
      "url": "https://mcp.columnapi.com/mcp"
    }
  }
}
```

### 2D. Other MCP-Compatible Clients

Any MCP client that supports HTTP transport can connect:
- **URL:** `https://mcp.columnapi.com/mcp`
- **Transport:** HTTP (not stdio)
- **Authentication:** None required (public API)

---

## 3. MCP TOOLS REFERENCE

Aiwyn exposes 10 MCP tools. Here is the complete reference:

### 3A. Discovery Tools

| Tool | Purpose | When to Use |
|---|---|---|
| `tax_years` | Lists all supported tax years | First call — verify the target tax year is supported |
| `tax_jurisdictions` | Lists all supported jurisdictions (federal + states) | Check which states are supported |
| `tax_namespaces` | Lists all available tax form namespaces for a jurisdiction/year | Discover what forms/schedules Aiwyn can compute |
| `tax_namespace_schema` | Returns the full input schema for a specific namespace | Get exact field names, types, and constraints for a form |

### 3B. Calculation Tools

| Tool | Purpose | When to Use |
|---|---|---|
| `tax_simple_return` | Returns a minimal template for a basic return | Starting point — see the required structure before gathering inputs |
| `check_tax` | Validates inputs without computing | Pre-validate before running full calculation; catches errors early |
| `calculate_tax` | Computes the full tax return | Core calculation — produces the actual tax liability and all form outputs |

### 3C. Output Tools

| Tool | Purpose | When to Use |
|---|---|---|
| `generate_tax_pdf_tool` | Initiates PDF generation of the computed return | After successful calculate_tax — creates the filing-ready PDF |
| `get_tax_pdf_tool` | Retrieves/polls for the generated PDF | Poll until PDF is ready; returns download URL |

### 3D. Utility Tools

| Tool | Purpose | When to Use |
|---|---|---|
| `generate_uuid_v5` | Generates a deterministic UUID v5 | When Aiwyn requires UUIDs for entity identification |

---

## 4. CAPABILITIES AND LIMITATIONS

### 4A. What Aiwyn CAN Do

- **Federal Form 1040** — Complete individual return calculation
- **Supported state returns** — But only for jurisdictions returned by the live
  `tax_jurisdictions` call for the target tax year
- **Standard and itemized deductions** — Computes optimal choice
- **Capital gains and losses** — Including wash sale adjustments
- **Self-employment tax** — Schedule SE calculations
- **AMT** — Form 6251 calculations
- **Credits** — CTC, EITC, education credits, energy credits, and others supported in its schema
- **Scenario modeling** — Run multiple calculations with different inputs to compare strategies (e.g., MFJ vs. MFS, standard vs. itemized, Roth conversion impact)
- **PDF generation** — IRS-ready PDFs with all forms and schedules
- **Schema discovery** — Query what inputs are accepted and what forms are supported
- **Pre-validation** — Check inputs before computing to catch errors early
- **Deterministic results** — Same inputs always produce the same outputs; auditable

### 4B. What Aiwyn CANNOT Do

- **E-filing** — Aiwyn calculates and generates PDFs but does NOT electronically file returns with the IRS or state agencies. A separate filing method is required (see Section 5).
- **Complex form coverage uncertainty** — While Aiwyn covers the 1040 and major schedules, coverage of less common forms (Form 3520, Form 8938, complex international, etc.) should be verified by checking `tax_namespaces` and `tax_namespace_schema` for the specific year and jurisdiction.
- **Tax advice or strategy** — Aiwyn is a calculator. It does not recommend strategies, identify optimization opportunities, or flag errors. That is the LLM's job.
- **Document reading** — Aiwyn does not read W-2s, 1099s, or other source documents. The agent must extract data from documents and input it into Aiwyn's structured format.
- **Year-over-year comparison** — Each calculation is independent. Cross-year analysis is the LLM's responsibility.
- **Amended returns** — Verify via `tax_namespaces` whether Form 1040-X is supported for your target year.

### 4C. Verify Before Assuming

When in doubt about whether Aiwyn supports a specific form, schedule, or computation:

1. Call `tax_namespaces` for the jurisdiction and year
2. Call `tax_namespace_schema` for the specific namespace
3. If a namespace exists and has the relevant fields, Aiwyn can handle it
4. If a namespace does NOT exist, you must handle that computation manually or note it as a limitation

---

## 5. E-FILING STRATEGY

Aiwyn computes the return and generates PDFs. Filing requires a separate step.

### Filing Options

| Method | Federal Cost | State Cost | Notes |
|---|---|---|---|
| **FreeTaxUSA** | $0 | ~$15/state | Best value for most taxpayers. Import Aiwyn-computed values. |
| **IRS Free File Fillable Forms** | $0 | N/A (federal only) | Bare-bones e-filing directly to IRS. No guidance, no state. Good if you already have the numbers from Aiwyn. |
| **IRS Direct File** | $0 | $0 (where available) | IRS's own filing tool. Limited to simple returns and participating states. |
| **TaxSlayer** | ~$25-$60 | ~$40/state | Multiple tiers. Good balance of features and price. |
| **TurboTax** | $0-$129+ | ~$60/state | Most popular; expensive for complex returns. |
| **H&R Block** | $0-$110+ | ~$40/state | Comparable to TurboTax. In-person option available. |
| **TaxAct** | $0-$70+ | ~$40/state | Budget option with good coverage. |
| **Paper filing** | $0 (plus postage) | $0 (plus postage) | Print Aiwyn PDFs, sign, and mail. Slowest processing. Use certified mail. |

### Recommended Workflow

1. **Aiwyn calculates** the complete federal and state returns
2. **Review the Aiwyn output** for accuracy (the LLM's job — cross-reference with source documents)
3. **Choose a filing method** based on complexity and budget
4. **Enter the Aiwyn-computed values** into the chosen filing software, OR print and mail the Aiwyn PDFs
5. **Cross-verify** the filing software's calculated tax against Aiwyn's calculation — they should match exactly. Any discrepancy indicates an input error.

### Paper Filing Notes

- Aiwyn-generated PDFs can be printed and filed by mail
- Sign and date the return
- Send via USPS Certified Mail (proof of timely filing)
- Federal: Department of the Treasury, Internal Revenue Service (address varies by state — check IRS.gov)
- State: Check state revenue department mailing address
- Include payment voucher (Form 1040-V) if balance due
- Processing takes 6-8 weeks for paper returns

---

## 6. DISCOVERY WORKFLOW

Before calculating a return, discover what Aiwyn supports for the target year.
Use this workflow:

### Step 1: Check Supported Tax Years

```
Call: tax_years
Purpose: Confirm the tax-year key (for example `TY25`) is supported
```

### Step 2: Check Supported Jurisdictions

```
Call: tax_jurisdictions
Parameters: { tax_year: "TY25" }
Purpose: Get list of federal + state jurisdictions available
```

### Step 3: Discover Available Namespaces

```
Call: tax_namespaces
Parameters: { tax_year: "TY25", jurisdiction: "us" }  // federal
Purpose: See all form/schedule namespaces Aiwyn can compute
```

Repeat for the taxpayer's state:
```
Call: tax_namespaces
Parameters: { tax_year: "TY25", jurisdiction: "ca" }  // example: California
```

### Step 4: Get Input Schema for Specific Forms

```
Call: tax_namespace_schema
Parameters: { tax_year: "TY25", namespace: "irs1040" }
Purpose: Get exact field definitions, types, required vs. optional
```

### Step 5: Get Simple Return Template

```
Call: tax_simple_return
Parameters: { tax_year: "TY25" }
Purpose: Get a minimal working input structure to start from
```

For state work, call `tax_simple_return` again with the state code, for example:

```
Call: tax_simple_return
Parameters: { tax_year: "TY25", jurisdiction: "ca" }
Purpose: Get the federal + California workflow and required namespace set
```

**Agent tip:** Run the discovery workflow once at the start of a session and cache
the results mentally. You do not need to rediscover for each calculation.

---

## 7. FULL RETURN CALCULATION WORKFLOW

### Phase 1: Gather All Inputs

Using the intake questionnaire, collect all taxpayer information. Map each piece
of information to Aiwyn's input schema fields (discovered via `tax_namespace_schema`).

**Critical:** Collect ALL information before calling `calculate_tax`. Do not call
it with partial data and try to fill in gaps later.

### Phase 2: Pre-Validate

```
Call: check_tax
Parameters: { complete input payload }
Purpose: Catch errors, missing required fields, and invalid values before computing
```

If `check_tax` returns errors:
- Translate error messages to plain language
- Ask the user for the specific missing or invalid values
- Do NOT fabricate or guess values
- Re-run `check_tax` after corrections

If `check_tax` returns **disqualifications**: STOP immediately. Inform the user of
the disqualification reason. Do not attempt to work around a disqualification.

### Phase 3: Calculate Federal Return

```
Call: calculate_tax
Parameters: { complete input payload, tax_year: "TY25" }  // federal by default
Purpose: Compute the full federal return
```

Save the complete federal output (markdown response) for review and state calculation.

### Phase 4: Calculate State Return (if applicable)

```
Call: calculate_tax
Parameters: { complete input payload, jurisdiction: "ca", tax_year: "TY25" }
Purpose: Compute the state return
```

Note: State calculations extend the federal input using state namespaces. Use the
same overall input payload, include the needed state namespaces, and specify the
state jurisdiction code returned by `tax_jurisdictions`.

### Phase 5: Generate PDF

Only after ALL `calculate_tax` calls are complete:

```
Call: generate_tax_pdf_tool
Parameters: { ... include state jurisdiction if applicable so both federal and state forms are in one PDF }
Purpose: Initiate PDF generation
```

### Phase 6: Retrieve PDF

```
Call: get_tax_pdf_tool
Parameters: { ... reference from generate_tax_pdf_tool }
Purpose: Poll until PDF is ready, then retrieve download URL
```

Poll periodically until the PDF is available. Present the download URL to the user.

### Phase 7: Review and Verify

After receiving the Aiwyn output:

1. **Cross-reference** every major line item against source documents (W-2s, 1099s, K-1s)
2. **Verify** that Aiwyn's computed AGI matches the sum of all income sources
3. **Check** that deductions, credits, and taxes match expectations from the intake
4. **Compare** the effective tax rate to prior years (if available) — significant deviations warrant investigation
5. **Flag** any discrepancies for the taxpayer before proceeding to filing

---

## 8. FORMATTING RULES AND DATA CONVENTIONS

The Aiwyn MCP server has specific formatting requirements. Failure to follow these
will cause errors or incorrect calculations.

### 8A. Value Wrapping

All input values must be wrapped in a `{"value": <val>}` object:

```json
{
  "filing_status": { "value": "married_filing_jointly" },
  "wages": { "value": 150000 },
  "ssn": { "value": "123456789" }
}
```

### 8B. Currency

- All dollar amounts must be **whole-dollar integers** (no cents)
- Round to the nearest dollar
- Do NOT include dollar signs, commas, or decimal points in the value

```json
// Correct:
{ "wages": { "value": 150000 } }

// Incorrect:
{ "wages": { "value": "$150,000.00" } }
{ "wages": { "value": 150000.50 } }
```

### 8C. Social Security Numbers

- Must be a **9-digit string** (no dashes, no spaces)

```json
// Correct:
{ "ssn": { "value": "123456789" } }

// Incorrect:
{ "ssn": { "value": "123-45-6789" } }
{ "ssn": { "value": 123456789 } }  // number, not string
```

### 8D. Dates

- Follow the format specified in the schema (typically YYYY-MM-DD or MM/DD/YYYY)
- Check `tax_namespace_schema` for the exact format expected

### 8E. Enumerations

- Filing status, state codes, and other enums must match Aiwyn's expected values exactly
- Check `tax_namespace_schema` for valid enum values

### 8F. Multiple W-2s

- Always ask the user if they had multiple W-2s
- Each W-2 is a separate entry in the input array
- Do not combine W-2 amounts — Aiwyn needs them separate to correctly handle Social Security wage base, Additional Medicare Tax, and state allocation

### 8G. Never Fabricate Values

**Under no circumstances should you fabricate, guess, or assume input values.**

If a required field is missing:
1. Ask the user for the value in plain language
2. Explain why it is needed
3. If the user does not have the information, explain what document it can be found on
4. Do NOT use placeholder values, zeros (unless truly zero), or estimates

### 8H. One Input at a Time

When gathering information the user does not have readily available:
- Ask for one input at a time
- Wait for the user to respond before asking the next question
- Group related questions when the user clearly has the document in front of them
  (e.g., "From your W-2, I need Boxes 1, 2, 5, 12, and 17")

---

## APPENDIX A: TROUBLESHOOTING

### Tools Not Available

**Symptom:** Aiwyn MCP tools do not appear in the tool list.

**Fixes:**
1. Verify the config is in `~/.claude.json` (not `settings.json` or `.claude/settings.json`)
2. Re-run the installation command: `claude mcp add --transport http --scope user aiwyn-tax https://mcp.columnapi.com/mcp`
3. Restart Claude Code after adding the MCP server
4. Check that the URL is exactly `https://mcp.columnapi.com/mcp` (no trailing slash)

### Calculation Errors

**Symptom:** `calculate_tax` returns errors.

**Fixes:**
1. Run `check_tax` first to isolate which fields have issues
2. Check that values are wrapped in `{"value": <val>}` format
3. Check that currency is whole-dollar integers
4. Check that SSNs are 9-digit strings
5. Check that enums match the schema exactly (use `tax_namespace_schema` to verify)
6. Check that required fields are not missing

### Disqualification

**Symptom:** `check_tax` or `calculate_tax` returns a `"disqualifications"` key.

**Action:** STOP. Do not attempt to fix the input or continue. Inform the user of
the disqualification reason. Common causes:
- Filing status incompatible with claimed credits
- Income thresholds exceeded for specific programs
- Eligibility requirements not met

### PDF Generation Timeout

**Symptom:** `get_tax_pdf_tool` returns "not ready" repeatedly.

**Action:** Wait and retry. PDF generation can take 10-30 seconds. If still not
ready after 60 seconds, regenerate with `generate_tax_pdf_tool`.

---

## APPENDIX B: SCENARIO MODELING WORKFLOW

One of Aiwyn's most valuable uses is comparing different filing strategies. The
approach is:

1. **Baseline calculation** — Compute the return as-is
2. **Alternative scenario** — Change one variable (filing status, deduction method, Roth conversion amount, etc.) and recalculate
3. **Compare** — Present both results side by side with the dollar impact

### Common Scenarios to Model

| Scenario | What to Change | What to Compare |
|---|---|---|
| MFJ vs. MFS | Filing status | Total combined tax liability |
| Standard vs. itemized | Deduction method | Tax liability (usually obvious, but edge cases exist) |
| Roth conversion amount | Add conversion income | Tax bracket impact, future tax savings |
| S-Corp salary levels | W-2 wages vs. distributions | SE tax savings vs. QBI deduction impact |
| Selling appreciated stock | Capital gains amount | Tax on gains vs. portfolio rebalancing benefit |
| Charitable bunching | Donate 2 years' worth in 1 year | Itemize in bunching year, standard in off year |
| Retirement contribution level | IRA/401(k) contribution amount | Tax savings vs. cash flow impact |
| Entity election impact | Sole prop vs. S-Corp | SE tax, payroll costs, QBI deduction |

### Modeling Template

For each scenario, present results as:

```
## Scenario: [Description]

| Item | Baseline | Alternative | Difference |
|---|---|---|---|
| AGI | $X | $Y | +/- $Z |
| Taxable Income | $X | $Y | +/- $Z |
| Federal Tax | $X | $Y | +/- $Z |
| State Tax | $X | $Y | +/- $Z |
| SE Tax | $X | $Y | +/- $Z |
| Total Tax | $X | $Y | +/- $Z |
| Effective Rate | X% | Y% | +/- Z% |

**Recommendation:** [Which option and why]
```

---

*Last updated: Tax Year 2025. Verify Aiwyn's current capabilities via the discovery
workflow — form coverage and features may expand over time.*
