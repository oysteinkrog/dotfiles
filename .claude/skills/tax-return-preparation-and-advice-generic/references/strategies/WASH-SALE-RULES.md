# Wash Sale Rules -- Definitive Guide

## Overview

IRC section 1091 disallows the deduction of a loss on the sale or other disposition of stock or securities if, within 30 days before or 30 days after the sale, the taxpayer acquires (or enters into a contract or option to acquire) "substantially identical" stock or securities. The disallowed loss is not permanently lost -- it is added to the basis of the replacement security -- but the timing impact can be severe, especially at year-end when planned tax-loss harvesting is defeated.

All figures and rules reflect the 2025 tax year (applicable to 2025 returns filed in 2026).

---

## The 61-Day Window

### Statutory Framework (IRC section 1091(a))

The wash sale period is a 61-day window:

```
30 days BEFORE sale  +  day of sale  +  30 days AFTER sale = 61 calendar days
```

**Example:**
- You sell Stock X at a loss on **March 15**
- Wash sale window: **February 13 through April 14** (inclusive)
- Any acquisition of substantially identical securities within this window triggers the wash sale rule

### Key Dates for Calendar-Day Counting

Calendar days, not business/trading days, control. Weekends and holidays count toward the 30-day period.

| Sale Date | Window Opens | Window Closes |
|---|---|---|
| Jan 15 | Dec 16 (prior year) | Feb 14 |
| Jun 30 | May 31 | Jul 30 |
| Nov 30 | Oct 31 | Dec 30 |
| Dec 15 | Nov 15 | Jan 14 (next year) |

---

## What Triggers a Wash Sale

### Direct Repurchases

Buying the **same** stock or security within the 61-day window. This is the most straightforward trigger.

**Example:** Sell 100 shares of AAPL at a $5,000 loss on March 1. Buy 100 shares of AAPL on March 20. The $5,000 loss is disallowed.

### Call Options on the Same Stock

Purchasing a call option on a stock is treated as acquiring a substantially identical security. Selling a put option (which may result in acquiring the stock) can also trigger the rule.

- **Buy call on same stock:** YES, triggers wash sale (Rev. Rul. 56-602)
- **Sell (write) deep-in-the-money put on same stock:** likely triggers wash sale (substance over form; IRS has argued this aggressively)
- **Sell (write) far-out-of-the-money put:** generally NOT a wash sale (but no bright-line test)

### Spouse's Accounts

Under IRC section 1091(a), the wash sale rule applies to acquisitions by the taxpayer's **spouse** as well. If you sell at a loss and your spouse buys the same security within the window, your loss is disallowed.

**Case law:** *Bedrosian v. Commissioner*, T.C. Memo. 1979-200 -- confirmed that purchases by a spouse in their own account triggered wash sale rules for the selling spouse. The court looked at the economic unity of the marital unit.

### IRA and Retirement Account Purchases

**Critical trap:** If you sell stock at a loss in your taxable brokerage account and buy the same stock in your IRA (Traditional or Roth) within 30 days, the wash sale rule is triggered. However, unlike a taxable-to-taxable wash sale, the disallowed loss **cannot** be added to the IRA's basis -- the loss is **permanently destroyed**.

- **Rev. Rul. 2008-5:** Confirmed that purchasing replacement shares in an IRA triggers the wash sale rule, and the basis adjustment does not apply because the IRA is tax-deferred.
- This applies to all retirement accounts: Traditional IRA, Roth IRA, 401(k), 403(b), etc.
- **Strategy:** NEVER buy a security in a retirement account within 30 days of selling it at a loss in a taxable account.

### Reinvested Dividends

If you sell a mutual fund at a loss and have automatic dividend reinvestment enabled, the reinvested dividends count as a purchase of substantially identical securities. Even a small $50 reinvested dividend can trigger a wash sale on the entire position.

**Planning tip:** Turn off automatic reinvestment at least 31 days before selling a fund at a loss.

### Mutual Fund Capital Gain Distributions

