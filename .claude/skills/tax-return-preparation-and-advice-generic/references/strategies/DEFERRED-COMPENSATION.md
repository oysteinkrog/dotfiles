# DEFERRED COMPENSATION — Advanced Strategies

## Overview

Deferred compensation encompasses arrangements where an employee or service provider receives pay in a tax year after the year in which the services are performed. The tax rules vary dramatically depending on the type of arrangement — from the punitive penalties of ss409A for nonqualified plans to the penalty-free withdrawals of ss457(b) for government employees. This guide covers the full spectrum.

---

## ss409A — NONQUALIFIED DEFERRED COMPENSATION

### Background

Section 409A, enacted by the American Jobs Creation Act of 2004, imposes strict rules on nonqualified deferred compensation plans (NQDCs). Violations result in immediate taxation, a 20% penalty tax, and an interest charge — making compliance critical.

### What Is Covered

ss409A applies to any plan that provides for the deferral of compensation, unless an exemption applies. This includes:
- Supplemental Executive Retirement Plans (SERPs)
- Deferred bonus arrangements
- Phantom stock and stock appreciation rights (if not settled immediately)
- Separation pay arrangements (above certain thresholds)
- Reimbursement arrangements with multi-year carryovers
- Discounted stock options and stock appreciation rights

### Key Exemptions from ss409A

| Exemption | Authority | Conditions |
|---|---|---|
| Short-term deferral | Reg. ss1.409A-1(b)(4) | Payment by the 15th day of the 3rd month after the year in which the right vests (no longer subject to substantial risk of forfeiture) |
| Stock options at FMV | Reg. ss1.409A-1(b)(5) | ISO or NSO with exercise price >= FMV at grant. Requires 409A-compliant valuation (see below). |
| Separation pay | Reg. ss1.409A-1(b)(9) | Involuntary separation pay not exceeding 2x lesser of (a) annual compensation or (b) ss401(a)(17) limit ($345,000 in 2025), paid within 2 years |
| Foreign plans | Reg. ss1.409A-1(b)(8) | Plans covering nonresident aliens for services performed outside the US |

### Timing of Deferral Elections

**Initial deferral election** must be made BEFORE the beginning of the year in which the services are performed:
- New plan: election within 30 days of initial eligibility (for first year only)
- Performance-based compensation: election by June 30 of the performance year (if performance period is at least 12 months)
- Subsequent year deferrals: election by December 31 of the PRIOR year

**Once made, elections are generally irrevocable** for that year.

### Permissible Distribution Triggers (ss409A(a)(2))

Deferred compensation can ONLY be distributed upon one of six events:
1. **Separation from service** (with 6-month delay for "specified employees" of public companies)
2. **Disability** (as defined in ss409A(a)(2)(C))
3. **Death**
4. **Specified time or fixed schedule** (elected at time of deferral)
5. **Change in control** (as defined in Reg. ss1.409A-3(i)(5) — acquisition, asset sale, or change in board)
6. **Unforeseeable emergency** (severe financial hardship — Reg. ss1.409A-3(i)(3))

### The 6-Month Delay Rule

For "specified employees" of publicly traded companies (generally, the top 50 highest-paid officers), distributions triggered by separation from service must be delayed for 6 months after separation. This prevents executives from using separation as an acceleration trigger.

### 409A Penalties for Violations

If a plan fails to comply with ss409A in form or operation:
1. **Immediate income inclusion**: ALL deferred compensation is included in income in the year of the failure
2. **20% additional tax**: On the amount included (ss409A(a)(1)(B)(i)(II))
3. **Premium interest**: Interest at the underpayment rate + 1%, calculated from the year the compensation was first deferred (ss409A(a)(1)(B)(i)(I))

**Worked Example — 409A Violation**:
- Executive deferred $500K in 2020, $500K in 2021, $500K in 2022
- Plan violation discovered in 2025
- Total vested deferred amount: $1,500,000 (plus investment gains)
- Included in 2025 income: $1,500,000+
- 20% penalty: $300,000+
- Interest charge: ~$75,000 (premium interest from 2020-2025)
- Total additional cost: ~$375,000+ PLUS the regular income tax on $1.5M

