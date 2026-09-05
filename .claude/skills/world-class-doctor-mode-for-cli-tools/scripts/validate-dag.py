#!/usr/bin/env python3
"""validate-dag.py — assert dependency_graph.json is a DAG.

Usage: validate-dag.py <path>
Exit 0 if DAG, 2 with offending cycle on stderr if not.

Schema expected:
  {"nodes": ["fm-...", ...],
   "edges": [{"from": "fm-...", "to": "fm-..."}, ...]}
"""

import json
import sys
from pathlib import Path
from collections import defaultdict


def main():
    if len(sys.argv) != 2:
        print("usage: validate-dag.py <path>", file=sys.stderr)
        sys.exit(64)
    path = Path(sys.argv[1])
    if not path.exists():
        print(f"error: {path} does not exist", file=sys.stderr)
        sys.exit(2)
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        print(f"VIOLATION: {path}: invalid JSON — {e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict):
        print(f"VIOLATION: {path}: top-level value must be a JSON object, got {type(data).__name__}", file=sys.stderr)
        sys.exit(2)
    raw_nodes = data.get("nodes", [])
    raw_edges = data.get("edges", [])
    if not isinstance(raw_nodes, list) or not all(isinstance(n, str) and n for n in raw_nodes):
        print(f"VIOLATION: {path}: nodes must be a list of non-empty strings", file=sys.stderr)
        sys.exit(2)
    if not isinstance(raw_edges, list):
        print(f"VIOLATION: {path}: edges must be a list of objects with from/to strings", file=sys.stderr)
        sys.exit(2)

    nodes = set(raw_nodes)
    edges = []
    for i, edge in enumerate(raw_edges):
        if not isinstance(edge, dict):
            print(f"VIOLATION: {path}: edges[{i}] must be an object", file=sys.stderr)
            sys.exit(2)
        f = edge.get("from")
        t = edge.get("to")
        if not isinstance(f, str) or not f or not isinstance(t, str) or not t:
            print(f"VIOLATION: {path}: edges[{i}] must have non-empty string from/to", file=sys.stderr)
            sys.exit(2)
        edges.append((f, t))

    try:
        # Keep this guard as a final belt-and-suspenders check in case future
        # schema fields start accepting richer node identifiers.
        hash(frozenset(nodes))
    except TypeError as e:
        print(f"VIOLATION: {path}: malformed schema — unhashable node id — {e}", file=sys.stderr)
        sys.exit(2)

    adj = defaultdict(list)
    for f, t in edges:
        adj[f].append(t)
        nodes.add(f)
        nodes.add(t)

    # ITERATIVE DFS to avoid Python's recursion limit on deep graphs (>~1000
    # FMs) and to bound memory at O(N) instead of the prior recursive
    # `stack + [m]` form which was O(N²) per call due to list copies. Also
    # avoids the multi-cycle splicing bug where the prior module-level
    # `cycle` list could accumulate fragments from parallel back-edges
    # before unwinding. (Audit findings #26, #27.)
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in nodes}

    def find_cycle_from(start):
        """Iterative DFS. Returns the first cycle found as a list of
        node IDs in traversal order, or None if start's component is
        acyclic. The path stack tracks the CURRENT in-progress path
        (the "GRAY" frontier); when we encounter a GRAY edge target,
        the cycle is path[path.index(target):] + [target].
        """
        # Stack holds (node, child_iterator). path mirrors the GRAY frontier.
        path = [start]
        stack = [(start, iter(adj.get(start, [])))]
        color[start] = GRAY
        while stack:
            node, children = stack[-1]
            try:
                child = next(children)
            except StopIteration:
                # Done with this node's children; pop.
                color[node] = BLACK
                stack.pop()
                if path and path[-1] == node:
                    path.pop()
                continue
            if color.get(child, WHITE) == GRAY:
                # Back-edge → cycle. Extract the cycle from the current
                # path, starting at the target's position.
                if child in path:
                    idx = path.index(child)
                    return path[idx:] + [child]
                # Defensive: shouldn't happen if path is consistent with GRAY.
                return [child, child]
            if color.get(child, WHITE) == WHITE:
                color[child] = GRAY
                path.append(child)
                stack.append((child, iter(adj.get(child, []))))
            # BLACK children are already-finished; skip.
        return None

    for n in sorted(nodes):
        if color[n] == WHITE:
            cycle = find_cycle_from(n)
            if cycle is not None:
                print(f"CYCLE: {' -> '.join(cycle)}", file=sys.stderr)
                sys.exit(2)

    print(f"validate-dag: {path} OK ({len(nodes)} nodes, {len(edges)} edges)", file=sys.stderr)


if __name__ == "__main__":
    main()
