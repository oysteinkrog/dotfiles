# Enforcement — Redirects, Tracker Encoding, and Canarying

How to make the doctrine bind: ready-to-send redirect prompts for live
drift, mechanisms that put the rules in front of every agent at claim time,
and canaries that prove the enforcement actually works.

<!-- TOC: Redirect Prompts | Durable Law Block for AGENTS.md / CLAUDE.md | Encoding Doctrine Into the Tracker | Canary the Enforcement | Verification-Tooling Honesty | Incentive Firewall | Timeboxing -->

## Redirect Prompts

### Anti-ceremony redirect (pane or self drifting into process work)

```text
Stop. The artifact you are building (<NAME>) gates no named feature. Our goal
is working, deployable capability; process exists only to serve that. Park
the artifact, note why it was stopped, and take the highest-priority ready
capability item instead: <ITEM or 'take the top ready item'>. If you believe
the artifact IS a hard gate, reply with one sentence naming its consumer, the
feature it gates, and the observed defect class that justifies it; otherwise
drop it.
```

### Refusal-farming redirect

```text
Your recent closes are guard/refusal paths; the positive capability is still
open. A typed refusal beats a fabricated result, but it is far less valuable
than the real capability. Label the current item refusal-only, leave it open,
and implement the positive path now: <SPECIFIC POSITIVE BEHAVIOR + TEST>.
Pair every forbidden case you already wrote with a near-identical permitted
case that proceeds.
```

### Machinery freeze / render now (governance has become the ceremony)

Also works dispatched at yourself.

```text
STOP process work. We have fallen into the trap our own doctrine forbids:
<N> rounds of <schema/validator/audit/review> work while the deliverable
stands at <X>/<Y>. Effective immediately:
1. Machinery is FROZEN at current HEAD. The existing checks are sufficient to
   keep authoring honest. Record deferred rigor as an explicit debt list; do
   not build it.
2. Begin producing the actual deliverable NOW, in bounded batches, with
   <verification floor> after each batch.
3. Reviews are welcome on CONTENT (deliverable quality, correctness), not on
   machinery. No new machinery demands until the deliverable is done.
The deliverable is the deliverable. Acknowledge and start.
```

### Credit-rules module (append to any start-of-session or wave dispatch)

```text
CREDIT RULES (binding):
- Real code + real tests in the SAME work item. No todo!()/unimplemented!()
  in commits. No faked tests, no fixtures/mocks presented as live proof, no
  weakened assertions, no golden regeneration to force green, no hard-coded
  success paths.
- Refusal-only implementation never closes a positive-capability item. Label
  it refusal-only and leave it open; it reads as unfinished, not shipped.
- Process artifacts (certificates, ledgers, reports, matrices) are NOT
  progress. Create one only if it is a hard gate for a named feature, and
  name its consumer, gate, observed defect class, and deletion condition.
- Only the independent verifier closes items, citing green evidence. Never
  close your own or a peer's item. False closes are reopened with an
  incident comment.
- Claim the highest-priority ready item, not the most comfortable one.
- Commit rate is not a KPI. Splitting work to harvest closures is treated as
  reward hacking.
- If blocked on something external, mark blocked naming the exact missing
  thing AND the substitutes you are forbidden to fake it with. Waiting earns
  zero credit.
- If no independent verifier exists (solo session), re-verify by
  re-execution against the original acceptance criteria before reporting
  done, and state what was not independently verified.
- Never silence stderr in a command whose output you will cite as evidence.
```

### Joint-freeze protocol module (multi-agent structure ownership)

```text
DECISION PROTOCOL (binding): propose structural decisions as NUMBERED items;
the counterparty replies ACCEPT or counters by item number; silence is not
acceptance. No repository or tracker mutation while acceptance is pending.
Every freeze cites its agreement artifact (message ID + commit SHA). If you
find a violated invariant, send STOP with reproducible evidence; work on
that surface halts until dispositioned. When shown contradicting durable
evidence, concede in full with the exact confounder chain, on the record.
Reviews of committed work re-execute the committed tool/tests at HEAD and
report observed output, never impressions of the diff.
```

## Durable Law Block for AGENTS.md / CLAUDE.md

Offered only in interactive use (see SKILL.md), appended verbatim to
whichever standing-instructions file the project uses. It is deliberately
compact: durable law, not per-item specifics.

```markdown
## Honest Work and Anti-Ceremony (binding for agents and humans alike)

The purpose of agent work here is working, deployable capability. Process
serves that outcome and never becomes the product.

- A process artifact (certificate, ledger, dashboard, matrix, meta-report,
  speculative check) may be created only if it names a concrete consumer,
  the named feature it gates, the observed defect class justifying it, and
  its deletion condition. Otherwise it does not get created. Boundary test:
  if running code branches on it, it is product; if only humans and status
  reports read it, it is process and the creation-gate rule above applies;
  code written just to flip this answer counts as the pathology, not as a
  consumer. Sole exception: a minimal
  integrity/recovery control (crash-recovery state, provenance snapshot) is
  legitimate when it prevents a named evidence-loss or corruption mode and
  is necessary and minimal.
- Real code + real tests in the same unit of work. Forbidden: faked tests,
  fixtures/mocks presented as live proof, weakened assertions, golden
  regeneration to force green, hard-coded success paths, placeholder macros
  in commits, editing the spec instead of implementing it, narrowing scope
  while claiming full success.
- No self-certification: work is closed by an independent verifier citing
  evidence at an exact revision. Solo sessions re-verify by re-execution and
  state what was not independently verified.
- A typed refusal beats a fabricated result and is less valuable than the
  real capability; refusal-only work stays open and says so.
- Truthful null results ("checked X, found no material increment") are
  successful outcomes. Unsupported claims are worse than silence.
- Metrics predeclare denominator and countermetric; agreement between
  agents may raise confidence but is never independent evidence; never
  silence stderr in evidence-bearing commands.
- Name these pathologies when they occur (gate self-weakening, proof-class
  inflation, golden regeneration, tolerance widening, suppression-pragma
  laundering, refusal farming, follow-up laundering); the names are the
  deterrent. The full catalog with countermeasures lives in the
  just-say-no-to-process-porn-and-ceremony skill; ask the operator for it
  if you cannot resolve that reference.
```

