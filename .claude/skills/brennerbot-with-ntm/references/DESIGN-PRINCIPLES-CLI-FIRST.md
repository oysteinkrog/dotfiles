# DESIGN-PRINCIPLES-CLI-FIRST.md — Architectural Philosophy

## Table of Contents

- Why these matter
- The 4 principles
- How they compose
- Per-principle examples
- When to break the principles
- Composition with brennerbot operations
- Anti-patterns
- Cross-references

Brennerbot's architecture is opinionated. Four principles drive every design decision:

1. **CLI-First, Not API-First** — local subscriptions over vendor APIs
2. **Deterministic Merging** — operators apply in order; same inputs → same outputs
3. **Fail-Closed Security** — features default off; explicit opt-in
4. **No-Mocks Testing** — integration tests use real (or in-memory-real) services

These principles aren't preferences. They're operational invariants — and operators of the brennerbot skill should respect them when extending or adapting.

Mined from `/dp/brenner_bot/README.md § Design Principles`.

---

## Why these matter

For agents (and operators) reading this skill: the principles explain WHY the system looks the way it does. Without them, you might "improve" it by adding API calls, async merging, opt-out security, or mock-heavy tests — and accidentally break the operational guarantees the system depends on.

---

## The 4 principles

### Principle 1: CLI-First, Not API-First

The system runs on **local CLI agent invocations**, not vendor model APIs.

Why?

- **Subscription economics**: Operators pay per subscription (Claude Code, Codex CLI, Gemini CLI), not per API token
- **No vendor lock-in**: switching models = swapping CLI binaries
- **Local-first**: sessions can run offline (corpus is local, beads are local, deltas are local)
- **Cost containment**: per-subscription rates dominate per-API-call rates at heavy use

Implications:
- All inter-pane communication via Agent Mail (HTTP MCP) + ntm (tmux), not direct model API calls
- Even tools that *could* use APIs (e.g., embedding for similarity search) prefer local models
- The web app's `/sessions/new` endpoint dispatches to CLI agents via Agent Mail, not API

Counter-intuitive consequence: this skill is **slower to spin up** (CLI agents take 5-15 sec to respond per round) than a pure-API system would be. Tradeoff is intentional.

### Principle 2: Deterministic Merging

Multiple agents emit deltas. The merger applies them in **timestamp order**, with **last-write-wins per field, merge per non-conflicting fields**.

Why?

- **Replay**: per SESSION-REPLAY-AND-REPRODUCIBILITY.md, replay must produce identical artifacts given identical inputs
- **Audit**: every change has provenance; no "phantom" changes
- **Conflict resolution**: deterministic rules avoid arbitrary tie-breaking

Implications:
- No async background merging; deltas apply synchronously
- Conflicts logged (not silently resolved); auditable
- Schema validation per delta before merging (per ARTIFACT-LINTER-RULES.md)

Counter-intuitive consequence: parallelism is **bounded** by the deterministic order. You can't speed-up by running merges in parallel; the order is the contract.

### Principle 3: Fail-Closed Security

Features that affect external state default to **off**, requiring explicit opt-in.

Examples (per `/dp/brenner_bot/apps/web/README.md` Lab Mode):

```
BRENNER_LAB_MODE=1                    # required to enable session orchestration
BRENNER_TRUST_CF_ACCESS_HEADERS=1     # explicit Cloudflare Access opt-in
BRENNER_LAB_SECRET=<secret>           # shared secret for local dev
```

Why?

- **Default-off** prevents accidental session-orchestration in misconfigured deployments
- **Defense in depth**: HMAC-based timing-safe secret comparison (per CHANGELOG.md v0.3.0)
- **Path-injection prevention**: command whitelist for experiment execution

Implications:
- Production deployments must explicitly enable each feature
- Misconfigurations fail loudly (not silently)
- Adding new features that affect external state requires opt-in flag

Counter-intuitive consequence: setting up for the first time has *more* steps than other systems. Tradeoff is intentional.

### Principle 4: No-Mocks Testing Philosophy

Tests use **real or in-memory-real** services, not mocks.

Per `/dp/brenner_bot/apps/web/README.md`:
> Agent Mail Test Server: in-memory Agent Mail for E2E (no real network I/O)

Why?

- **Mocks lie**: a mock that returns "success" doesn't tell you what the real service does
- **In-memory implementations** of real services give the real behavior at memory speed
- **Integration tests catch real failures** that unit tests with mocks miss

Implications:
- The test suite has 4500+ tests but uses real (or in-memory-real) Agent Mail, ntm, beads, and corpus
- Test fixtures are real session data, not synthetic
- E2E tests run real Playwright against real servers

Counter-intuitive consequence: the test suite is **larger and slower** than mock-heavy alternatives. Tradeoff: when tests pass, the system actually works.

---

## How they compose

The four principles reinforce each other:

