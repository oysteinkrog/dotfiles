# Case Study: FrankenNetworkX — `/dp/franken_networkx`

The most graph-iteration-order-sensitive port in the family. NetworkX 3.x's backend-dispatch protocol gives a clean parity surface; the rest of the gauntlet discipline is absent. Per-algorithm tie-breaking is the central engineering challenge.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | Numerical-Python-class with graph-iteration-order overlay |
| **Tier** | **T3 — Workspace** |
| **Recommended mode** | `gauntlet-full` (first proper application) |
| **Reference pinning** | `docs/contracts/networkx_version_contract.toml` likely at `networkx-3.3.x`; preflight verifies `nx.__version__`, dispatch-protocol version |
| **README claims summary** | NetworkX-API-compatible Rust graph backend via the 3.x backend-dispatch protocol; algorithm parity for traversal + shortest paths + centrality + components + PageRank + MST. Recent activity (commits `aef66579`, `9e30da94`, `017382e2`) shows GEXF hierarchy-label preservation — serialization correctness in active expansion. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ✅ via backend protocol | NetworkX dispatch gives clean parity surface |
| Negative ledger | ❌ | absent |
| cass | ❌ | absent |
| Agent Mail | ❌ | absent |
| bv | ❌ | absent |
| Math layer (§75–76) | ❌ | absent |
| MT-scale harness | ❌ | absent |
| RaptorQ | ❌ | not applicable |
| `GraphSpec` normalized comparator | ⚠️ | implicit via dispatch |
| Iteration-order golden artifacts | ⚠️ | snapshots exist; tier-classification informal |
| Parallel-traversal metamorphic | ❌ | absent |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-algorithm benches exist informally. No aggregate. No `.bench-history`.

**First 3 gaps:**
1. **No algorithm-family weighted bench** — `BFS_DFS 0.15 / ShortestPaths 0.20 / Centrality 0.20 / Components 0.10 / PageRank 0.15 / MST 0.10 / Other 0.10`.
2. **No graph-size × density × algorithm matrix** — perf cliff at degree-distribution heavy-tailed vs uniform.
3. **No `traversal_node_visit_count` exposed** — visit count is the algorithmic-correctness anchor for BFS/DFS perf claims.

### (b) Conformance — current state + first 3 gaps

**Current state.** Backend-dispatch parity gives implicit correctness; iteration-order snapshots exist; serialization roundtrips tested.

**First 3 gaps:**
1. **Parallel-traversal tie-breaking** — single-threaded BFS visits in deterministic order; parallel BFS may not. Per-fixture divergence whose root cause is the parallelism strategy.
2. **`MultisetEquivalence` vs `ExactRowMatch`** for algorithm outputs — some algorithms (e.g., centrality scores) are unique up to numerical precision; others (e.g., MST edge list) admit multiple valid outputs. Classification not formal.
3. **Hash-based graph layout** — node-iteration order depends on hash seed; under different Rust + Python hash seeds, divergence. NetworkX recently moved to `OrderedDict`-style stable iteration; the port may inherit a different order.

### (c) Surface — current state + first 3 gaps

**Current state.** Per-algorithm coverage partial; serialization-format coverage partial.