Selling a mutual fund at a loss within 30 days of receiving (and reinvesting) a capital gain distribution triggers a wash sale for the portion attributable to the reinvested distribution.

---

## What Does NOT Trigger a Wash Sale

### Different Companies

Selling Stock A (Coca-Cola) and buying Stock B (PepsiCo) is NOT a wash sale, even though both are in the same industry. The "substantially identical" test looks at the specific security, not the economic exposure.

### Different Index Funds Tracking Different Indices

Selling an S&P 500 index fund and buying a Total Stock Market index fund is generally NOT a wash sale because:
- They track different indices (500 stocks vs. ~4,000 stocks)
- Different composition and weighting
- The IRS has not issued definitive guidance, but tax practitioners widely regard these as different enough

However, selling one S&P 500 fund and buying another S&P 500 fund (even from a different provider) is likely a wash sale because the portfolios are nearly identical.

### Selling Stock and Buying Options on a DIFFERENT Stock

Selling shares of MSFT at a loss and buying call options on GOOG is not a wash sale -- different underlying securities.

### Selling Bonds with Different Issuers, Rates, or Maturities

Treasury bonds with different maturity dates and coupon rates are generally not substantially identical, even if issued by the same entity.

---

## The "Substantially Identical" Test

There is no statutory definition of "substantially identical." The IRS and courts apply a facts-and-circumstances test.

### Clear YES -- Substantially Identical

| Scenario | Wash Sale? | Authority |
|---|---|---|
| Same stock, same company | YES | IRC section 1091(a) |
| Same bond, same issuer/terms | YES | Reg. section 1.1091-1(a) |
| Call option on same stock you sold | YES | Rev. Rul. 56-602 |
| Convertible bond for stock of same company | YES (if conversion terms make it essentially the stock) | Rev. Rul. 77-201 |
| Same mutual fund, same fund company | YES | IRS Pub. 550 |

### Gray Area -- Maybe Substantially Identical

| Scenario | Wash Sale? | Analysis |
|---|---|---|
| Different share classes of same fund (Investor vs. Admiral) | Very likely YES | Same portfolio, same manager, same strategy |
| Mutual fund vs. ETF tracking same index | Likely YES | IRS has not ruled definitively, but practitioners treat as wash sale risk |
| Preferred stock vs. common stock of same company | Depends | If preferred is convertible and closely tracks common, likely yes |
| Two S&P 500 funds from different providers | Likely YES | Same index, nearly identical holdings |

### Clear NO -- Not Substantially Identical

| Scenario | Wash Sale? | Authority |
|---|---|---|
| Stocks of different companies | NO | Different securities |
| S&P 500 fund vs. Total Market fund | NO | Different indices |
| S&P 500 fund vs. Russell 2000 fund | NO | Completely different compositions |
| Bitcoin vs. Ethereum | NO | Different assets (and crypto exempt; see below) |
| Stock vs. bond of same company | Generally NO | Different security types |
| US Treasury vs. corporate bond | NO | Different issuers |

---

## Cryptocurrency Exception (As of 2025)

### IRC section 1091 Does NOT Apply to Cryptocurrency

IRC section 1091 applies to "stock or securities." Cryptocurrency is classified as "property" under IRS Notice 2014-21, not as a "stock or security." Therefore, wash sale rules **do not apply** to crypto as of 2025.

**Practical impact:** You can sell BTC at a loss and immediately repurchase BTC, claiming the full loss deduction. This makes crypto uniquely advantageous for tax-loss harvesting.

### Proposed Legislation -- Watch Carefully

Section 138155 of various proposed Build Back Better / budget reconciliation bills would have extended wash sale rules to digital assets. As of 2025, no such provision has been enacted into law. If Congress extends section 1091 to include "digital assets" or "specified assets," this advantage disappears.

**Strategy for 2025:** Aggressively harvest crypto losses before any legislative change takes effect. Harvest losses on down days and immediately repurchase -- perfectly legal today.

### NFTs and Other Digital Assets