### Valuation Requirements for Stock Options

Stock options granted at "fair market value" are exempt from 409A. But FMV must be determined using a "reasonable" method:
- **Public companies**: Closing price on grant date, average of high/low, 30-day trailing average
- **Private companies**: Must use a "reasonable application of a reasonable valuation method" — the three safe harbors per Reg. ss1.409A-1(b)(5)(iv)(B):
  1. Independent appraisal (within 12 months of grant)
  2. Formula-based valuation (for non-publicly traded stock, applied consistently)
  3. Start-up company valuation (company less than 10 years old, no public trading, reasonable analysis by qualified person)

The infamous "409A valuation" for startups — typically conducted by a third-party valuation firm producing a report used to set option strike prices.

---

## SUPPLEMENTAL EXECUTIVE RETIREMENT PLANS (SERPs)

### Structure

A SERP is an unfunded, unsecured promise by the employer to pay additional retirement benefits. SERPs are used when qualified plan limits (ss401(a)(17) compensation cap: $345,000; ss415(c) annual addition limit: $70,000) are insufficient for highly compensated executives.

### Tax Treatment

- **Employer**: No deduction until amounts are actually paid to the executive (ss404(a)(5))
- **Executive**: No income until amounts are actually or constructively received (ss451)
- **FICA**: Subject to FICA tax when the amounts vest (or when services are performed, if no substantial risk of forfeiture) — per ss3121(v)(2)

### Risk: Employer Insolvency

SERP benefits are general unsecured obligations of the employer. If the employer becomes insolvent, the executive is a general creditor — and may receive nothing. This is the fundamental trade-off: tax deferral comes at the cost of credit risk.

---

## RABBI TRUSTS

### Structure (Rev. Proc. 92-64)

A rabbi trust is an irrevocable trust established by the employer to hold assets earmarked for deferred compensation. Named after the first IRS ruling approving this structure for a rabbi's deferred compensation (PLR 8113107).

### Key Features

- **Assets are subject to employer's creditors** in the event of insolvency or bankruptcy
- Because assets remain at risk, the executive is NOT treated as having received the compensation — deferral is preserved
- Trust is a grantor trust of the EMPLOYER — employer pays income tax on trust earnings
- Executive recognizes income only upon actual distribution

### The Tax Paradox

The employer gets no deduction until payment, pays tax on trust earnings, and the executive has credit risk. The only advantage is the psychological comfort that assets are segregated (and the employer cannot unilaterally revoke the arrangement).

---

## SECULAR TRUSTS

### Structure

A secular trust is an irrevocable trust where the assets are NOT subject to employer creditors — providing genuine security to the executive.

### Tax Consequences

Because the assets are secured, the economic benefit doctrine applies:
- **Executive**: Taxed immediately when amounts are contributed to the trust (constructive receipt/economic benefit)
- **Employer**: Deduction when amounts are contributed (matching principle)
- **Trust earnings**: Taxed to the executive (or trust) as earned

Secular trusts essentially convert deferred compensation into current compensation with creditor protection — losing the tax deferral benefit but gaining security.

---

## ss457(b) — GOVERNMENT EMPLOYEE PLANS

### The Hidden Gem

ss457(b) plans for state and local government employees are among the most overlooked retirement vehicles. Key advantages:

1. **No 10% early withdrawal penalty**: Unlike 401(k) and IRA, distributions from governmental 457(b) plans are NOT subject to the 10% early withdrawal penalty regardless of age (ss72(t)(9)). This makes 457(b) the ONLY tax-deferred plan allowing penalty-free access before 59.5.

2. **Separate contribution limit**: The 457(b) limit ($23,500 in 2025, $31,000 if age 50+) is IN ADDITION to the 401(k)/403(b) limit. A government employee with access to both can defer:
   - $23,500 to 457(b) + $23,500 to 401(k)/403(b) = **$47,000/year** (plus catch-up)

3. **Special 3-year catch-up**: In the 3 years before "normal retirement age" (as defined in the plan), the participant can defer the LESSER of (a) twice the annual limit ($47,000) or (b) the annual limit plus underutilized amounts from prior years. This is IN ADDITION to the age-50 catch-up (but cannot use BOTH the 3-year catch-up and age-50 catch-up in the same year).

