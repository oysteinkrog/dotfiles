# Cryptocurrency and Digital Assets

Modern estates include substantial digital components. Cryptocurrency is the most legally and operationally complex.

## Cryptocurrency — The Irrecoverable Loss Risk

**Self-custody wallets are genuinely irrecoverable if the seed phrase is lost.** A judge's order means nothing to the blockchain. Cryptography wins.

### Custody Types

| Type | Examples | Recovery at Death |
|------|----------|-------------------|
| **Exchange (custodial)** | Coinbase, Kraken, Binance.US, Gemini | KYC-based inheritance process; some have explicit procedures (Coinbase has one) |
| **Hot wallet** | MetaMask, Phantom, Trust Wallet | Requires seed phrase |
| **Hardware wallet** | Ledger, Trezor, Coldcard | Device useless without seed phrase (and possibly passphrase) |
| **Multi-signature** | Custom 2-of-3, 3-of-5 setups | Requires distributing keys across multiple parties |
| **Cold storage paper** | Hand-written seed phrases in safe | Fully irrecoverable if location lost |

### The Seed Phrase Problem

A 12-24 word seed phrase is a **bearer instrument** — whoever holds it controls the wallet.

- **Cannot put in the will** — wills often become public at probate, which creates obvious theft risk
- **Cannot leave with one person only** — single point of failure
- **Cannot store digitally without encryption** — risk of compromise
- **Must be findable by executor** — but not by random visitor

### Recommended Storage Patterns

**Single-user, modest holdings:**
- Hardware wallet in fireproof home safe
- Seed phrase on metal backup plate (Cryptosteel, Billfodl) in safe deposit box
- Letter of instruction: location of hardware wallet + safe deposit box, name of executor authorized to access

**Multi-user / family / larger holdings:**
- **Shamir's Secret Sharing** — split seed into N pieces requiring K to reconstruct (e.g., 3-of-5)
- Distribute pieces across: home safe, safe deposit box, attorney, trusted family member, professional fiduciary
- Diagram in letter of instruction explains where pieces are and recombination process

**Significant holdings ($1M+):**
- **Multi-sig wallet** (3-of-5 or similar) with keys distributed
- Some keys held by professional crypto custodian (Casa, Unchained, Anchorage)
- Specialty crypto trust attorney for documentation
- Specific crypto-trust company may be appropriate

### Inheritance Processes by Exchange

- **Coinbase:** has documented inheritance process — death certificate + court letters + ID
- **Kraken, Gemini:** similar
- **Binance.US:** process exists but slower
- **DeFi platforms:** no inheritance process; only seed phrase
- **NFT marketplaces:** depends on platform; OpenSea has nascent process

### Tax Basis

Cryptocurrency is **property** for federal tax purposes. Heirs need:
- Date-of-death FMV (use exchange data; CoinGecko/CoinMarketCap historical)
- Detailed transaction history for cost basis
- Records of any forks, airdrops, staking income

Keep transaction records via Koinly, CoinTracker, or similar throughout life. Without sufficient records, basis substantiation gets much harder and taxable gain can be overstated.

### DeFi Positions

- Tokens deposited in lending protocols (Aave, Compound)
- Liquidity pool positions (Uniswap, Curve)
- Yield farms
- Staked positions with unlock periods (ETH 2.0, etc.)

The executor needs not just the wallet but **instructions on how to unwind** these positions. Document each position with the protocol, contract address, position type, and unwinding procedure.

## Other Digital Assets

### Email Accounts (Gmail, Outlook)

- Decades of correspondence and important records
- Often the recovery email for everything else
- Google's **Inactive Account Manager**: pre-designate a successor with access after defined inactivity
- Apple's **Digital Legacy Contact**: similar
- Without designation, family typically requires court order; sometimes denied per terms of service

### Photo / Video Cloud Storage

- iCloud, Google Photos, Dropbox, OneDrive
- Often the only copy of decades of family photos
- Death without a legacy contact, recovery path, or independent backup can make recovery slow, partial, or impossible
- **Pre-designate** legacy contact or maintain offline backup

### Social Media

| Platform | Death Policy | Action |
|----------|--------------|--------|
| **Facebook** | Memorialize or delete; legacy contact can manage | Designate legacy contact |
| **Instagram** | Memorialize or delete | Family request with proof |
| **X (Twitter)** | Deactivate per family request | No legacy contact |
| **LinkedIn** | Memorialize or delete | Family request |
| **Apple ID** | Digital Legacy program | Designate contact |
| **Google** | Inactive Account Manager | Designate contact |

