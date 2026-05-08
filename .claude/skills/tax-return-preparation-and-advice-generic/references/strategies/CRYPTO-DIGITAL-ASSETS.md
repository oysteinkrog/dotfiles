# Crypto and Digital Asset Tax Strategies

## Overview

The IRS treats cryptocurrency and digital assets as property (Notice 2014-21). Every disposal is a taxable event, and record-keeping requirements are substantial. Beginning in 2025, exchanges are issuing Form 1099-DA, bringing crypto reporting closer to traditional securities.

---

## IRS Classification

Digital assets are property, not currency. This means:
- Capital gains/losses rules apply to sales, trades, and disposals
- Ordinary income rules apply to mining, staking, airdrops, and payments for services
- All the same documentation and reporting requirements as stock and real estate transactions

---

## Taxable Events

### Events That Trigger Tax

| Event | Tax Treatment | Reported On |
|---|---|---|
| Sell crypto for fiat (USD, etc.) | Capital gain/loss | Schedule D, Form 8949 |
| Trade one crypto for another | Capital gain/loss on disposed crypto | Schedule D, Form 8949 |
| Spend crypto on goods/services | Capital gain/loss | Schedule D, Form 8949 |
| Receive crypto as payment for services | Ordinary income at FMV when received | Schedule C or Schedule 1 |
| Mining rewards | Ordinary income at FMV when received | Schedule C (if business) or Schedule 1 |
| Staking rewards | Ordinary income at FMV when received (Rev. Rul. 2023-14) | Schedule 1 or Schedule C |
| Airdrops (dominion and control established) | Ordinary income at FMV when received (Rev. Rul. 2019-24) | Schedule 1 or Schedule C |
| Hard fork (if new coins received and accessible) | Ordinary income at FMV when received (Rev. Rul. 2019-24) | Schedule 1 |
| Interest/rewards from lending platforms | Ordinary income | Schedule 1 or Schedule B |
| Cross-chain bridge transfer | Likely taxable disposition (see below) | Schedule D, Form 8949 |
| Wrapping tokens (ETH -> wETH) | Uncertain -- see analysis below | May need Form 8949 |

### Non-Taxable Events

| Event | Notes |
|---|---|
| Buy crypto with fiat | Not taxable (establishes cost basis) |
| Transfer between your own wallets (same chain) | Not taxable (same owner, no disposal) |
| Gift crypto (below annual exclusion) | Not taxable to giver or recipient (recipient takes carryover basis) |
| Donate crypto to charity | Not taxable; deduction at FMV if held over 1 year |

---

## Staking Rewards -- Detailed Analysis

### IRS Position (Rev. Rul. 2023-14)

Staking rewards are taxable as ordinary income at the time the taxpayer gains dominion and control. This means:

- **When taxable:** The moment the staking reward is credited to the taxpayer's account and available for withdrawal/transfer
- **Amount:** Fair market value at the time of receipt
- **Basis:** FMV at receipt becomes the cost basis for future capital gain/loss calculations
- **Subsequent sale:** If held >1 year after receipt, gain/loss is long-term capital gain/loss

### Staking Income Reporting

```
Example: Validator receives 0.5 ETH staking reward on March 15
ETH price on March 15: $3,200

Ordinary income recognized: 0.5 x $3,200 = $1,600
Basis in the 0.5 ETH: $1,600

If sold 14 months later at $4,000/ETH:
Proceeds: 0.5 x $4,000 = $2,000
Basis: $1,600
Long-term capital gain: $400
```

### The Jarrett Case (Not Settled Law)

In Jarrett v. United States, the taxpayer argued that staking rewards are newly created property (like a baker baking bread) and should not be taxable until sold. The IRS refunded the tax but the case was dismissed without precedent. The IRS subsequently issued Rev. Rul. 2023-14 confirming that staking rewards ARE taxable at receipt. The Jarrett argument is not viable for tax preparation purposes.

---