Same analysis -- NFTs, tokenized assets, and other digital property are not "stock or securities" under current law. Wash sale rules do not apply.

---

## Basis Adjustment Mechanics

### How the Disallowed Loss Transfers

When a wash sale is triggered, the disallowed loss is **added to the cost basis** of the replacement security. This ensures the loss is not permanently forfeited (except in the IRA scenario) -- it is merely deferred.

**Worked Example:**

```
Step 1: Buy 100 shares of XYZ at $50/share        Basis: $5,000
Step 2: Sell 100 shares of XYZ at $30/share        Proceeds: $3,000
         Loss: $2,000 (DISALLOWED -- wash sale)
Step 3: Buy 100 shares of XYZ at $32/share (within 30 days)
         Unadjusted basis: $3,200
         Add disallowed loss: +$2,000
         Adjusted basis: $5,200

Step 4: Later sell at $55/share                    Proceeds: $5,500
         Gain = $5,500 - $5,200 = $300
         (Without wash sale, you'd have: $2,000 loss + $2,300 gain = net $300 gain)
```

The economic result is the same -- you just cannot take the $2,000 loss in the year of the wash sale.

### Holding Period Tacking

The holding period of the **original** shares tacks onto the replacement shares. If you held the original shares for 11 months (short-term), and the wash sale triggers, the replacement shares' holding period starts from the original purchase date, not the replacement purchase date.

**IRC section 1223(4):** The replacement property includes the holding period of the exchanged property.

This can be beneficial: if your original shares were held over 12 months (long-term), the replacement shares inherit that long-term status for determining capital gain rates on eventual sale.

---

## Multiple Lot Wash Sales

### Partial Wash Sales

If you sell 100 shares at a loss but only repurchase 60 shares within the window, only 60% of the loss is disallowed. The remaining 40% is deductible.

**Example:**
```
Sell 100 shares at $20 loss/share = $2,000 total loss
Repurchase 60 shares within 30 days
Disallowed loss: 60/100 x $2,000 = $1,200
Allowable loss: 40/100 x $2,000 = $800
Basis adjustment to 60 new shares: $1,200 / 60 = $20/share added to each
```

### Ordering Rules

When selling shares from multiple lots at different prices, the IRS applies a **first-in, first-out (FIFO)** ordering unless the taxpayer specifically identifies lots (Reg. section 1.1012-1(c)).

If you sell multiple lots and repurchase fewer shares, the wash sale applies to the **earliest** loss shares sold, matched against the first replacement shares acquired.

### Multiple Purchases in the Window

If you make multiple purchases within the wash sale window, each purchase is matched against the loss shares in chronological order. The first purchase absorbs losses first.

---

## Wash Sales Across Accounts

### The Cross-Account Rule

Wash sale rules apply across **all** accounts you control:
- Taxable brokerage at Fidelity + taxable brokerage at Schwab
- Taxable brokerage + IRA
- Taxable brokerage + 401(k)
- Your account + spouse's account
- Individual account + joint account

### The IRA Trap (Permanent Loss Destruction)

| Replacement Account | Loss Treatment |
|---|---|
| Another taxable account | Loss added to replacement basis (deferred) |
| Traditional IRA | Loss permanently destroyed (no basis adjustment possible) |
| Roth IRA | Loss permanently destroyed |
| 401(k) | Loss permanently destroyed |
| Spouse's IRA | Loss permanently destroyed |

**Rev. Rul. 2008-5** confirmed this devastating result. There is no mechanism to add basis to an IRA account, so the disallowed loss simply evaporates.

---

## Broker Reporting -- What 1099-B Shows and What It Misses

### What Brokers Report

Form 1099-B, Box 1g: "Wash sale loss disallowed" -- shows the amount of loss disallowed due to wash sales.

Brokers adjust the basis of replacement securities on the 1099-B to reflect the added disallowed loss.

### Critical Limitation: Single-Broker Tracking Only