- **CLI-First + Deterministic Merging** → sessions are reproducible across machines (no API-roulette)
- **Deterministic Merging + Fail-Closed Security** → audit trail is complete (every change has provenance + every feature has explicit opt-in)
- **Fail-Closed Security + No-Mocks Testing** → security tests verify real behavior, not mock-stubbed pass-throughs
- **No-Mocks Testing + CLI-First** → tests verify real CLI integration, not API-call adapters

---

## Per-principle examples

### CLI-First example

```bash
# Right (CLI-First):
# bootstrap-session.sh has already seeded "$WORKSPACE/.ntm/pipelines/".
ntm spawn RS-20260101-cell-fate --cc=1 --cod=1 --gmi=1
./scripts/register-mail-identities.sh --project-key="$WORKSPACE" --session=RS-20260101-cell-fate
ntm pipeline run "$WORKSPACE/.ntm/pipelines/brennerbot-squad.yaml" \
  --session RS-20260101-cell-fate \
  --var workspace_path="$WORKSPACE" \
  --var session_id=RS-20260101-cell-fate \
  --dry-run

# Wrong (API-First):
curl https://api.anthropic.com/v1/messages -H "Authorization: ..." -d '{ "model": "claude-opus-4-7", ... }'
# vendor lock-in; per-token costs; not local-first
```

### Deterministic Merging example

```bash
# Right (deterministic):
agent_A_message at t=100 → delta D_A
agent_B_message at t=101 → delta D_B
artifact = apply(apply(initial, D_A), D_B)  # always same result

# Wrong (non-deterministic):
artifact = parallel_apply([D_A, D_B], initial)  # order undefined; replay diverges
```

### Fail-Closed Security example

```bash
# Right (fail-closed):
if [ "${BRENNER_LAB_MODE:-}" != "1" ]; then
  echo "ERROR: BRENNER_LAB_MODE=1 not set; session orchestration disabled" >&2
  exit 2
fi

# Wrong (fail-open):
if [ "${BRENNER_LAB_MODE:-}" != "1" ]; then
  echo "WARNING: lab mode not enabled; continuing anyway" >&2
fi
```

### No-Mocks Testing example

```typescript
// Right (in-memory-real):
import { AgentMailTestServer } from "@/test-utils";
let server: AgentMailTestServer;
beforeAll(async () => { server = new AgentMailTestServer(); await server.start(); });
// tests use real Agent Mail behavior

// Wrong (mock):
jest.mock("@/lib/agent-mail-client", () => ({
  sendMessage: jest.fn().mockResolvedValue({ id: "fake-msg-id" })
}));
// mock returns synthetic; doesn't catch real Agent Mail bugs
```

---

## When to break the principles

These are *operational invariants*, not commandments. Break them when:

- **CLI-First**: in CI tests where spawning CLIs is too slow → use in-memory adapters (still real, just embedded)
- **Deterministic Merging**: never; if you're tempted, the cost is too high
- **Fail-Closed Security**: never for security-relevant features; OK for purely-local convenience features
- **No-Mocks Testing**: for performance-sensitive tests where in-memory-real is too slow → carefully-bounded mocks (rare)

If you find yourself wanting to break these regularly, the system is being used wrong.

---

## Composition with brennerbot operations

The skill operationalizes these principles:

- **CLI-First**: `MO-*` dispatches use ntm + Agent Mail, not API calls
- **Deterministic Merging**: per DELTA-PROTOCOL-FAIL-FAST.md, deltas apply in timestamp order
- **Fail-Closed Security**: T4+ sessions require explicit opt-in (per BRENNERBOT-DOCTOR-RUBRIC.md)
- **No-Mocks Testing**: when adding `scripts/`, integration tests use real beads, real ntm, real mail

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Add direct vendor-API calls "for speed" | Violates CLI-First; vendor lock-in |
| Async-merge deltas | Violates Deterministic Merging; replay breaks |
| Default-on a security feature for "convenience" | Violates Fail-Closed; misconfigurations leak |
| Mock Agent Mail in tests | Violates No-Mocks; tests lie about real behavior |
| Hide opt-in flags | Violates Fail-Closed (transparency); operators can't reason about deployment |
| Tolerate non-deterministic merging in "high-throughput" mode | Either deterministic or not; no in-between |
| Use mocks "just for unit tests" | Unit tests + integration tests both should use real-or-in-memory-real |
| Conflate "fail-soft" with "fail-closed" | Fail-soft means degraded function; fail-closed means refuse to function |

---

## Cross-references

- `DELTA-PROTOCOL-FAIL-FAST.md` — Deterministic Merging in practice
- `SESSION-REPLAY-AND-REPRODUCIBILITY.md` — replay depends on Determinism
- `BRENNERBOT-DOCTOR-RUBRIC.md` — Fail-Closed lab-mode check
- `SKILL-AS-METHODOLOGY-PATTERN.md` — meta: how this skill embodies the principles
- `BRENNERBOT-AT-SCALE.md` — at-scale operational implications
- /dp/brenner_bot/README.md § Design Principles — original source
- /dp/brenner_bot/CHANGELOG.md v0.3.0 § Security — fail-closed examples