## Hard Forks and Airdrops

### IRS Position (Rev. Rul. 2019-24)

- **Hard fork without airdrop:** If a blockchain forks but no new tokens are distributed, there is no taxable event
- **Hard fork with airdrop (or standalone airdrop):** Taxable as ordinary income at FMV when the taxpayer has dominion and control over the new tokens
- **Dominion and control:** The ability to transfer, sell, or otherwise dispose of the tokens. If the tokens are on an exchange and the exchange does not support the new coin, the taxpayer may not have dominion and control until the exchange supports it (or the taxpayer moves to a wallet where they can access it)
- **Basis:** FMV at the time dominion and control is established

### Practical Challenges

- Many airdrops arrive unsolicited at negligible value
- "Dust attacks" (worthless tokens sent to wallets) should not be reported as income if they have no FMV
- Tokens from defunct projects may have $0 FMV at receipt -- no income to report
- Track the date dominion and control is established, not necessarily the date of the airdrop transaction

---

## Cost Basis Methods

### Available Methods

| Method | Description | Best For |
|---|---|---|
| **FIFO** (First In, First Out) | Oldest lots sold first | Default if no election; generally results in long-term gains |
| **LIFO** (Last In, First Out) | Newest lots sold first | Maximizing short-term losses or minimizing gains in rising markets |
| **Specific Identification** | Choose which specific lots to sell | Maximum flexibility; can minimize current tax |
| **Average Cost** | Average cost of all units | Simpler calculation; now permitted for crypto under new IRS rules |

### Specific Identification (Preferred)

- Requires identifying the specific units sold at the time of the transaction
- Must be documented (exchange records, wallet records, timestamps)
- Allows strategic selection: sell highest-basis lots to minimize gains, or lowest-basis lots to realize losses
- Most tax-efficient method overall

### Cost Basis Complexity and Tools

**The challenge:** Unlike stock held at a single brokerage, crypto often moves between exchanges, wallets, and protocols. Each movement can create tracking difficulties.

**Universal vs. per-exchange tracking:**
- Universal tracking: all holdings across all exchanges/wallets are treated as one pool. Specific identification draws from ANY lot regardless of location. This is the correct method but requires comprehensive records.
- Per-exchange tracking: each exchange is treated separately. Simpler but can produce incorrect results (the IRS does not recognize per-exchange as a separate basis method).

**Recommended tools for basis tracking:**
| Tool | Strengths | Exchanges/Chains Supported |
|---|---|---|
| CoinTracker | Broadest integration, tax-loss harvesting alerts | 300+ exchanges, major chains |
| Koinly | Strong DeFi support, international tax reporting | 350+ exchanges, 50+ blockchains |
| TokenTax | Full-service (they prepare the return), DeFi support | Major exchanges + manual import |
| CoinLedger (fka CryptoTrader.Tax) | Simple interface, good for basic portfolios | 100+ exchanges |
| TaxBit | Enterprise-grade, used by exchanges themselves | Major exchanges, EVM chains |

**Best practice:** Use one tool consistently. Import from ALL exchanges and wallets. Reconcile annually. Generate Form 8949 from the tool.

### Changing Methods

- You can change methods between tax years
- Cannot retroactively change the method for prior-year transactions
- Once a lot is sold using a particular method, that sale is final
- Starting in 2025, brokers may assign default methods on 1099-DA -- verify and override if needed

---

## Section 475(f) Mark-to-Market Election for Crypto Traders

### What It Is

A trader in commodities or securities can make an IRC 475(f) election to use mark-to-market (MTM) accounting. All positions are treated as sold at FMV on the last business day of the tax year. All gains and losses become ordinary (not capital).

### Application to Crypto

The IRS has not definitively ruled on whether crypto qualifies for 475(f) treatment, but many tax practitioners argue it does because:
- Crypto is "property" under Notice 2014-21
- 475(f) applies to "commodities" (broadly defined) or "securities" (if the taxpayer is a trader in securities)
- Crypto may qualify as a commodity for 475(f) purposes