Brokers only track wash sales **within their own accounts**. They have no visibility into:
- Your accounts at other brokers
- Your spouse's accounts (at any broker)
- Your IRA/401(k) at another custodian
- Crypto exchanges

**Your responsibility:** You must identify and report cross-broker wash sales yourself. Failure to do so is technically tax fraud if it results in claiming a disallowed loss.

### Reconciliation Requirement

Every year, compare all 1099-B forms across brokers and reconcile:
1. Identify all loss sales across all accounts
2. Check for matching purchases in ANY account within the 61-day window
3. If cross-broker wash sale found, add Code "W" to Form 8949 and adjust

---

## Tax-Loss Harvesting Strategies That Avoid Wash Sales

### Strategy 1: Swap to Similar-But-Not-Identical

Sell the losing position and immediately purchase a similar but not substantially identical security.

| Sell | Buy Instead | Notes |
|---|---|---|
| Vanguard S&P 500 ETF (VOO) | Vanguard Total Stock Market ETF (VTI) | Different index |
| iShares Core S&P 500 (IVV) | Schwab U.S. Broad Market (SCHB) | Different index |
| Individual stock (AAPL) | Technology sector ETF (XLK) | Not substantially identical |
| MSCI Emerging Markets ETF | FTSE Emerging Markets ETF | Gray area -- different index, different countries |
| Bond fund (BND) | Different bond fund (AGG) | Different indices, safe swap |

### Strategy 2: The "Doubling Up" Strategy

Buy replacement shares FIRST, wait 31 calendar days, THEN sell the original loss shares.

**Worked Timeline:**
```
Day 0 (Feb 1):    Own 100 shares XYZ at $50 basis (currently at $30)
Day 0 (Feb 1):    Buy additional 100 shares XYZ at $30
Day 31 (Mar 4):   Sell the ORIGINAL 100 shares at $30 (or wherever price is)
                   Loss = $50 - $30 = $20/share = $2,000 loss
                   No wash sale -- repurchase was >30 days before sale
```

**Advantage:** You maintain market exposure throughout (you own 200 shares for 31 days, then 100 shares). You are never out of the market.

**Risk:** You have double the position for 31 days, increasing exposure. If the stock drops further, your loss is larger on the doubled position.

### Strategy 3: Year-End Planning

**Option A -- Early December Sale:**
Sell losing positions before December 1. The 30-day post-sale window ends before December 31, so you can repurchase the same security starting January 1 of the new year.

```
Sell: November 28
Window ends: December 28
Safe to repurchase: December 29
```

**Option B -- Late December Sale with January Repurchase:**
Sell in late December and wait until late January to repurchase.

```
Sell: December 20
Window ends: January 19
Safe to repurchase: January 20
```

**WARNING:** If you sell December 20 and repurchase January 5, the wash sale rule disallows the loss on your current-year return, even though the repurchase is in the next calendar year. The 30-day window does not respect year-end boundaries.

---

## Short Sale Wash Sales

### IRC section 1091(e) -- Special Rules

Short sales add complexity to wash sales:

1. **Short against the box:** If you own stock and sell short "against the box" (meaning you also hold the same stock long), losses on closing the short position may be subject to wash sale rules if you maintain the long position.

2. **Closing a short sale at a loss:** If you close a short position at a loss and reopen a short position in the same security within 30 days, wash sale rules apply.

3. **Constructive sale rules (IRC section 1259):** Selling short against an appreciated long position may trigger a "constructive sale," which is a separate (and harsher) regime from wash sales.

---

## ETF Tax Efficiency: Share Creation/Redemption

### Why ETFs Are More Tax-Efficient Than Mutual Funds

ETFs use an **in-kind creation/redemption** mechanism that systematically purges low-basis shares from the portfolio without triggering taxable events:

1. When an authorized participant (AP) redeems ETF shares, the ETF delivers **actual stock** (not cash) to the AP
2. The ETF manager selects the **lowest-basis** lots to deliver, removing the built-in gain from the fund
3. This is not a taxable sale by the ETF -- it is an in-kind transfer

