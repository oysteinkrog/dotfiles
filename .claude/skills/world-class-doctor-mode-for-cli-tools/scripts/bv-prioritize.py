#!/usr/bin/env python3
"""bv-prioritize.py — rank failure modes by graph-centrality metrics.

Phase 6 scorecard-generator currently uses static `frequency × blast_radius`
as the priority weight. This script complements that with graph-aware
prioritization: the FM whose fixer unblocks the MOST other FMs gets a
higher implementer-priority than a leaf FM with the same severity.

Reads `<workspace>/analysis/dependency_graph.json` and computes:
- in-degree (how many prerequisite FMs this one depends on)
- out-degree (how many downstream FMs this one directly unblocks)
- approximate unblock-focused PageRank (iterative, no external deps)
- topological order (build sequence)

Output: `<workspace>/prioritized_fms.jsonl` — one record per FM:
  {"fm_id": "...", "in_degree": N, "out_degree": M, "pagerank": 0.123,
   "topo_order": K, "priority_hint": "high|medium|low"}

If `bv` is installed and the dependency graph is exportable in bv format,
the script will also try `bv --robot-insights` for richer metrics. That's
optional — falls back to the local PageRank if bv isn't available or the
format conversion fails.

Usage: bv-prioritize.py <workspace>
Exit: 0 success; 64 usage; 66 missing input.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


class _UsageExitParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:  # noqa: ANN001
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


def topological_order(nodes: list[str], edges: list[tuple[str, str]]) -> list[str]:
    """Kahn's algorithm. Returns nodes in topological order; cycles are
    broken arbitrarily (caller should validate-dag.py first)."""
    in_count: dict[str, int] = {n: 0 for n in nodes}
    out_edges: dict[str, list[str]] = {n: [] for n in nodes}
    for src, dst in edges:
        if src in out_edges and dst in in_count:
            out_edges[src].append(dst)
            in_count[dst] += 1
    queue = [n for n in nodes if in_count[n] == 0]
    order = []
    while queue:
        n = queue.pop(0)
        order.append(n)
        for m in out_edges.get(n, []):
            in_count[m] -= 1
            if in_count[m] == 0:
                queue.append(m)
    # Append any leftover (cycle members) at the end.
    for n in nodes:
        if n not in order:
            order.append(n)
    return order


def pagerank(nodes: list[str], edges: list[tuple[str, str]],
             damping: float = 0.85, iterations: int = 50) -> dict[str, float]:
    """Plain iterative PageRank over unblock edges.

    The doctor's dependency graph uses A→B to mean "A must be fixed before B".
    To prioritize unblockers, rank flows in the reverse direction: B contributes
    rank back to A. Otherwise leaf dependents would outrank the prerequisites
    that actually unblock work.
    """
    if not nodes:
        return {}
    n = len(nodes)
    rank = {node: 1.0 / n for node in nodes}
    out_edges: dict[str, list[str]] = {node: [] for node in nodes}
    for src, dst in edges:
        if dst in out_edges and src in rank:
            out_edges[dst].append(src)
    for _ in range(iterations):
        new_rank = {node: (1.0 - damping) / n for node in nodes}
        for src in nodes:
            outs = out_edges[src]
            if not outs:
                # Sink: distribute rank uniformly.
                share = damping * rank[src] / n
                for node in nodes:
                    new_rank[node] += share
            else:
                share = damping * rank[src] / len(outs)
                for dst in outs:
                    new_rank[dst] += share
        rank = new_rank
    # Normalize to sum=1.0.
    total = sum(rank.values())
    if total > 0:
        rank = {k: v / total for k, v in rank.items()}
    return rank


def priority_hint(out_degree: int, pr: float, max_pr: float) -> str:
    """Coarse hint: high if PR is in the top tertile OR it unblocks >= 3 FMs."""
    if max_pr <= 0:
        return "low"
    if pr >= max_pr * 0.66 or out_degree >= 3:
        return "high"
    if pr >= max_pr * 0.33 or out_degree >= 1:
        return "medium"
    return "low"


def main() -> int:
    parser = _UsageExitParser(description=__doc__.splitlines()[0])
    parser.add_argument("workspace", help="workspace dir")
    args = parser.parse_args()
    ws = Path(args.workspace)
    if not ws.is_dir():
        print(f"bv-prioritize: {ws} not a directory", file=sys.stderr)
        return 66
    graph_path = ws / "analysis" / "dependency_graph.json"
    if not graph_path.is_file():
        print(f"bv-prioritize: no dependency_graph.json at {graph_path}",
              file=sys.stderr)
        return 66

    try:
        graph = json.loads(graph_path.read_text())
    except json.JSONDecodeError as e:
        print(f"bv-prioritize: dependency_graph.json invalid: {e}", file=sys.stderr)
        return 66

    nodes = list(graph.get("nodes", []))
    edges_raw = graph.get("edges", [])
    edges = [(e["from"], e["to"]) for e in edges_raw if "from" in e and "to" in e]

    in_degree: dict[str, int] = {n: 0 for n in nodes}
    out_degree: dict[str, int] = {n: 0 for n in nodes}
    for src, dst in edges:
        if src in out_degree:
            out_degree[src] += 1
        if dst in in_degree:
            in_degree[dst] += 1

    pr = pagerank(nodes, edges)
    topo = topological_order(nodes, edges)
    topo_index = {fm: i for i, fm in enumerate(topo)}
    max_pr = max(pr.values()) if pr else 0.0

    out_path = ws / "prioritized_fms.jsonl"
    records = []
    for fm in nodes:
        rec = {
            "fm_id": fm,
            "in_degree": in_degree[fm],
            "out_degree": out_degree[fm],
            "pagerank": round(pr.get(fm, 0.0), 6),
            "topo_order": topo_index.get(fm, -1),
            "priority_hint": priority_hint(out_degree[fm], pr.get(fm, 0.0), max_pr),
        }
        records.append(rec)

    # Sort: priority_hint desc, pagerank desc, topo_order asc.
    hint_rank = {"high": 0, "medium": 1, "low": 2}
    records.sort(key=lambda r: (hint_rank[r["priority_hint"]],
                                -r["pagerank"],
                                r["topo_order"]))
    with out_path.open("w") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"bv-prioritize: wrote {len(records)} prioritized FMs to {out_path}",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