### Requirements

- Must be filed by the DUE DATE of the PRIOR year's return (not the current year). For the 2025 tax year, the election must have been filed by April 15, 2025 (the due date of the 2024 return).
- The taxpayer must be a "trader" (not just an investor): frequent, regular, and continuous trading activity with the intent to profit from short-term price movements
- The election is made by attaching a statement to the tax return and filing internally in the taxpayer's records

### What It Does

| Feature | Without 475(f) | With 475(f) |
|---|---|---|
| Gain/loss character | Capital (STCG/LTCG) | Ordinary income/loss |
| Loss limitation | $3,000/year capital loss limit | NO limit (ordinary losses fully deductible) |
| Wash sale rule | Does not apply to crypto (currently) | Irrelevant (all gains/losses are ordinary) |
| Year-end treatment | Only realized transactions | ALL positions marked to market |
| LTCG rate benefit | Yes (0%/15%/20%) | NO (all ordinary) |
| Net operating loss | No | Yes (ordinary losses can create NOL) |

### When 475(f) Makes Sense

- Active trader with significant unrealized losses at year-end
- Trader who frequently generates large losses that exceed the $3,000 capital loss limit
- Day trader who wants all gains/losses to be ordinary (simplifies reporting)

### When 475(f) Does NOT Make Sense

- Buy-and-hold investor (destroys LTCG rates)
- Taxpayer with large unrealized long-term gains (would be converted to higher-taxed ordinary income)
- Must be filed BEFORE the tax year begins -- cannot be applied retroactively

---

## DeFi Deep Dive

### Liquidity Pools

**Adding liquidity:**
- Depositing tokens into a liquidity pool (e.g., Uniswap, Curve) involves sending Token A and Token B to the pool smart contract
- In return, the depositor receives LP tokens representing their share
- **Tax treatment:** Likely a taxable exchange -- disposing of Token A + Token B in exchange for LP tokens. The LP tokens have a basis equal to the FMV of the tokens deposited.
- **Counterargument:** Some practitioners argue this is a deposit (like putting money in a bank), not a sale. The IRS has not issued definitive guidance.

**Removing liquidity:**
- Redeeming LP tokens for the underlying tokens
- **Tax treatment:** Likely a taxable exchange -- disposing of LP tokens for Token A + Token B. Gain/loss = FMV of tokens received minus basis of LP tokens.
- Impermanent loss is NOT a separately recognized tax concept; it is reflected in the gain/loss calculation when liquidity is removed.

**LP rewards/fees:**
- Trading fees earned by liquidity providers: ordinary income at FMV when received or accrued
- Governance token rewards (e.g., UNI, SUSHI): ordinary income at FMV when received

### Yield Farming

- Tokens received as yield farming rewards: ordinary income at FMV when received
- Subsequent sale of reward tokens: capital gain/loss from the income-recognized basis
- Auto-compounding vaults (e.g., Yearn): may trigger income at each compounding event (if new tokens are received), or may be deferred until withdrawal -- this is a gray area

### Wrapping and Unwrapping

**Wrapping ETH to wETH (same chain):**
- Majority practitioner view: non-taxable (functionally equivalent, 1:1 exchange on same chain)
- Conservative view: taxable disposition (you send ETH, receive a different token: wETH)
- **IRS has not ruled definitively.** The safest approach is to track as if taxable (calculate gain/loss) but report as non-taxable with a disclosure note. If the IRS later rules it is taxable, you have the records.

**Cross-chain bridges (e.g., ETH on Ethereum -> ETH on Arbitrum):**
- More likely to be treated as a taxable disposition because:
  - You send a token on Chain A and receive a different token (bridged/wrapped version) on Chain B
  - The IRS treats each blockchain as a separate asset class
  - The tokens are technically different smart contracts