**Result:** ETFs rarely distribute capital gains. The Vanguard S&P 500 ETF (VOO) has distributed **$0** in capital gains in most years. The equivalent mutual fund (VFIAX) has distributed capital gains in several years.

### Impact on Wash Sale Planning

Because ETFs are more tax-efficient, consider:
- Hold the ETF version of funds in taxable accounts (fewer surprise distributions)
- Hold the mutual fund version in tax-advantaged accounts (distributions don't matter)
- When tax-loss harvesting, swap between ETFs and mutual funds cautiously -- ETF-to-identical-mutual-fund is likely a wash sale

---

## Worked Examples with Specific Dates and Dollar Amounts

### Example 1: Basic Wash Sale

```
Jan 10: Buy 200 shares TSLA at $250/share            Basis: $50,000
Mar 5:  Sell 200 shares TSLA at $200/share            Proceeds: $40,000
        Loss: $10,000
Mar 15: Buy 200 shares TSLA at $205/share             Cost: $41,000

Result: $10,000 loss DISALLOWED (wash sale)
New basis of Mar 15 shares: $41,000 + $10,000 = $51,000
Holding period: includes time from Jan 10 (tacks on)
```

### Example 2: Partial Wash Sale

```
Jun 1:  Buy 300 shares META at $400/share             Basis: $120,000
Sep 10: Sell 300 shares META at $350/share             Proceeds: $105,000
        Loss: $15,000
Sep 20: Buy 100 shares META at $355/share              Cost: $35,500

Result: 100/300 of loss disallowed = $5,000 disallowed
Deductible loss: $10,000
New basis of 100 shares: $35,500 + $5,000 = $40,500
```

### Example 3: IRA Permanent Loss Destruction

```
Oct 1:  Buy 500 shares NVDA at $500/share in taxable  Basis: $250,000
Nov 15: Sell 500 shares NVDA at $450/share in taxable  Proceeds: $225,000
        Loss: $25,000
Nov 20: Buy 500 shares NVDA at $455/share in Roth IRA  Cost: $227,500

Result: $25,000 loss PERMANENTLY DESTROYED
- Cannot deduct the loss on current return
- Cannot add $25,000 to Roth IRA basis (no mechanism exists)
- $25,000 is gone forever
- Cost: at 23.8% LTCG rate = $5,950 in permanently lost tax benefit
```

### Example 4: Year-End Tax-Loss Harvest with Safe Swap

```
Nov 28: Own 1,000 shares Vanguard S&P 500 ETF (VOO) at $400 basis
        Current price: $380
        Unrealized loss: $20,000
Nov 28: Sell 1,000 shares VOO at $380                  Proceeds: $380,000
        Loss: $20,000 (DEDUCTIBLE)
Nov 28: Buy 1,000 shares Vanguard Total Stock Mkt (VTI) at $220
        Cost: $220,000 (different index, not substantially identical)

Jan 5:  Sell 1,000 shares VTI (if desired)
Jan 5:  Buy 1,000 shares VOO (back to original position)
        No wash sale on the VOO loss -- VTI is not substantially identical
        At 23.8% rate, $20,000 loss saves $4,760 in taxes
```

### Example 5: Cryptocurrency Loss Harvest (No Wash Sale Concern)

```
Dec 15: Own 2.0 BTC at $60,000 basis ($30,000/BTC)
        Current price: $25,000/BTC
        Unrealized loss: $10,000
Dec 15: Sell 2.0 BTC at $25,000/BTC                    Proceeds: $50,000
        Loss: $10,000 (DEDUCTIBLE)
Dec 15: Immediately buy 2.0 BTC at $25,000/BTC         Cost: $50,000

Result: $10,000 loss fully deductible -- wash sale rules do NOT apply to crypto
        New basis: $50,000 (reset to current market)
        If BTC recovers to $30,000: gain is $10,000 (same economic position,
        but you claimed a $10,000 loss in the current year)
```

---

## Wash Sale Tracking and Reporting

### Software Solutions

| Tool | Coverage | Notes |
|---|---|---|
| TaxBit | Crypto + securities | Excellent cross-exchange tracking |
| CoinTracker | Primarily crypto | Good for multi-exchange crypto |
| GainsKeeper | Securities | Legacy tool, integrated with some brokers |
| TradeLog | Active traders | Handles complex multi-account scenarios |

### Form 8949 Reporting

When reporting a wash sale on Form 8949:

1. **Column (a):** Description of property (e.g., "100 sh AAPL")
2. **Column (b):** Date acquired
3. **Column (c):** Date sold
4. **Column (d):** Proceeds
5. **Column (e):** Cost or other basis (unadjusted)
6. **Column (f):** Code **"W"** for wash sale
7. **Column (g):** Amount of adjustment (the disallowed loss as a positive number)
8. **Column (h):** Gain or loss (after adding back the disallowed loss, this may show $0 or a reduced loss)

**Example entry:**
```
(a) 100 sh AAPL
(b) 01/15/2025
(c) 03/05/2025
(d) $15,000
(e) $20,000
(f) W
(g) $5,000
(h) $0          (loss of $5,000 fully disallowed)
```

The disallowed $5,000 is added to the basis of the replacement shares, which will be reported on a future Form 8949 when those shares are eventually sold.

---

## Advanced Strategies and Pitfalls

### The "Bed and Breakfast" (UK Term) Problem

Some investors try to sell on December 31 and repurchase January 1. This clearly violates the 30-day rule. You must wait until January 31 (31 days after the sale) to repurchase.

### Dividend Reinvestment Trap

Even a small DRIP purchase of $10 within the wash sale window can taint the entire loss. If you plan to harvest losses on a dividend-paying stock:
1. Turn off DRIP at least 31 days before selling
2. Verify no dividends are scheduled within 30 days after selling
3. Check the ex-dividend date, not the payment date

### Wash Sale Chain Reactions

Wash sales can "chain" -- if a wash sale defers a loss to new shares, and you sell those new shares at a loss and trigger another wash sale, the loss keeps getting deferred. In extreme cases with frequent trading, a loss can be deferred for months or even into the next tax year.

### Worthless Securities (IRC section 165(g))

If a security becomes truly worthless, the loss is allowed regardless of wash sale rules because there is no way to acquire "substantially identical" shares of a worthless company. The loss is treated as a capital loss on the last day of the tax year.

---

## Strategy Interaction Matrix

| Strategy | Wash Sale Interaction |
|---|---|
| Tax-loss harvesting | DIRECTLY affected -- must plan around 61-day window |
| Roth conversion | No interaction (conversion is not a sale of securities) |
| Charitable giving | No interaction (donation is not a sale) |
| 1031 exchange | Not applicable (real estate, not securities) |
| Installment sale | Wash sale applies if replacement purchased |
| Crypto harvesting | NOT subject to wash sale (2025 law) |
| Options strategies | Complex interaction -- see options section above |
| Short selling | section 1091(e) special rules apply |
| Margin calls | Forced sale may trigger wash sale if you repurchase |
| Estate planning | Stepped-up basis at death eliminates need for wash sale planning |

---

## Key Regulatory References

- **IRC section 1091(a):** Core wash sale provision
- **IRC section 1091(d):** Basis adjustment for replacement property
- **IRC section 1091(e):** Short sale wash sale rules
- **IRC section 1223(4):** Holding period tacking for wash sales
- **Reg. section 1.1091-1:** Treasury regulations implementing wash sale rules
- **Reg. section 1.1091-2:** Rules for wash sales involving substantially identical bonds
- **Rev. Rul. 56-602:** Options as substantially identical securities
- **Rev. Rul. 2008-5:** IRA replacement purchase permanently destroys loss
- **IRS Publication 550:** Investment Income and Expenses (wash sale guidance)
- **Bedrosian v. Commissioner, T.C. Memo. 1979-200:** Spousal purchases trigger wash sale