### Governmental vs Non-Governmental 457(b)

| Feature | Governmental 457(b) | Non-Governmental 457(b) |
|---|---|---|
| Rollover to IRA/401(k) | YES | NO |
| Trust required | YES (assets held in trust) | NO (unfunded promise) |
| Early withdrawal penalty | NONE | NONE |
| Subject to employer creditors | NO | YES |
| Eligible participants | All employees | "Top hat" group only |

---

## ss457(f) — NON-PROFIT "TOP HAT" PLANS

### Structure

ss457(f) plans are used by tax-exempt organizations (hospitals, universities, nonprofits) to provide deferred compensation to key employees. Unlike 457(b), there is NO annual contribution limit.

### Tax Treatment

Amounts are taxed when there is NO "substantial risk of forfeiture" — typically when the executive vests:
- If the executive must work for 5 years to vest: taxation occurs at the 5-year mark
- The ENTIRE vested amount is ordinary income in the year of vesting (not the year of payment)
- This can create a massive one-year income spike

### Planning Strategies

- **Rolling risk of forfeiture**: Structure vesting in tranches (e.g., 20% per year over 5 years) to spread income recognition
- **Performance-based vesting**: Tie vesting to performance metrics that create genuine risk of forfeiture
- **Coordinate with other income**: Time vesting events to years with lower other income (sabbatical, transition years)

---

## STOCK APPRECIATION RIGHTS (SARs) AND PHANTOM STOCK

### SARs

A SAR gives the holder the right to receive the increase in value of a specified number of shares over a base price, paid in cash or stock:
- **Settled in stock**: Typically NOT subject to ss409A if the base price equals FMV at grant
- **Settled in cash**: Generally subject to ss409A (must comply with all 409A requirements)
- **Tax at exercise**: Ordinary income on the spread (FMV - base price)

### Phantom Stock