- **Recommended treatment:** Report as a taxable exchange. Gain/loss = FMV at bridge time minus basis of original token. New token has basis = FMV at bridge time.

### Liquid Staking Receipt Tokens (stETH, rETH, cbETH)

Liquid staking protocols allow users to stake ETH (or other assets) and receive a liquid receipt token in return (e.g., Lido's stETH, Rocket Pool's rETH, Coinbase's cbETH). The tax treatment of receiving a liquid staking token is **unresolved** -- there is NO IRS guidance on this specific question.

**Two positions:**

1. **Conservative position (taxable disposition):** Depositing ETH into Lido and receiving stETH is a taxable exchange -- the taxpayer has disposed of ETH and received a different asset (stETH). Gain/loss is recognized at the time of the swap. The stETH has a basis equal to its FMV at receipt.

2. **Aggressive position (non-taxable exchange):** The deposit is analogous to wrapping (ETH -> wETH) -- a non-taxable transformation of the same economic position. The stETH inherits the basis of the original ETH. No gain/loss until the stETH is sold or redeemed.

**Key considerations:**
- stETH rebases daily (balance increases to reflect staking rewards). Each rebase may constitute ordinary income under the conservative view.
- rETH and cbETH do NOT rebase -- they appreciate in value relative to ETH. Under the conservative view, staking rewards are only recognized when the token is sold (as capital gain, not ordinary income). This creates a potential character difference.
- **Recommendation:** Document the position taken. Track basis under both methods if feasible. Be prepared to defend either position. The IRS could rule either way when (if) guidance is issued.

### Restaking (EigenLayer-Style Protocols)

Restaking protocols allow users to deposit liquid staking tokens (stETH, rETH) into a second protocol layer (e.g., EigenLayer) and receive yet another receipt token. This creates a chain of receipt tokens with **absolutely no IRS guidance** at any level.

**Tax treatment is completely uncharted territory.** The open questions include:
- Is depositing stETH into EigenLayer a taxable disposition of the stETH?
- What is the basis of the restaking receipt token?
- Are restaking rewards (from securing additional protocols) ordinary income? When is dominion and control established?
- If the restaking receipt token is itself used in DeFi (lending, liquidity provision), how is basis tracked through multiple layers of abstraction?

**Recommendation:** Track every deposit, withdrawal, and reward event with timestamps and FMV. Maintain a clear record of the chain of custody (ETH -> stETH -> EigenLayer deposit -> restaking receipt token). Choose a consistent position and document the rationale. This area will eventually receive guidance, and clean records will be essential for compliance or amended filing.

### Lending / Borrowing

- **Lending crypto and receiving interest:** Ordinary income on interest received (whether in crypto or fiat)
- **Borrowing against crypto:** NOT a taxable event (loan, not a sale)
- **Liquidation of collateral:** Taxable disposal of the collateral (capital gain/loss on the difference between collateral basis and FMV at liquidation)
- **Interest paid on crypto loans:** May be deductible if used for investment purposes (investment interest expense on Schedule A, limited to net investment income). If used for business purposes, deductible on Schedule C.

### DAO Participation

- **Governance token holdings:** Not taxable to hold (same as any other crypto)
- **Treasury distributions:** If a DAO distributes tokens from its treasury to governance token holders, this is likely taxable as ordinary income at FMV when received
- **Compensation for contributions:** Payments for work (development, governance, management) are ordinary income. If the DAO is structured as a partnership or other entity, Form K-1 may apply. If compensation is paid directly in tokens, it is self-employment income reported on Schedule C.
- **DAO-as-entity:** Some DAOs may be treated as partnerships or unincorporated associations for tax purposes, with members receiving K-1s. The tax characterization depends on the DAO's structure and activities.

### DAO Governance Token Airdrops

Governance tokens received via airdrop are **ordinary income at FMV** when the recipient has **dominion and control** (per Rev. Rul. 2019-24, applied by analogy to governance token distributions). Key considerations:

- **Unconditional airdrops (no lockup):** Taxable at FMV when tokens appear in the wallet and the recipient can transfer, sell, or use them. Basis = FMV at receipt.
- **Tokens subject to lockup or vesting:** The dominion-and-control question becomes fact-specific. If the tokens are in the wallet but cannot be transferred (smart contract lock, vesting schedule), the taxpayer may not have dominion and control until the lockup expires. However, if the tokens can be used for governance voting during the lockup period, the IRS could argue partial dominion and control exists.
- **Claiming requirement:** Many governance airdrops require the recipient to affirmatively claim the tokens (e.g., visiting a website and submitting a transaction). Income is recognized when the claim transaction is executed and tokens are received -- not when the airdrop is announced or the eligibility snapshot occurs.
- **Basis:** FMV at the time of receipt becomes the cost basis. Subsequent price changes are capital gain/loss.

### Token Lockups and Vesting Schedules

When tokens are received subject to lockup restrictions or vesting schedules, the timing of income recognition depends on the interaction between Rev. Rul. 2019-24 (dominion and control) and **Section 83** (property transferred in connection with services).

**Section 83 Analysis:**
- If tokens are received in connection with the performance of services (employment, contract work, DAO contributions), Section 83 governs.
- **Section 83(a):** If the tokens are subject to a **substantial risk of forfeiture** (e.g., they are forfeited if the recipient stops contributing before the vesting date) AND are **not transferable**, income is deferred until the tokens vest (i.e., the restrictions lapse). Income = FMV at vesting minus amount paid.
- **Section 83(b) election:** The recipient may elect under Section 83(b) to recognize income at GRANT (not vesting). The election must be filed with the IRS within **30 days** of the token grant. This is advantageous if the tokens are expected to appreciate -- the recipient pays tax on the lower grant-date FMV, and all subsequent appreciation is capital gain.
  - **Risk:** If the tokens decline in value or are forfeited, no deduction is available for the previously recognized income.
  - **Requirement:** The tokens must have an ascertainable FMV at grant. For illiquid, non-traded governance tokens, establishing FMV may be difficult.
- **Tokens NOT received for services:** If tokens are received via a general airdrop (not for services), Section 83 does not apply. The dominion-and-control test from Rev. Rul. 2019-24 governs -- income is recognized when the recipient can freely dispose of the tokens.

---

## NFT Taxation

### Creating and Selling NFTs

- **Creator sells NFT:** Ordinary income (proceeds minus cost of creation)
- **Reported on:** Schedule C (if business activity)
- **Self-employment tax:** Applies to creator income
- **Royalties on secondary sales:** Ordinary income when received

### Purchasing and Selling NFTs -- By Type

**Art/collectible NFTs:**
- If the NFT represents art, a collectible, or an antique, the maximum LTCG rate is **28%** (not 20%)
- This is the "collectibles" rate under IRC 408(m) and 1(h)(4)
- Applies to: digital art, PFP projects (Bored Apes, CryptoPunks, etc.), music NFTs
- Short-term gains are still taxed as ordinary income (no difference)

**Utility NFTs:**
- NFTs that represent access, membership, or in-game items may not be collectibles
- Regular LTCG rates (0%/15%/20%) may apply
- The IRS issued Notice 2023-27 requesting comments on NFT collectible classification but has not issued final guidance
- **Recommended approach:** Treat art/PFP NFTs as collectibles (28% rate) and utility NFTs as regular property (20% rate), but be prepared for IRS reclassification

**Fractionalized NFTs:**
- Fractionalized ownership (e.g., via Fractional.art or PartyBid) creates fungible ERC-20 tokens representing shares of an NFT
- The fractionalization itself may be a taxable event (exchanging NFT for tokens)
- Sale of fractional tokens: capital gain/loss
- Collectible character may carry through to the fractional tokens

### Gas Fees

- Gas fees paid to acquire an asset: added to cost basis
- Gas fees paid to sell an asset: reduce proceeds (or increase loss)
- Gas fees for non-taxable transactions (transfers between own wallets): may be deductible as investment expenses (though miscellaneous itemized deductions are suspended through 2025 under TCJA)
- Gas fees for failed transactions: likely a non-deductible personal loss (no asset acquired, no sale completed)

---

## Wash Sale Rules and Crypto

### Current Law (2025)

- The wash sale rule (Section 1091) applies to "stock or securities"
- Cryptocurrency is classified as property, NOT stock or securities
- Therefore, the wash sale rule does **NOT currently apply** to cryptocurrency
- This means: you can sell crypto at a loss and immediately repurchase the same asset, realizing the loss without the 30-day waiting period

### Tax-Loss Harvesting Strategy

Because the wash sale rule does not apply to crypto (as of 2025):

1. Identify positions trading at a loss
2. Sell the position to realize the loss
3. Immediately repurchase the same asset
4. The loss is recognized for tax purposes
5. The new purchase has a basis equal to the repurchase price

This can be done daily, weekly, or at any frequency. There is no 30-day waiting period.

**Example:**
```
Bought 1 BTC at $60,000
BTC drops to $45,000
Sell 1 BTC: realize $15,000 loss
Immediately buy 1 BTC at $45,000: new basis = $45,000
Net position: still hold 1 BTC, but have $15,000 realized loss

If in 24% bracket: tax savings = $15,000 x 24% = $3,600
(Subject to capital loss limitations if no offsetting gains)
```

### Potential Changes

- Multiple legislative proposals have been introduced to extend wash sale rules to digital assets
- The Build Back Better Act and various budget proposals included crypto wash sale provisions
- If enacted, the same 30-day before/after window would apply
- Monitor legislation -- this could change in future tax years
- Some tax software may incorrectly apply wash sale rules to crypto; verify

---

## Lost, Stolen, and Worthless Crypto

### Lost/Stolen Crypto (Hacks, Scams, Lost Keys)

Under TCJA (2018-2025), personal casualty losses are ONLY deductible if attributable to a federally declared disaster. This means:
- Crypto lost to hacking, scams, phishing, or exchange insolvency (e.g., FTX, Celsius) is generally NOT deductible as a casualty loss
- Crypto in a lost/inaccessible wallet (lost private keys) is NOT deductible as a casualty loss

### Worthless Security Deduction (IRC 165(g))

If crypto becomes provably worthless, a deduction may be available:
- **IRC 165(g):** If the crypto can be characterized as a "security" that becomes worthless, the loss is treated as a capital loss on the last day of the tax year
- **IRC 165(a) general loss provision:** A loss sustained and not compensated by insurance is deductible. For crypto to qualify, the taxpayer must demonstrate:
  1. The asset is genuinely worthless (not merely low-value)
  2. There is no reasonable prospect of recovery
  3. An identifiable event establishing worthlessness occurred (exchange closure, project abandonment, blockchain cessation)

### Abandoned Property

- If a taxpayer abandons property (e.g., sends crypto to a burn address), the loss may be deductible as an ordinary loss under IRC 165
- Must demonstrate genuine abandonment (not just holding a worthless token in a wallet)
- Sending to a documented burn address (0x000...dead) with no ability to recover is strong evidence of abandonment

### Practical Approach for FTX/Celsius/BlockFi Claims

- If a bankruptcy claim exists, the loss is NOT yet final (there may be a recovery)
- When the final distribution is determined, the loss = basis minus amount recovered
- The loss is a capital loss (not ordinary) in most cases
- Claim the loss in the year the worthlessness becomes certain (final bankruptcy distribution)

---

## Mining as a Business

### Schedule C Reporting

If crypto mining is conducted as a trade or business (regular, continuous activity with profit intent):

**Income:**
- Mining rewards: ordinary income at FMV when mined (this is gross revenue on Schedule C)

**Deductions:**
- **Equipment:** Mining rigs, GPUs, ASICs -- eligible for Section 179 immediate expensing (up to $2,500,000 in 2025) or bonus depreciation
- **Electricity:** The largest ongoing expense for most miners. Deductible to the extent used for mining.
- **Internet/connectivity:** Business-use percentage deductible
- **Facility costs:** If mining in a dedicated facility (not home), all facility costs are deductible
- **Home office:** If mining rigs are in a dedicated room of the home, the home office deduction applies (regular and exclusive use test). Note: heat and noise from mining rigs may make it difficult to claim the space is "regular and exclusive" if it is also used for other purposes.
- **Pool fees:** Mining pool fees deductible as business expense
- **Cooling:** Additional cooling costs attributable to mining equipment
- **Software:** Mining software, monitoring tools

**Self-employment tax:** Mining income is subject to SE tax (15.3% on first $176,100 of combined wages + SE income for 2025, then 2.9% Medicare on amounts above).

### Hobby vs. Business

If mining is not a business (hobby), income is still reportable but deductions are severely limited:
- Income reported on Schedule 1 (not Schedule C)
- No deduction for expenses (TCJA suspended hobby loss deductions through 2025)
- Still subject to income tax but no SE tax

**Factors supporting business treatment:** Significant investment in equipment, regular mining activity, profit in 3 of last 5 years (safe harbor, not requirement), taxpayer's expertise, time and effort devoted.

---

## Form 1099-DA (New for 2025)

### What It Is

Beginning in 2025, cryptocurrency exchanges and brokers are required to issue Form 1099-DA (Digital Asset Proceeds) to users and the IRS.

### What It Reports

- Gross proceeds from sales or dispositions
- Cost basis (if known to the exchange)
- Date acquired and date sold
- Gain or loss (if basis is available)

### Important Caveats

- Exchanges may not have complete cost basis information (especially for assets transferred in from external wallets)
- Basis may be reported as $0 or "unknown" for transferred-in assets
- Taxpayer is responsible for accurate basis regardless of what the 1099-DA shows
- Multiple exchanges mean multiple 1099-DAs -- consolidation is the taxpayer's responsibility
- **DeFi Broker Rule Repeal (April 2025):** The DeFi broker 1099-DA reporting rule was repealed in April 2025 (signed by President Trump), removing reporting obligations for on-chain-only protocols. DeFi protocols are **NOT** required to issue 1099-DA forms. This means decentralized exchanges (Uniswap, Curve, etc.) and other on-chain-only protocols have no 1099-DA filing obligation. **However, taxpayers are still required to self-report all gains, losses, and income from DeFi transactions.** The repeal of the broker reporting requirement does not change the underlying tax obligation -- it only removes the information-reporting burden from the protocols themselves.

---

## Foreign Account Reporting

### FBAR (FinCEN Form 114)

- Required if the aggregate value of foreign financial accounts exceeds $10,000 at any time during the year
- Foreign cryptocurrency exchanges (Binance, Bitfinex, KuCoin, etc.) are considered foreign financial accounts
- Filed electronically with FinCEN (not the IRS) by April 15 (automatic extension to October 15)

**Penalties (per Bittner v. United States, 2023):**
- Non-willful penalty: up to $12,909 per REPORT (not per account). The Supreme Court ruled in Bittner (2023) that the non-willful penalty is assessed per report, not per account, significantly reducing exposure for taxpayers with multiple foreign accounts.
- Willful penalty: up to $100,000 or 50% of account balance per account per year (Bittner does not limit willful penalties)
- Criminal penalties for willful violations: up to $250,000 fine and 5 years imprisonment

### FATCA (Form 8938)

- Required for specified foreign financial assets above:
  - $50,000 (single, end of year) or $75,000 (at any time during year) for domestic filers
  - $200,000 (single, end of year) or $300,000 (at any time) for foreign residents
  - Higher thresholds for MFJ
- Foreign crypto exchange accounts are reportable
- Filed with the tax return (Form 1040)

### Key Distinction

- US-based exchanges (Coinbase, Kraken US, Gemini): NOT foreign accounts, no FBAR/FATCA
- Foreign exchanges (Binance.com, KuCoin, Bybit): ARE foreign accounts, FBAR/FATCA apply
- Self-custodied wallets (hardware wallets, software wallets): generally NOT reportable (no financial institution involved), though FinCEN has proposed rulemaking that could change this -- monitor for updates

---

## The Form 1040 Digital Asset Question

Starting in 2022, Form 1040 asks: "At any time during [tax year], did you: (a) receive (as a reward, award, or payment for property or services); or (b) sell, exchange, gift, or otherwise dispose of a digital asset (or a financial interest in a digital asset)?"

**You must answer YES if you had ANY taxable crypto transaction during the year.**

Answering "No" when the answer is "Yes" is a false statement on a Federal tax return.

**You may answer NO if you only:**
- Held digital assets without selling, exchanging, or disposing of them
- Transferred digital assets between your own wallets

---

## Record-Keeping Requirements

### What to Track for Every Transaction

- Date and time of transaction
- Type of transaction (buy, sell, trade, receive, send)
- Amount of crypto (units)
- Fair market value in USD at the time of transaction
- Cost basis of the crypto disposed of
- Fees paid (gas fees, exchange fees)
- Wallet addresses involved
- Exchange or platform used

### Sources of Records

1. **Exchange exports:** Most exchanges (Coinbase, Kraken, Binance.US, Gemini) provide transaction history CSV exports
2. **On-chain data:** Blockchain explorers (Etherscan, Blockchain.com, Solscan) for wallet-based transactions
3. **DeFi aggregators:** Zapper, DeBank, Zerion for DeFi activity tracking
4. **Tax software:** CoinTracker, Koinly, TokenTax, CoinLedger, TaxBit -- import from exchanges and wallets, calculate gains/losses
5. **Manual records:** Spreadsheets for OTC trades, peer-to-peer transactions

### Recommended Approach

1. Export transaction history from ALL exchanges at least annually
2. Connect wallets to a crypto tax software platform
3. Reconcile exchange records with on-chain activity
4. Identify and categorize income events (mining, staking, airdrops)
5. Choose and consistently apply a cost basis method
6. Generate Form 8949 from the tax software
7. Keep all records for at least 6 years (the IRS can look back 6 years if income is understated by 25%+)

---

## Common Mistakes

1. **Not reporting crypto transactions** -- the IRS receives 1099s and has blockchain analytics capabilities
2. **Using incorrect cost basis** -- especially for assets transferred between exchanges/wallets
3. **Failing to report mining/staking income** -- this is ordinary income at FMV when received (Rev. Rul. 2023-14)
4. **Ignoring DeFi transactions** -- LP deposits, yield farming, and cross-chain swaps are generally taxable
5. **Not filing FBAR** for foreign exchange accounts -- penalties are severe
6. **Applying wash sale rules** when they do not currently apply to crypto (but be ready for legislative change)
7. **Treating all crypto-to-crypto trades as non-taxable** -- every trade is a taxable disposal
8. **Not tracking gas fees** -- they affect cost basis and proceeds
9. **Relying solely on exchange 1099s** for basis -- exchanges often do not have complete records
10. **Answering "No" to the Form 1040 digital asset question** when transactions occurred
11. **Treating cross-chain bridges as non-taxable** -- likely taxable dispositions
12. **Not reporting airdrop/hard fork income** -- taxable at FMV when dominion and control is established
13. **Making a 475(f) election without understanding the consequences** -- destroys LTCG rates on ALL positions
14. **Treating lost/stolen crypto as a casualty loss** -- generally not deductible under TCJA unless from a federally declared disaster
15. **Using per-exchange basis tracking** -- the IRS expects universal tracking across all platforms
