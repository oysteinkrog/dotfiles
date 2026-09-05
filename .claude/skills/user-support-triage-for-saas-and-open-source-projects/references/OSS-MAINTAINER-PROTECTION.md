# OSS Maintainer Protection — Sustaining Open-Source Triage Without Burning Out

`GITHUB-FORK.md` covers the *mechanics* of triaging GitHub issues / PRs (commands, queries, gh CLI). This file covers the *human* layer specific to OSS — what makes maintainer-driven triage break down over months and years, and the policies and patterns that protect both the maintainer and the contributor experience.

> **Core insight:** an OSS project does not die because of bugs. It dies because the maintainer stops being able to face the issue queue. Every triage decision should be tested against "does this make the queue more or less faceable a month from now?"

This is the OSS analog to `CUSTOMER-PSYCHOLOGY.md` — the same emotional mechanics, different stakeholders.

---

## The Three Failure Modes Of OSS Triage

| Mode | What it looks like | Underlying cause | Fix |
|---|---|---|---|
| **Avalanche** | 100+ issues unread, weeks behind, no plan | Triage was treated as urgent-not-important; demand outpaced capacity | Stale-bot, contribution policy, weekly batch window |
| **Fortress** | Maintainer rejects all external PRs, defensive in tone | Past bad PR experiences; trust withdrawn | Honest "no-contributions" or "review-only" policy stated up front |
| **Saint** | Maintainer replies politely to everything, weekend work, "I'll get to it" | Identity tied to being helpful; can't say no | Pre-written boundary templates; office-hours; co-maintainer recruitment |

All three end the same way: maintainer steps back, project decays, contributors blame the maintainer for "abandonment." The protection patterns below try to keep the maintainer in the chair longer.

---

## The Contribution Policy Spectrum

There is no single "right" OSS contribution policy. There are five legitimate ones, and the disaster comes from running one *implicitly* while contributors assume another. Pick one explicitly, calibrate it to the maintainer's actual capacity, and put it in `CONTRIBUTING.md`:

### Policy 1 — Open contributions

> "We welcome all PRs. Please open an issue first for non-trivial changes. Maintainer review SLA: best-effort, usually <1 week."

Right when: maintainer has bandwidth, project is mature, community is active and self-policing.
Wrong when: maintainer is solo, ships fast, or the codebase is opinionated in ways drive-by contributors won't know.

### Policy 2 — Contribution by issue first

> "Open an issue and wait for maintainer response *before* writing a PR. PRs without a prior accepted issue may be closed."

Right when: maintainer wants to control direction; codebase has a coherent architecture; contributor enthusiasm is high but quality is uneven.
Wrong when: this becomes a way to *appear* open while never accepting issues.

### Policy 3 — Bug-fix contributions only

> "We accept PRs for bugs only. Feature work is owned by the core team. Open an issue for features; maintainer will decide whether to add to roadmap."