Phantom stock units entitle the holder to a cash payment equal to the value of a specified number of shares (and often dividends) at a future date:
- Subject to ss409A (it is deferred compensation by definition)
- Must meet all 409A election and distribution timing requirements
- Taxed as ordinary income upon distribution
- No capital gains treatment (it's compensation, not stock)

### Phantom Stock vs Restricted Stock Units (RSUs)

| Feature | Phantom Stock | RSUs |
|---|---|---|
| Settled in | Cash | Actual stock |
| ss409A applies | Yes | Often exempt (settled at vesting = short-term deferral) |
| Dilutive to shareholders | No | Yes |
| Capital gains potential | No | Yes (post-vesting appreciation) |
| ss83(b) election | Not applicable | Not applicable (RSUs, unlike restricted stock, cannot have 83(b)) |

---

## ss83(b) ELECTION FOR RESTRICTED PROPERTY

### When to Elect

The ss83(b) election is available when a taxpayer receives property (typically stock) that is subject to a substantial risk of forfeiture (e.g., vesting). By electing:

- **Immediate taxation**: Pay ordinary income tax on the FMV at grant (minus any amount paid), even though the stock hasn't vested
- **Future appreciation**: Taxed as capital gain (long-term if held 1+ year after grant)
- **Forfeiture risk**: If the stock is forfeited (e.g., employee leaves before vesting), NO deduction is allowed for the tax previously paid

### When ss83(b) Makes Sense

| Scenario | Elect ss83(b)? | Reason |
|---|---|---|
| Early-stage startup, stock worth $0.001/share | **YES** | Negligible tax now, all future gain is capital gain |
| Mature company, stock worth $50/share, 4-year vest | **Maybe** | Significant upfront tax, but converts future appreciation to capital gain |
| High forfeiture risk (executive may leave) | **NO** | Risk of paying tax on stock that's given back |
| Stock has no upside potential | **NO** | No benefit to accelerating taxation |

### Worked Example

- Employee receives 100,000 shares of startup stock at $0.10/share, 4-year vesting
- **With ss83(b)**: Pay ordinary income tax on $10,000 (100K x $0.10). If stock reaches $50/share and is sold after 5 years: $4,990,000 taxed as LTCG at 20% = $998,000 tax. Total tax: $1,001,500 (including initial ~$3,500 ordinary tax).
- **Without ss83(b)**: At each vesting date, ordinary income on FMV at that time. If stock is $50/share when fully vested: $5,000,000 ordinary income taxed at 37% = $1,850,000. Future appreciation also ordinary until sold. Total tax: significantly higher.
- **Savings from ss83(b)**: ~$850,000+

### Filing Requirements

- Must be filed with the IRS within **30 days** of the property transfer
- Send to the IRS Service Center where the taxpayer files their return
- Also provide a copy to the employer
- Attach a copy to the taxpayer's income tax return for the year
- **No extensions, no exceptions** — a late filing is no filing

---

## STATE TAX CONSIDERATIONS

### California's Deferred Compensation Sourcing

California taxes deferred compensation based on the ratio of California service to total service during the period the compensation was earned — regardless of where the taxpayer resides when the compensation is received (Cal. Rev. & Tax. Code ss17041, FTB Publication 1005).

**Worked Example**:
- Executive works 20 years for company: 15 years in CA, 5 years in TX
- Retires to FL (no income tax)
- Receives $2M NQDC distribution
- CA taxes: $2M x (15/20) = $1,500,000 x 13.3% = $199,500 CA tax
- Even though the executive lived in FL when receiving the distribution

### Other State Issues

- **New York**: Similar source-based taxation for NQDC attributable to NY services
- **New Jersey**: Subject to NJ income tax if earned during NJ employment period
- **Multi-state sourcing**: Particularly complex for executives who worked in multiple states — must apportion based on service years in each state
- **Section 457(b)**: Governmental 457(b) distributions are generally taxable only in the state of residence at the time of distribution (not the state where services were performed), per 4 U.S.C. ss114

---

## PLANNING STRATEGIES

### Deferral vs Acceleration Decision Matrix

| Factor | Favors Deferral | Favors Current Taxation |
|---|---|---|
| Expected future tax rate | Lower in retirement | Higher rates expected (TCJA sunset?) |
| Employer credit risk | Low risk | High risk (defer less) |
| Investment returns | Trust earns higher returns | Personal investment preferred |
| State tax | Moving to no-tax state | Staying in high-tax state |
| Liquidity needs | None near-term | Need access to funds |
| ss409A complexity | Simple plan | Compliance cost not worth it |

### The "Bridge" Strategy for Early Retirees

For executives retiring before 59.5:
1. Defer enough NQDC to bridge from retirement age to 59.5
2. Structure distributions as "specified date" payments under 409A
3. Payments start at retirement, end at 59.5
4. Then switch to 401(k)/IRA distributions
5. If the executive also has 457(b), access that FIRST (no early withdrawal penalty)

### NQDC + Roth Conversion Coordination

In years when NQDC elections reduce current-year income, consider Roth conversions to fill the bracket space:
- Executive defers $500K of bonus into NQDC
- This creates $500K of "bracket space" that would otherwise be at 37%
- Convert $500K of Traditional IRA to Roth IRA
- Fill the same bracket — net effect: tax-free growth in Roth instead of taxable growth in Traditional

---

## KEY TAKEAWAYS

1. **ss409A compliance is non-negotiable** — the penalties (20% + interest from original deferral year) are devastating
2. **Deferral elections must be made BEFORE the year of service** — no retroactive deferrals
3. **Only six distribution triggers** are permitted — plan accordingly
4. **ss457(b) for government employees is uniquely powerful** — no 10% penalty, separate contribution limit
5. **ss83(b) within 30 days** — the most time-sensitive election in tax law
6. **Rabbi trusts provide comfort but NOT security** — assets remain at risk to employer creditors
7. **California taxes based on where services were performed**, not where you live when paid
8. **NQDC bracket space can be filled with Roth conversions** — coordinate strategies across all compensation types
9. **Stock options must be granted at FMV** to avoid 409A — get a proper 409A valuation
10. **Early retirement planning**: 457(b) first (no penalty), then NQDC bridge, then qualified plans at 59.5
