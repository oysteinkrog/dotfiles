# Securities Lending and Substitute Payments

## Overview

Securities lending is a common but poorly understood brokerage practice where your shares are lent to other market participants (typically short sellers or market makers) in exchange for collateral and a fee. When shares are on loan over a dividend record date, the borrower pays a "substitute dividend" (also called a "payment in lieu" or PIL) instead of the actual dividend from the company. This substitute payment receives dramatically worse tax treatment -- ordinary income rates instead of qualified dividend rates -- and many investors do not realize their dividends have been reclassified until they receive their 1099.

All figures and rules reflect the 2025 tax year.

---

## How Securities Lending Works

### The Basic Mechanism

1. **Your broker** identifies shares in your account eligible for lending (typically margin accounts, but some brokers lend from cash accounts with consent)
2. **Borrower** (short seller, market maker, or other institution) borrows your shares
3. **Collateral** is posted -- cash or Treasury securities equal to 100-105% of the share value
4. **Interest/fees** are split between the broker and you (the lender)
5. **When the borrower returns the shares**, the loan terminates

### Why Shares Are Lent

- **Short selling:** Short sellers must borrow shares to sell short
- **Market making:** Designated market makers need shares for settlement
- **Failure to deliver (FTD) resolution:** Covering settlement failures
- **Hedging:** Various hedging strategies require borrowed shares

---

## Payments in Lieu of Dividends (Substitute Payments)

### The Tax Problem

When your shares are on loan on the **record date** for a dividend, you do not receive the actual dividend from the company. Instead, the borrower pays you a "substitute payment" or "payment in lieu of dividends" (PIL) equal to the dividend amount.

**Critical tax difference:**

| Payment Type | Tax Treatment | Maximum Rate |
|---|---|---|
| Qualified dividend (actual) | Preferential rates (section 1(h)) | 20% + 3.8% NIIT = 23.8% |
| Substitute payment (PIL) | Ordinary income | 37% + 3.8% NIIT = 40.8% |

**Spread at top bracket:** 40.8% - 23.8% = **17 percentage points** on each substituted dividend

### IRC Authority

- **IRC section 871(m):** Dividend equivalent payments -- withholding rules for foreign persons on substitute dividends
- **Reg. section 1.861-3(a)(6):** Substitute payments are treated as received from the payor (borrower), not the corporation
- **IRS Publication 550:** "If you receive a substitute payment in lieu of dividends... the substitute payment is not a dividend. It is taxable as ordinary income."

---

## How Substitute Payments Appear on Tax Forms

### Form 1099-MISC Box 8

"Substitute payments in lieu of dividends or interest" -- this is the primary reporting location for PILs. The amount appears as ordinary income, NOT on Form 1099-DIV.

### Form 1099-DIV Reclassification

Some brokers reclassify dividends that were actually PILs directly on the 1099-DIV, reducing the qualified dividend amount (Box 1b) and adding the PIL amount to 1099-MISC. The investor may see a lower qualified dividend figure than expected.

### The Transparency Problem

Most investors never notice the reclassification because:
1. The net amount received is the same (PIL = dividend amount)
2. The reclassification only appears on the 1099, not on account statements
3. Tax software automatically categorizes 1099-MISC Box 8, but the investor may not understand the tax impact

---

## The Interactive Brokers (IB) Problem

### Stock Yield Enhancement Program (SYEP)

Interactive Brokers' SYEP automatically lends shares from customer accounts. Key characteristics:

- **Opt-in program** (customer must enroll), but many active traders do
- IB keeps **50%** of the lending fee, customer receives 50%
- Shares in the program can be lent at any time, including over dividend record dates
- **All dividends on lent shares become PILs** -- ordinary income, not qualified dividends

### Financial Impact Example

```
Portfolio: $500,000 in dividend-paying stocks
Annual dividends: $15,000 (3% yield)
SYEP lending fee income: $800/year (varies widely)

Scenario: 50% of dividends become PILs due to shares being on loan

Without SYEP:
  $15,000 qualified dividends at 23.8%: $3,570 tax

With SYEP:
  $7,500 qualified dividends at 23.8%: $1,785
  $7,500 PILs at 40.8%: $3,060
  Total tax: $4,845
  Lending income: $800 (taxed at 40.8% = $326 net = $474 after tax)
  
  Extra tax on PILs: $4,845 - $3,570 = $1,275
  Net of lending income: $1,275 - $474 = $801 COST
  
Result: SYEP COSTS the investor $801/year net
```