Right when: project has product opinions; contributor velocity > maintainer review velocity for features specifically.
Wrong when: bugs are also gatekept (then it's policy 5 in disguise).

### Policy 4 — Review-only

> "We're happy to review forks but cannot accept upstream PRs at this time."

Right when: maintainer has bandwidth to *help* but not bandwidth to *integrate* (review, test, merge, release, support).
Wrong when: this is a euphemism for "I never look at PRs" — be honest if so.

### Policy 5 — No external contributions

> "This is a one-person/closed-team project. PRs will be closed. You're welcome to fork."

Right when: maintainer has decided they want to ship without coordination overhead; project is opinionated.
Wrong when: the *appearance* of openness is preserved (issues open, contributing.md missing) — that's the worst combo.

**The disaster pattern**: project advertises as policy 1, runs as policy 5 in practice. Drive-by contributors spend weekends on PRs that get ignored or closed without explanation. Trust collapses; the contributor publicly complains; future would-be contributors avoid the project.

**The protective pattern**: state the *actual* policy, warmly, on day one of the README. Even policy 5 is fine — you're allowed to want to ship alone — but it has to be visible. Most negative emotion around OSS contribution is downstream of policy ambiguity, not policy choice.

---

## Drive-By Issues — The Triage Speed Trap

Drive-by issue patterns (someone files an issue, never returns):

| Sub-pattern | What to do |
|---|---|
| **No-repro shell** ("doesn't work, please fix") | Auto-reply with template requesting repro; close after 14d no response |
| **Feature wishlist** ("add support for X") | Mark `needs-discussion`; do not promise; queue for monthly review |
| **Question-as-issue** ("how do I do X?") | Convert to discussion / point to docs; close issue |
| **Stack-overflow drive-by** | Reply with the answer; close — these are usually one-shot users |
| **Vendor-bundling-our-tool** ("our customer reports...") | Politely redirect to vendor; the vendor is the actual user |

The triage skill's adapter contract treats these the same as SaaS tickets, but the *time budget* is different: for OSS, drive-by issue triage should take 2–5 minutes per item, not 20–40. Bulk-actionable templates and a stale-bot are essential.

### Stale-bot configuration (starter shape)

The YAML below is a policy shape, not a universal value judgment. High-trust, low-volume, or security-heavy projects may need longer windows or exempt labels; high-volume solo-maintainer projects may need shorter windows to keep the queue faceable.

```yaml
# .github/workflows/stale.yml — protect the maintainer
days-before-issue-stale: 30
days-before-issue-close: 14
days-before-pr-stale: 14
days-before-pr-close: 14
exempt-issue-labels: 'pinned,security,roadmap,confirmed-bug'
exempt-pr-labels: 'pinned,security,maintainer-priority'
stale-issue-message: |
  This issue has been quiet for 30 days. If it's still relevant, drop a
  comment and we'll keep it open. Otherwise it'll close in 14 days; you
  can always re-open with new info.
```

Adjust days based on volume. The stale-bot is *not* a way to dismiss issues; it's a way to *keep the queue legible* so the maintainer can find the alive items.

---

## The Three Templates Every OSS Project Should Have

Before any triage automation, write these three reply templates and put them in `04-templates/`:

### Template 1 — Bug report missing repro

```
Thanks for the report. To investigate, I need a reproduction:

1. The exact command you ran (or steps in the UI)
2. The version of <project> (`<project> --version` or in the about page)
3. OS / runtime version
4. The full error output (in a code block, not a screenshot if avoidable)

If you can put all of that in a comment here, I'll dig in. Without
repro the issue can't move forward; I'll auto-close in 14 days if
the info doesn't appear, but feel free to reopen any time you can
add it.
```

### Template 2 — Feature request

```
Thanks for the suggestion. We track feature requests with the
`enhancement` label and review them roughly monthly. A few things
that move a request up the list:

- A clear use case (what are you trying to do, and what's blocking?)
- Whether you'd be willing to draft a PR — happy to discuss design first
- 👍 reactions from other users (rough demand signal)

Right now this is in the `needs-discussion` bucket; I'll come back
to it. No promise on timeline.
```

### Template 3 — Drive-by PR (no prior issue)

```
Thanks for the PR — really appreciate you taking the time.

Quick note before I review: we ask for an issue first for changes
beyond minor fixes (typos, doc tweaks), so we can agree on the
shape before code is written. Could you open one summarizing what
you're solving, and link this PR? That way if we need to iterate
on the design, you don't lose the work you've done.

If this falls under "minor fix" (typo / single-line / pure doc),
ignore that — happy to review as-is.
```

These three templates handle 70%+ of incoming OSS triage volume cleanly. They are warm, specific, and respect the contributor's time *and* the maintainer's time.

---

## The Maintainer's Bandwidth Budget

A useful exercise during onboarding (or during a "we're behind" review): map the maintainer's *actual* triage budget vs *observed* triage demand:

```
[OPERATOR-LOCAL: Maintainer Bandwidth Audit]
1) Hours/week available for triage: ___
2) Average minutes per issue (current): ___
3) Average minutes per PR review: ___
4) Open issues: ___
5) Open PRs: ___
6) Weekly inbound rate (last 4 weeks avg): ___ issues, ___ PRs

Compute:
  Throughput = hours/week * 60 / avg_minutes
  Backlog reduction rate = throughput - inbound_rate

If backlog reduction rate is negative, the maintainer is sinking. The
options are (a) reduce inbound (stricter contribution policy, KB,
auto-templates), (b) increase per-item speed (more bulk actions,
better tooling), or (c) increase capacity (co-maintainer).

State explicitly which is being attempted.
```

If the budget is upside-down, no amount of personal heroism fixes it. The structural change has to come first.

---

## Contributor Recognition Mechanics

Contributors who are credited well stay; contributors who are credited badly leave (and tell others). Cheap, durable patterns:

- **Release notes name first-time contributors** with their handle and a one-liner on what they fixed
- **Auto-add to CONTRIBUTORS.md / `all-contributors`** so the credit is durable
- **Personal merge message**: "Thanks for catching this — clean fix" beats "merged" without comment
- **Public shoutout on first significant PR** (X / discussions) with consent

These cost the maintainer 30 seconds and create the contributor-loyalty effect that compounds over years. The opposite — silent merges, passive-aggressive review comments, ignored PRs — also compounds, in the wrong direction.

---

## Hostile Contributor Patterns (OSS-Specific)

The hostile-user runbook (`runbooks/HOSTILE-USER.md`) handles end-user hostility. OSS has a different shape: the *contributor* who turns hostile.

| Pattern | Example | Response |
|---|---|---|
| **Entitled drive-by** | "You're ignoring my PR. This is unacceptable for a project of this size." | Standard formal reply citing contribution policy; do not engage with framing |
| **Scope creep + tantrum** | PR was rejected for scope; contributor escalates publicly | Restate scope policy; offer to reopen if reduced; do not negotiate via insult |
| **Architectural fundamentalism** | "Your code is wrong because [framework] dogma" | Thank for input; explain project's stance once; do not re-litigate; lock thread if needed |
| **Public shaming via blog/X** | Contributor writes a hit piece | Owner-led public-response path (usually [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md) + [STATUS-PAGE.md](STATUS-PAGE.md) if incident-related); short factual reply; do not cross-post screenshots |
| **License-as-weapon** | "I demand you accept my PR because the license requires it" | License does not require acceptance; cite the relevant license clause; close if necessary |
| **Trademark/CoC abuse** | Filing CoC reports as a tool to force PR acceptance | Treat the report seriously *and separately*; do not conflate with the PR decision |

The discipline: *contribution decisions and behavior decisions are independent*. A contributor can have a bad PR and be a great person; they can have a great PR and be a bad person. Do not let one decide the other.

---

## Co-Maintainer Recruitment

The single biggest protection against burnout is having a co-maintainer. Recruitment patterns that work:

| Pattern | How |
|---|---|
| **Promote from within** | First, watch your top 3-5 most thoughtful contributors over 6+ months; second, offer triage-only commit access; third, after they've done that well for 3+ months, full commit |
| **Funded co-maintainer** | If revenue allows, pay a senior contributor on contract for X hours/week |
| **Org-sponsored** | If a company depends on the project, ask them to sponsor part of an engineer's time |
| **Maintainership program** | Invite known good citizens from adjacent projects to co-maintain — this often works because the skill set is similar |

Co-maintainership goes wrong when: (a) too rushed (you don't know the person well enough), (b) too informal (no agreement on scope or decision rights), (c) too ambitious (you delegate too much too fast and quality drops). The right pace is "they do triage and small reviews for 3-6 months, then big reviews, then features, then full peer."

---

## The Sabbatical Pattern

Every 12-18 months a sustainable OSS maintainer takes a 1-4 week scheduled break. Patterns:

- **Announced**: README banner + last-issue reply mention "I'll be off [date range], expect delays"
- **Auto-replied**: GitHub Action posts a friendly "we're on a break" comment on new issues, with link to community discussion forum
- **Pre-staged**: stale-bot still runs, security-disclosure path still works (security@ should not depend on the maintainer being awake)
- **Returned**: a "back-from-break" issue or post acknowledging the queue and re-prioritizing

Maintainers who take scheduled breaks last *years* longer than maintainers who don't. The community usually responds better than the maintainer fears.

---

## "No-Contributions" Policy: Doing It Honestly

If you decide policy 5 is right, do it warmly and visibly. Sample README block:

```markdown
## Contributing

Short version: this project doesn't accept external contributions
right now. It's a one-person project I ship at a pace that works
for me, and PR review is a different kind of work that would slow
that down.

What this means:
- PRs will be politely closed (don't take it personally; this is
  policy, not commentary on your code).
- Issues are very welcome — bug reports especially. Feature
  requests are read but not promised.
- You're welcome to fork; the license is [LICENSE].

If something blocks you and a fork would solve it, that's the right
move. I'd rather you have a working fork than a stuck PR.
```

Honest policy 5 generates almost no negativity. *Implicit* policy 5 (issues open, PRs ignored) generates the worst kind. The text above also models the warm tone — direct, not apologetic, not formal-cold.

---

## How This File Plugs In

| Used by | How |
|---|---|
| GITHUB-FORK.md | Provides the human-side context for the gh-CLI mechanics |
| 04-templates/ | The three OSS templates above |
| 05-policies.md | Contribution policy choice (1-5) |
| 08-voice.md | Maintainer-side tone calibration |
| Pipeline N (OSS PR review) | Imports drive-by patterns |
| Pipeline O (Drive-by hostile contributor) | Imports the hostile-contributor table |
| FAILURE-MODES.md | Adds maintainer-burnout failure modes |

---

## Cross-References

- [GITHUB-FORK.md](GITHUB-FORK.md) — gh-CLI mechanics
- [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md) §"The Maintainer's Bandwidth"
- [STATUS-PAGE.md](STATUS-PAGE.md) — incident-related public updates
- [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) — converting recurring OSS issues into roadmap/docs signals
- [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md) — base hostile-user playbook
- [KNOWLEDGE-BASE.md](KNOWLEDGE-BASE.md) and [KB-FEEDBACK-LOOP.md](KB-FEEDBACK-LOOP.md) — reducing inbound demand without dismissing reporters
- `gh-triage-ru` (companion skill) — bulk-actions for OSS triage
