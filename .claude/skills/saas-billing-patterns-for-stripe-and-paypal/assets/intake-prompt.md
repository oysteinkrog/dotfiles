# Intake prompt

> **Template.** Use this at the very start of a new skill invocation to gather inputs from the user before kicking off Phase 0.

Hello — I'm activating the **saas-billing-patterns-for-stripe-and-paypal** skill. Before we start, I need to confirm a few things.

## 1. Project path
- Default: current working directory (`<cwd>`).
- Or: an absolute path to your SaaS project.
- Or: a git URL (I'll clone it to `/tmp/<basename>` first).

**What's the project path?** [<answer>]

## 2. Mode
Based on what you've told me, I think the right mode is **`<auto-detected mode>`**. Here are the options:

- `audit-only` — produce a written audit; no code changes.
- `audit-and-fix` — audit + close gaps in a multi-PR program of work. ← typical default for existing billing code
- `harden-incident` — a real incident just happened; RCA-driven scoped fix first, then expand.
- `add-feature` — adding ONE bounded billing capability (teams, dunning, MRR, etc.).
- `greenfield` — no billing code yet; build from scratch following the step-ordered build.
- `migration` — switching providers or adding a second provider.
- `compliance-pass` — SOC2 / ISO / customer security questionnaire.

**Which mode?** [<answer>]

## 3. Provider scope
- `stripe-only`
- `paypal-only`
- `both` ← default; the patterns are calibrated for the dual-provider asymmetric case

**Which providers?** [<answer>]

## 4. Risk appetite
- `production-paying-customers` — most patterns mandatory ← typical
- `pre-launch-pilot` — security mandatory; reporting deferrable
- `internal-tool` — skip dunning + reporting; keep schema + idempotency + hijack defenses

**Which risk appetite?** [<answer>]

## 5. Branch strategy
Default: I'll create a new branch `billing-<mode>-<YYYYMMDD>` and commit each phase separately so you can review per-phase diffs.

**OK with that branch name? Different naming convention?** [<answer>]

## 6. Real-DB tests
Phase 8 requires a disposable Postgres (Supabase branch / Neon branch / local Docker). **Mock-only billing tests are explicitly rejected** — we will refuse to mark Phase 8 complete without a real DB.

**Do you have a disposable Postgres available?**
- Yes (which? Supabase branch / Neon branch / local Docker / other)
- No (I'll help set one up)

[<answer>]

## 7. Stripe + PayPal sandbox creds
For Phase 9 staging drills.

**Do you have:**
- [ ] A Stripe Test mode account (with restricted API key)
- [ ] PayPal sandbox business + buyer accounts
- [ ] CLI access to Stripe (for `stripe trigger`)

If not, I'll walk you through generating them.

## 8. Resuming a prior run?
If `.billing_workspace/` already exists in your project, I can:
- (a) Re-enter the phase loop where it left off (idempotent).
- (b) Treat as a fresh run.

**What would you like?** [<answer>]

## 9. Helper skills
I'll check for these helper skills (`/operationalizing-expertise`, `/codebase-archaeology`, etc.). For any missing:
- If you have `jsm` installed and authenticated: I'll offer to `jsm install <name>` for each.
- If not: I'll fall back to inline equivalents (no blocking).

**Anything to know about your helper-skill setup?** [<answer>]

---

Once you've answered these, I'll:
1. Run `scripts/check-skills.sh .billing_workspace` (skill inventory).
2. Run `scripts/discover-stack.sh <project-path>` (stack detection).
3. (Optional) Run `subagents/cass-miner.md` (mine your past sessions for billing context).
4. Begin Phase 1.

Sound good?