### Subscriptions and Recurring Services

Often hundreds of dollars/month in zombie subscriptions for 18 months of administration:
- Streaming (Netflix, Hulu, Disney+, Spotify)
- Software (Adobe, Microsoft 365, Dropbox)
- Newsletters and content (Substack)
- Gym, club memberships
- Cell phone, internet
- Cloud computing (AWS, Azure)

**List in digital inventory.** Executor needs to identify and cancel.

### Domain Names

- Personal or business domains can be valuable
- Renewal must continue after death or domain expires
- Coordinate with registrar (GoDaddy, Namecheap, Cloudflare) on transfer
- High-value domains (1-2 word .com) can be six- or seven-figure assets

### Online Business / Creator Accounts

- YouTube channels generating ad revenue
- Patreon, Substack subscriptions
- Podcast networks
- Twitch streams
- Etsy, Shopify, eBay stores

These generate ongoing income. Need clear succession plan:
- Who continues the channel/store?
- How is access transferred?
- Who handles tax reporting?

### Loyalty Programs

Often substantial value:
- Airline miles (transfer, reinstatement, or estate-handling policies vary by program)
- Hotel points (Marriott, Hilton, IHG, Hyatt — policies vary)
- Credit card points (issuer rules can be especially unforgiving at death or account closure)

**Planning tip:** If loyalty balances are material, do not assume they transfer cleanly or survive by default. Check the current program terms and decide whether to redeem, document, or pre-position them before they evaporate.

## RUFADAA — State-Law Framework for Digital-Asset Access

RUFADAA is a **uniform state-law framework**, not a federal statute. Many states have adopted versions of the **Revised Uniform Fiduciary Access to Digital Assets Act**, but you should still confirm the user's actual state-law version before treating digital-access language as final:
- Provides fiduciaries (executors, trustees, agents under POA) defined rights to access digital content
- Requires explicit authorization in the will, trust, and POA
- Coordinates with platform terms of service

**Standard authorization clause:**

```
I authorize my Personal Representative, Trustee, and Agent under any
Power of Attorney to access, control, modify, transfer, and delete
all of my digital assets, electronic communications, and online
accounts, to the fullest extent permitted by law including the
Revised Uniform Fiduciary Access to Digital Assets Act and any
similar legislation, and I expressly grant them lawful consent to
divulge the content of any electronic communication.
```

Without explicit authorization, fiduciaries can face delay, narrower access, or outright platform resistance even when they otherwise have authority to act.

## The Digital Asset Inventory (Deliverable)

Every plan produces a digital inventory ([DIGITAL-INVENTORY.md](../../assets/DIGITAL-INVENTORY.md) template). Includes:

- Each cryptocurrency wallet (type, approximate value, custody location)
- Seed phrase storage location (NOT the seed phrase itself in this document)
- Exchange accounts with username
- DeFi positions with protocol and contract
- Email accounts with username and recovery
- Cloud storage accounts
- Social media accounts and legacy contacts configured
- Domain names with registrar
- Creator/online business accounts
- Subscriptions to cancel at death
- Password manager — which one, location of master password recovery
- 2FA devices and recovery codes location

**Stored separately from the will.** Often in a sealed envelope with the attorney + a backup with executor + a backup in fireproof home safe.

## Common Failure Modes

1. **Crypto seed phrase lost at death** — wealth permanently inaccessible
2. **Seed phrase in the will** — public at probate; stolen
3. **Single point of failure** — one safe with seed phrase burns down
4. **Exchange inheritance process not researched** — months of delay, possible loss
5. **Email account locked** — recovery for all other accounts blocked
6. **Photos in iCloud only with no Legacy Contact or backup** — recovery becomes uncertain and may be partial or impossible
7. **Subscriptions running for 18 months** — thousands of dollars wasted
8. **Domain expires** — business or brand identity lost
9. **No RUFADAA authorization in documents** — executor blocked by privacy laws
10. **Tax basis records missing** for crypto — basis becomes hard to substantiate and gain can be overstated

## The Conversation to Have

> "Your digital life is now a major part of your estate. The crypto holdings need a recovery plan that survives your death without exposing seed phrases publicly. If your family photos are mainly in iCloud, Google Photos, or another cloud platform, we need a real legacy-contact or backup path instead of hoping the provider will sort it out later. Your YouTube channel generates real income that someone needs to continue or transfer. We need to build a digital inventory — separate from the will, kept secure but findable — that gives your executor the recovery path to everything that matters online. Let's start with the crypto: how is it held today?"