**First 3 gaps:**
1. **Algorithm enumeration** — NetworkX 3.x has 100+ algorithms; per-algorithm `present|partial|missing|excluded` not assigned.
2. **Generator coverage** (`barabasi_albert_graph`, `erdos_renyi_graph`, etc.) — random-graph generators must match seeded output.
3. **`nx.drawing` likely excluded** — matplotlib-dependent.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/franken_networkx /dp/franken_networkx__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: networkx-3.3.x
# - oracle mode: PyO3 NetworkX with backend-dispatch awareness
# - perf weights: BFS_DFS=0.15, ShortestPaths=0.20, Centrality=0.20,
#   Components=0.10, PageRank=0.15, MST=0.10, Other=0.10
# - comparator: graph spec + iteration-order snapshot + parallel traversal metamorphics
# - failure terms: hash-layout-changed, iteration-order-divergent,
#   parallel-tie-break-differs, backend-fallback-too-aggressive,
#   serialization roundtrip lost metadata, generator seed divergent

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/franken_networkx /dp/franken_networkx__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T3 × `gauntlet-full`: **14–28 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **BFS visit order from a tied-edge node differs** — parallel BFS tie-breaking.
2. **PageRank convergence threshold different** — `tol=1e-6` interpretation.
3. **Dijkstra heap implementation choice** — binary vs Fibonacci affects amortized cost.
4. **`betweenness_centrality` Brandes algorithm parallelization** — node-level vs edge-level partition.
5. **Connected-components union-find** — path compression vs not.
6. **MST Kruskal vs Prim selection** — heuristic not in contract.
7. **`floyd_warshall` cubic-time naive** — block-LU variant faster.
8. **Subgraph extraction copy-on-write** — should view, not copy.

### Conformance
1. **Iteration order of `G.nodes()` after add/remove** — hash-stability differs.
2. **BFS from node with equal-weight neighbors** — tie-breaking divergent.
3. **`shortest_path` returns multiple valid paths** — selection criterion underspecified.
4. **`isomorphism` canonical-labeling** — multiple valid canonical labels.
5. **`pagerank` damping-factor extreme** (`alpha=0.99`) — convergence-criterion sensitive.
6. **GEXF nested-hierarchy preservation** (recent fix per commit `017382e2`) — likely more nesting cases lurk.
7. **GraphML attribute-type preservation** — string vs int vs float.
8. **`relabel_nodes` with conflicting labels** — collision handling.
9. **`MultiGraph` edge-key uniqueness** — auto-key vs user-key collisions.
10. **`Graph.copy()` vs `Graph.subgraph()` mutability semantics** — view-vs-copy decisions.

### Surface
1. **Per-algorithm classification gap** — 100+ algorithms.
2. **Generators** — random + named (`petersen_graph`, etc.).
3. **`nx.algorithms.approximation` submodule** — typically partial.

---

## 6. Patterns to Apply First

1. **Full FrankenSQLite floor** — `oracle.rs`, `differential_v2.rs`, `ratchet_policy.rs`, `failure_bundle.rs`, `e2e_log_schema.rs`, `comprehensive_bench.rs`, `.bench-history/<primary_bench>.latest.json`, AGENTS.md mandate paragraph.
2. **Algorithm-family weighted benches** with the proposed weights.
3. **Iteration-order golden artifacts at Tier 3 logical** — explicit tie-breaking is the contract; capture per fixture.
4. **Parallel-traversal metamorphic** — `seq_BFS(G) ≡ par_BFS(G).sort_by_visit_order_canonical()` for reachable set + depth labels.
5. **Serialization roundtrip fixtures** — every graph fixture → serialize → deserialize → re-execute → identical result.

---

## 7. Estimated Rounds to Convergence

**10–14 rounds.**

---

## 8. Risk Register

1. **Hash-seed drift between Python and Rust runtimes.** Iteration order depends on hash seeds. *Mitigation:* pin `PYTHONHASHSEED=0`; rust port uses deterministic hasher in oracle mode.
2. **NetworkX backend-dispatch protocol changes.** Protocol is young; spec may evolve. *Mitigation:* pin to specific NetworkX minor; `migration` mode for bumps.
3. **Parallel-traversal non-determinism.** Some algorithms (e.g., parallel BFS) are inherently order-non-deterministic; metamorphic relation must respect this. *Mitigation:* `MultisetEquivalence` vs `ExactRowMatch` classification per algorithm.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `algorithm_correctness.json` — per-algorithm pass rate
- `iteration_order_compliance.json` — per-algorithm tie-breaking proof
- `serialization_roundtrip.json` — per-format Tier 1/2/3 results
- `parallel_traversal_metamorphic.json` — seq-vs-par equivalence proof

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenNetworkX](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/numerical-python-class.md](../first-bug-hunt/numerical-python-class.md)