This calculation demonstrates that for dividend-focused portfolios, securities lending programs frequently **cost more in lost tax benefits than they generate in lending fees**.

---

## Short Rebate

### Definition

When a short seller borrows shares, they post cash collateral. The interest earned on that cash collateral is called the **short rebate**. In practice:

- **General collateral** (easy-to-borrow) shares: the short rebate is close to the prevailing interest rate minus a small spread
- **Hard-to-borrow** shares: the short rebate may be negative (the borrower pays the lender above-market rates)

### Tax Treatment

Short rebate income received by the share lender is **ordinary income**, reported on 1099-MISC or as part of the lending agreement proceeds.

---

## Short Dividend Obligation

### IRC section 263(h) -- Payments in Lieu by Short Sellers

When a short seller holds a short position over a dividend record date, they must pay the dividend amount to the share lender. This "short dividend" is:

- **Deductible** by the short seller, but only against **short sale gain** (section 263(h)(2))
- If the short position is held for 45 days or fewer (before or after the ex-dividend date), the payment is treated as a nondeductible personal expense
- For short positions held longer than 45 days, the payment is an itemized deduction (investment expense) subject to 2% AGI floor (pre-TCJA) -- but currently **NOT deductible** as miscellaneous itemized deductions are suspended through 2025

**Practical effect for short sellers:** The dividend obligation on a short position held for less than 46 days around the ex-date is a pure cost with no tax benefit.

---

## Strategies to Manage Substitute Payments

### Strategy 1: Opt Out of Securities Lending Programs