When appending, keep the project's existing heading conventions, and do not
duplicate rules the file already states; every frozen rule needs exactly
one canonical owner, and copies drift.

## Encoding Doctrine Into the Tracker

Doctrine that lives only in the operator's head, or in a file workers never
read, does not bind the swarm. Make it legible at the moment of claim.
Five mechanisms, strongest first (described in beads/`br` terms; adapt to
any tracker):

1. **Root meta item with inherited context.** One program-root item carrying
   ~10 binding rules as structured agent context, inherited by every
   descendant, so doctrine reaches all workers at claim time. It is never a
   claimable work item, and it closes exactly when the release join closes,
   never on process output.
2. **Frozen checkbox acceptance criteria on every executable leaf.** Written
   by the structure owner; implementers check boxes, never weaken, edit, or
   delete them. Profile: Positive (observable behavior through the public
   surface) / Negative (planted red a naive wrong implementation fails) /
   Tests (exact targets) / Proof class (permitted fixtures; forbidden
   substitutes) / Consumers (named downstream items) / **No-claim** (what
   green here does NOT prove). The No-Claim line is the single
   highest-leverage line: it pre-writes what a green result cannot be
   claimed to prove, making proof-class inflation a violation of the item's
   own text.
3. **Policy-enforced state machine, not etiquette.** Strict transitions;
   poison gates so the only reachable close route runs through independent
   verification; no bypass flag; minimum close reason; self-close forbidden;
   capacity caps as verification-debt bounds; meta items can never enter the
   ready pool. Know which invariants the CLI enforces and which the
   orchestrator must police; the second kind silently decays when you stop
   checking.
4. **Blocked-born external leaves.** Work waiting on an external
   authority/credential/subject is born blocked, naming (a) the exact
   missing external thing and (b) the forbidden substitutes an agent would
   be tempted to fake it with. If no live route exists at release time, the
   release reports BLOCKED on external proof, never green with a footnote.
5. **Attribution and ownership.** Every tracker mutation carries an actor;
   one structure owner at a time owns graph structure; implementation agents
   change only status/assignee/comments on items they claim.

## Canary the Enforcement

Policy files are claims, not facts. Before the first real wave, canary with
disposable items, keeping all stderr:

1. attempt an illegal direct close → must be refused;
2. attempt a second concurrent claim for one assignee → refused, or caught
   by orchestrator preflight (know which);
3. attempt a close without the verification gate → refused;
4. verify gate results are revision-scoped: a PASS recorded against an
   earlier revision must not satisfy a later close after rework;
5. verify inherited context actually appears on leaf items;
6. verify the dependency graph is cycle-free after each structural batch.

One real startup canary found the tracker silently dropped unrecognized
policy keys, did not enforce capacity on claim, and allowed close without
the gate: three invariants the operators believed were CLI-enforced and
were not. Had they stamped 900 items before canarying, every wave would
have run on imaginary rails. Re-canary after any tracker upgrade.

## Verification-Tooling Honesty

A validator that overstates its own coverage is proof-class inflation with
extra steps. When building validators, planners, or audit tools:

- **Partial modes never emit PASS.** A run over partial input reports
  INCOMPLETE with a nonzero exit. (A real reviewer STOP: a validator exited
  0/PASS on 16 of 1,520 required nodes while hiding 90 undispositioned
  rows.)
- **FAIL before INCOMPLETE.** Structural defects short-circuit as FAIL; only
  a structurally clean partial input may be called INCOMPLETE; otherwise
  "it's just partial" masks real defects.
- **Carry your own gaps in every output.** An explicit unimplemented-checks
  list attaches to every report; an audit can never go green while a
  required check is unimplemented; the honest result is UNAVAILABLE, not
  PASS-by-omission.
- **No weak digests.** If a sign-off digest cannot yet bind everything it
  must, emit no digest at all with a note; a weak digest is sign-off
  theater.
- **Agreed baselines refuse silent refresh.** Overwriting an agreed snapshot
  requires an explicit force flag; drift is a red flag, not a refresh.
- **Mutation is a separate, guarded mode.** Read modes never mutate; the
  apply mode requires current actor identity and an approval reference as
  runtime arguments, never tool constants.

## Incentive Firewall (What to Tell Working Agents)

Never tell agents: they must be unique or disagree; they are rewarded for
findings, criticism, novelty, confidence, or verbosity; another agent is
their antagonist; the report needs tension; a null result looks
unproductive.

Do tell them: the exact object-level question; evidence access and
boundaries; valid operations and outputs; that null and blocked outcomes
are allowed; that unsupported material claims are worse than silence; that
useful object-level work remains expected when a requested conclusion turns
out to be unsupported.

## Timeboxing (the Enforcement Is Also Subject to the Rules)

- Standing up the whole enforcement stack is one session, not a project.
- Adapt the templates; don't redesign them.
- Any review round about the apparatus (not about work-item content) beyond
  the second is the meta-trap firing. Ship.
- Keep the checks that catch defects; kill the rounds that only deepen the
  apparatus. Machinery is reconciled later as a derivative of the delivered
  thing; the delivered thing never waits on machinery completeness.