The simplest solution. If your broker offers an opt-in program (like IB's SYEP), decline or disenroll.

**Consideration:** Some brokers (especially those offering "free" trading) may lend shares from margin accounts automatically under the margin agreement. Moving to a cash account eliminates this.

### Strategy 2: Recall Shares Before Ex-Dividend Dates

If enrolled in a lending program, request that your broker recall shares before the ex-dividend date of a dividend payment. Some brokers allow this:

- **Fidelity Fully Paid Lending:** Shares can be recalled at any time
- **Interactive Brokers SYEP:** You can withdraw from the program, but recall timing may not guarantee shares are returned before the record date
- **Schwab:** Does not have a formal retail lending program

### Strategy 3: Segregate Dividend Stocks from Lending Accounts

Hold dividend-paying stocks in accounts that do **not** participate in lending:
- **IRA/401(k):** Dividends in retirement accounts are tax-deferred anyway; PILs vs. qualified dividends makes no difference
- **Cash accounts:** Shares in cash accounts generally cannot be lent (unless you explicitly consent)
- **Non-margin accounts:** Converting from margin to cash eliminates lending

Hold growth/non-dividend stocks in the lending-eligible margin account to earn lending fees without PIL tax cost.

### Strategy 4: Track PILs Separately for Accurate Tax Planning

Monitor your 1099-MISC Box 8 and compare against expected dividends. If PILs are significant:
1. Calculate the tax cost (ordinary rate - qualified rate) x PIL amount
2. Compare against lending income received
3. If net negative, disenroll from lending

### Strategy 5: Use Tax-Loss Harvesting to Offset PIL Income

PILs are ordinary income. If you have capital losses, remember that only $3,000 of net capital losses can offset ordinary income per year. However, if you have other ordinary income deductions (business losses, rental losses under exception), those can offset PIL income dollar-for-dollar.

---

## IRC section 1058 -- Tax-Free Securities Lending

### Requirements for Tax-Free Treatment

Under section 1058, a securities lending arrangement is NOT treated as a taxable disposition if ALL of the following are met:

1. The borrower must return **identical securities** (same issuer, same class, same number of shares)
2. The agreement must require return of identical securities, not just equivalent value
3. The lender must have the right to **terminate the loan** on not more than 5 business days' notice
4. The borrower must make payments to the lender equivalent to all interest, dividends, and other distributions during the loan period
5. The loan must not reduce the lender's risk of loss or opportunity for gain

**If these conditions are met:** The loan is not a sale, and lending fees are ordinary income. This is the basis for most brokerage securities lending programs.

**If conditions are NOT met:** The transfer may be treated as a sale, triggering gain recognition (section 1001).

### Voting Rights

When shares are on loan, the **borrower** (not the lender) has voting rights. Some lending agreements allow the lender to recall shares for important votes.

---

## Manufactured Payment Rules

### What Is a Manufactured Payment?

A manufactured payment occurs in several contexts:
1. **Short seller pays dividend equivalent** to share lender
2. **Securities borrower pays substitute dividend** to share lender
3. **Counterparty in swap agreement** pays dividend-like amount

### Tax Treatment Matrix

| Payer | Recipient | Payment Character |
|---|---|---|
| Short seller | Share lender (via broker) | Ordinary income to recipient; section 263(h) to payer |
| Securities borrower | Share lender | Ordinary income (PIL) to recipient |
| Swap counterparty | Swap holder | Ordinary income per section 871(m) |

---

## Brokerage Comparison

| Broker | Lending Program | Type | PIL Risk | Notes |
|---|---|---|---|---|
| Interactive Brokers | Stock Yield Enhancement | Opt-in | HIGH | Aggressive lending; significant PIL exposure |
| Fidelity | Fully Paid Lending | Opt-in | MODERATE | Can recall shares; better control |
| Charles Schwab | No formal retail program | N/A | LOW | Margin account lending per agreement |
| E*TRADE (Morgan Stanley) | Fully Paid Lending | Opt-in | MODERATE | Available for eligible accounts |
| Robinhood | Securities lending (built-in) | Automatic for margin | HIGH | Shares lent from margin accounts; cash account safer |
| TD Ameritrade (Schwab) | Fully Paid Lending | Opt-in | MODERATE | Being merged into Schwab platform |
| Vanguard | No lending program | N/A | NONE | Vanguard does not lend retail client shares |

---

## Worked Example: Full Tax Impact Analysis

### Investor Profile

- Filing status: MFJ
- Taxable income: $500,000 (37% ordinary bracket, 20% LTCG bracket)
- Subject to 3.8% NIIT on all investment income
- Portfolio: $1,000,000 in dividend stocks, 2.5% yield = $25,000/year in dividends

### Scenario A: No Securities Lending

```
$25,000 qualified dividends
Tax: $25,000 x 23.8% = $5,950
```

### Scenario B: 50% of Dividends Become PILs

```
$12,500 qualified dividends: $12,500 x 23.8% = $2,975
$12,500 substitute payments: $12,500 x 40.8% = $5,100
Total tax: $8,075

Lending fee income: $2,500 (0.25% of portfolio)
Tax on lending income: $2,500 x 40.8% = $1,020
Net lending income: $1,480

Additional tax from PILs: $8,075 - $5,950 = $2,125
Net cost of lending program: $2,125 - $1,480 = $645/year
```

### Scenario C: 100% of Dividends Become PILs

```
$25,000 substitute payments: $25,000 x 40.8% = $10,200
Total tax: $10,200

Lending fee income: $5,000 (0.50% of portfolio, high lending)
Tax on lending income: $5,000 x 40.8% = $2,040
Net lending income: $2,960

Additional tax from PILs: $10,200 - $5,950 = $4,250
Net cost of lending program: $4,250 - $2,960 = $1,290/year
```

### Break-Even Analysis

For securities lending to be net beneficial, the **after-tax lending fee income** must exceed the **PIL tax penalty**:

```
PIL tax penalty = PIL amount x (ordinary rate - qualified rate)
                = PIL amount x (40.8% - 23.8%)
                = PIL amount x 17%

Break-even lending fee (pre-tax) = PIL tax penalty / (1 - ordinary rate)
                                 = (PIL amount x 17%) / (1 - 40.8%)
                                 = PIL amount x 28.7%
```

In other words, lending fees must be approximately **28.7% of the PIL amount** just to break even. Since PILs typically equal 100% of the dividend, and lending fees are typically 0.1-1% of the share value (much less than the dividend yield), **securities lending almost never breaks even for dividend-focused portfolios at high tax brackets**.

---

## Key Regulatory References

- **IRC section 1058:** Tax-free securities lending requirements
- **IRC section 263(h):** Short sale dividend deduction limitations
- **IRC section 871(m):** Dividend equivalent payments (substitute dividends)
- **IRC section 1(h):** Preferential rates for qualified dividends
- **Reg. section 1.861-3(a)(6):** Source and character of substitute payments
- **Reg. section 1.1058-1:** Securities lending tax treatment
- **IRS Publication 550:** Investment Income and Expenses (substitute payments guidance)
- **Revenue Ruling 60-177:** Character of payments in lieu of dividends
