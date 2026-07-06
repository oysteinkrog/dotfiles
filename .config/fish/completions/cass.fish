# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
function __fish_cass_global_optspecs
	string join \n db= robot-help trace-file= q/quiet v/verbose color= progress= wrap= nowrap robot-format= h/help V/version
end

function __fish_cass_needs_command
	# Figure out if the current invocation already has a command.
	set -l cmd (commandline -opc)
	set -e cmd[1]
	argparse -s (__fish_cass_global_optspecs) -- $cmd 2>/dev/null
	or return
	if set -q argv[1]
		# Also print the command, so this can be used to figure out what it is.
		echo $argv[1]
		return 1
	end
	return 0
end

function __fish_cass_using_subcommand
	set -l cmd (__fish_cass_needs_command)
	test -z "$cmd"
	and return 1
	contains -- $cmd[1] $argv
end

complete -c cass -n "__fish_cass_needs_command" -l db -d 'Path to the `SQLite` database (defaults to platform data dir)' -r -F
complete -c cass -n "__fish_cass_needs_command" -l trace-file -d 'Trace command execution to JSONL file (spans)' -r -F
complete -c cass -n "__fish_cass_needs_command" -l color -d 'Color behavior for CLI output' -r -f -a "auto\t''
never\t''
always\t''"
complete -c cass -n "__fish_cass_needs_command" -l progress -d 'Progress output style' -r -f -a "auto\t''
bars\t''
plain\t''
none\t''"
complete -c cass -n "__fish_cass_needs_command" -l wrap -d 'Wrap informational output to N columns' -r
complete -c cass -n "__fish_cass_needs_command" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_needs_command" -l robot-help -d 'Deterministic machine-first help (wide, no TUI)'
complete -c cass -n "__fish_cass_needs_command" -s q -l quiet -d 'Reduce log noise (warnings and errors only)'
complete -c cass -n "__fish_cass_needs_command" -s v -l verbose -d 'Increase verbosity (show debug information)'
complete -c cass -n "__fish_cass_needs_command" -l nowrap -d 'Disable wrapping entirely'
complete -c cass -n "__fish_cass_needs_command" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_needs_command" -s V -l version -d 'Print version'
complete -c cass -n "__fish_cass_needs_command" -f -a "tui" -d 'Launch interactive TUI'
complete -c cass -n "__fish_cass_needs_command" -f -a "index" -d 'Run indexer'
complete -c cass -n "__fish_cass_needs_command" -f -a "completions" -d 'Generate shell completions to stdout'
complete -c cass -n "__fish_cass_needs_command" -f -a "man" -d 'Generate man page to stdout'
complete -c cass -n "__fish_cass_needs_command" -f -a "robot-docs" -d 'Machine-focused docs for automation agents'
complete -c cass -n "__fish_cass_needs_command" -f -a "search" -d 'Run a one-off search and print results to stdout'
complete -c cass -n "__fish_cass_needs_command" -f -a "pack" -d 'Build a deterministic answer pack for agent handoffs'
complete -c cass -n "__fish_cass_needs_command" -f -a "stats" -d 'Show statistics about indexed data'
complete -c cass -n "__fish_cass_needs_command" -f -a "diag" -d 'Output diagnostic information for troubleshooting'
complete -c cass -n "__fish_cass_needs_command" -f -a "storage" -d 'On-disk storage footprint breakdown by component (DB, WAL, lexical index, raw mirror, semantic, quarantine)'
complete -c cass -n "__fish_cass_needs_command" -f -a "dedup" -d 'Collapse pre-existing duplicate conversation rows (projects/<rel> vs <rel> external_id twins) created before the dedup fix'
complete -c cass -n "__fish_cass_needs_command" -f -a "status" -d 'Quick health check for agents: index freshness, db stats, recommended action'
complete -c cass -n "__fish_cass_needs_command" -f -a "capabilities" -d 'First-stop agent self-description: workflows, mistake recoveries, commands, flags, env vars, exit codes, and limits'
complete -c cass -n "__fish_cass_needs_command" -f -a "triage" -d 'One-shot agent triage: readiness, next command, workflows, docs, and schemas'
complete -c cass -n "__fish_cass_needs_command" -f -a "support-bundle" -d 'Assemble a redacted, share-safe recovery/support evidence bundle'
complete -c cass -n "__fish_cass_needs_command" -f -a "state" -d 'Quick state/health check (alias of status)'
complete -c cass -n "__fish_cass_needs_command" -f -a "api-version" -d 'Show API + contract version info'
complete -c cass -n "__fish_cass_needs_command" -f -a "introspect" -d 'Full API schema introspection - commands, arguments, and response schemas'
complete -c cass -n "__fish_cass_needs_command" -f -a "view" -d 'View a source file at a specific line (follow up on search results)'
complete -c cass -n "__fish_cass_needs_command" -f -a "health" -d 'Minimal health check (<50ms). Exit 0=healthy, 1=unhealthy. For agent pre-flight checks'
complete -c cass -n "__fish_cass_needs_command" -f -a "onboarding" -d 'First-run source onboarding + readiness wizard. Read-only: explains what CASS found, what it will index, what is missing, and the single safest next command. Scriptable via `--json`; never launches a bare TUI'
complete -c cass -n "__fish_cass_needs_command" -f -a "guide" -d 'Intent-to-command planner for guided safe workflows. Read-only: maps an operator intent (fix-ci, investigate-search-miss, prepare-release, repair-assets, export-session, onboard-source, support-capsule) to an exact safe command plan — steps, prerequisites, proof gates, forbidden shortcuts, rch target-dir hints, cost/risk, privacy notes, and stop conditions. Never mutates and never launches a bare TUI. Omit the intent to list the known intents'
complete -c cass -n "__fish_cass_needs_command" -f -a "doctor" -d 'Diagnose cass installation issues. Legacy `cass doctor --json` maps to the read-only check surface. Legacy `--fix` maps to safe-auto-run and may only apply contract-declared safe repairs'
complete -c cass -n "__fish_cass_needs_command" -f -a "context" -d 'Find related sessions for a given source path'
complete -c cass -n "__fish_cass_needs_command" -f -a "sessions" -d 'List recent sessions, with optional workspace/current-session filtering'
complete -c cass -n "__fish_cass_needs_command" -f -a "resume" -d 'Resolve a session path into a ready-to-run resume command for its native harness (Claude Code, Codex, OpenCode, pi_agent, Gemini)'
complete -c cass -n "__fish_cass_needs_command" -f -a "upgrade" -d 'Check for a newer cass release and (optionally) install it'
complete -c cass -n "__fish_cass_needs_command" -f -a "export" -d 'Export a conversation to markdown or other formats'
complete -c cass -n "__fish_cass_needs_command" -f -a "export-html" -d 'Export session as beautiful, self-contained HTML (with optional encryption)'
complete -c cass -n "__fish_cass_needs_command" -f -a "expand" -d 'Show messages around a specific line in a session file'
complete -c cass -n "__fish_cass_needs_command" -f -a "timeline" -d 'Show activity timeline for a time range'
complete -c cass -n "__fish_cass_needs_command" -f -a "pages" -d 'Export encrypted searchable archive for static hosting (P4.x)'
complete -c cass -n "__fish_cass_needs_command" -f -a "quarantine" -d 'Inspect and manage the conversation-ingest quarantine (list / clear)'
complete -c cass -n "__fish_cass_needs_command" -f -a "forget" -d 'Prune an already-indexed subset of conversations by source-path glob (dry-run by default; `--apply` to commit). Removes matching rows from the canonical DB and rebuilds derived search/analytics assets'
complete -c cass -n "__fish_cass_needs_command" -f -a "mirror" -d 'Inspect and prune raw-mirror evidence under explicit operator control'
complete -c cass -n "__fish_cass_needs_command" -f -a "sources" -d 'Manage remote sources (P5.x)'
complete -c cass -n "__fish_cass_needs_command" -f -a "models" -d 'Manage semantic search models'
complete -c cass -n "__fish_cass_needs_command" -f -a "fleet" -d 'Fleet-safe upgrade rehearsal and bounded post-upgrade verification'
complete -c cass -n "__fish_cass_needs_command" -f -a "lessons" -d 'Mine and query durable lessons from local evidence (commits, beads, proofs)'
complete -c cass -n "__fish_cass_needs_command" -f -a "swarm" -d 'Read-only swarm operations status, work packets, and coordination lint'
complete -c cass -n "__fish_cass_needs_command" -f -a "import" -d 'Import data from external sources'
complete -c cass -n "__fish_cass_needs_command" -f -a "analytics" -d 'Token usage, tool, and model analytics'
complete -c cass -n "__fish_cass_needs_command" -f -a "release-verify" -d 'Verify release distribution channels (GitHub, Homebrew, Scoop, crates.io, installer)'
complete -c cass -n "__fish_cass_needs_command" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand tui" -l asciicast -d 'Record terminal output to an asciicast v2 file; in non-interactive headless --once mode cass writes a labeled sentinel cast because no live TUI session is launched' -r -F
complete -c cass -n "__fish_cass_using_subcommand tui" -l data-dir -d 'Override data dir (matches index --data-dir)' -r -F
complete -c cass -n "__fish_cass_using_subcommand tui" -l ui-height -d 'Height of the inline UI in rows (default: 12, ignored without --inline)' -r
complete -c cass -n "__fish_cass_using_subcommand tui" -l anchor -d 'Anchor the inline UI to top or bottom of the terminal (default: bottom)' -r -f -a "top\t''
bottom\t''"
complete -c cass -n "__fish_cass_using_subcommand tui" -l record-macro -d 'Record input events to a macro file for replay/debugging' -r -F
complete -c cass -n "__fish_cass_using_subcommand tui" -l play-macro -d 'Play back a previously recorded macro file' -r -F
complete -c cass -n "__fish_cass_using_subcommand tui" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand tui" -l once -d 'Render once and exit (headless-friendly)'
complete -c cass -n "__fish_cass_using_subcommand tui" -l reset-state -d 'Delete persisted UI state (`tui_state.json`) before launch'
complete -c cass -n "__fish_cass_using_subcommand tui" -l inline -d 'Run in inline mode (UI anchored within terminal, scrollback preserved)'
complete -c cass -n "__fish_cass_using_subcommand tui" -l refresh -l catch-up -d 'Run an incremental `cass index` pass before launching the TUI so new conversations created since the last index are searchable. No-op when the index is already current; indexing errors are logged and the TUI opens on the existing index (non-fatal)'
complete -c cass -n "__fish_cass_using_subcommand tui" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand index" -l watch-once -d 'Trigger a single watch cycle for specific paths (comma-separated or repeated)' -r -F
complete -c cass -n "__fish_cass_using_subcommand index" -l watch-interval -d 'Minimum seconds between watch scan cycles (default: 30). Prevents high CPU usage from tight-loop scanning when filesystem events arrive continuously' -r
complete -c cass -n "__fish_cass_using_subcommand index" -l embedder -d 'Embedder to use for semantic indexing (hash, fastembed)' -r
complete -c cass -n "__fish_cass_using_subcommand index" -l data-dir -d 'Override data dir (index + db). Defaults to platform data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand index" -l idempotency-key -d 'Idempotency key for safe retries. If the same key is used with identical parameters, the cached result is returned. Keys expire after 24 hours' -r
complete -c cass -n "__fish_cass_using_subcommand index" -l progress-interval-ms -d 'Interval (ms) between NDJSON progress events emitted on stderr in --json/--robot mode. Clamped to [250, 60000]. Default 2000. Set --no-progress-events to disable' -r
complete -c cass -n "__fish_cass_using_subcommand index" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand index" -l full -d 'Perform full rebuild'
complete -c cass -n "__fish_cass_using_subcommand index" -l force-rebuild -l force -d 'Force Tantivy index rebuild even if schema matches'
complete -c cass -n "__fish_cass_using_subcommand index" -l watch -d 'Watch for changes and reindex automatically'
complete -c cass -n "__fish_cass_using_subcommand index" -l semantic -d 'Build semantic vector index after text indexing'
complete -c cass -n "__fish_cass_using_subcommand index" -l build-hnsw -d 'Build HNSW index for approximate nearest neighbor search (requires --semantic). Enables O(log n) search with `--approximate` flag at query time'
complete -c cass -n "__fish_cass_using_subcommand index" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand index" -l no-progress-events -d 'Suppress NDJSON progress events on stderr in --json/--robot mode. Also honored via CASS_INDEX_NO_PROGRESS_EVENTS=1 env var'
complete -c cass -n "__fish_cass_using_subcommand index" -l robot-trace-ingest -d 'Emit per-ingest-batch NDJSON timing and lookup counters on stderr for perf bisection'
complete -c cass -n "__fish_cass_using_subcommand index" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand completions" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand completions" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand man" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand man" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand robot-docs" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand robot-docs" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand search" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l limit -d 'Max results. 0 = "no limit" but is auto-capped to a RAM-proportional ceiling (1/16 of MemAvailable, clamped to [256 MiB, 16 GiB] of result-heap) so a single query can\'t tie up the whole machine. Override with CASS_SEARCH_NO_LIMIT_CAP=<hits> or CASS_SEARCH_NO_LIMIT_BYTES=<bytes>' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l offset -d 'Offset for pagination (start at Nth result)' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l fields -d 'Select specific fields in JSON output (comma-separated). Use \'minimal\' for `source_path,line_number,agent` or \'summary\' for `source_path,line_number,agent,title,score`. Example: --fields `source_path,line_number`' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l max-content-length -d 'Truncate content/snippet fields to max N characters (UTF-8 safe, adds \'...\' and _truncated indicator)' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l max-tokens -d 'Soft token budget for robot output (approx; 4 chars ≈ 1 token). Adjusts truncation' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l request-id -d 'Request ID to echo in robot _meta for correlation' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l cursor -d 'Cursor for pagination (base64-encoded offset/limit payload from previous result)' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l display -d 'Human-readable display format: table (aligned columns), lines (one-liner), markdown' -r -f -a "table\t'Aligned columns with headers (default human-readable)'
lines\t'One-liner per result with key info'
markdown\t'Markdown with role headers and code blocks'"
complete -c cass -n "__fish_cass_using_subcommand search" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand search" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS), keyword (`today`, `yesterday`, `now`), or relative offset (`-7d`, `-24h`, `-30m`, `-1w`). `allow_hyphen_values` lets the dash-prefixed forms pass clap without requiring the equals syntax (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l until -d 'Filter to entries until ISO date / keyword / relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l aggregate -d 'Server-side aggregation by field(s). Comma-separated: `agent,workspace,date,match_type` Returns buckets with counts instead of full results. Use with --limit to get both' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l timeout -d 'Timeout in milliseconds. Returns partial results and error if exceeded' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific source hostname' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l sessions-from -d 'Filter to sessions from file (one path per line). Use \'-\' for stdin. Enables chained searches: `cass search "query1" --robot-format sessions | cass search "query2" --sessions-from -`' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l mode -d 'Search mode: hybrid-preferred (default), lexical, or semantic' -r -f -a "lexical\t'Lexical (BM25) search - keyword matching'
semantic\t'Semantic search - embedding similarity'
hybrid\t'Hybrid-preferred search - RRF fusion of lexical and semantic when available'"
complete -c cass -n "__fish_cass_using_subcommand search" -l model -d 'Embedding model to use for semantic search. Available models depend on what\'s been downloaded. Use `cass models --list` to see available options' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l reranker -d 'Reranker model to use (requires --rerank). Use `cass models --list` to see available options' -r
complete -c cass -n "__fish_cass_using_subcommand search" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand search" -l json -l robot -d 'Output as JSON (--robot also works). Equivalent to --robot-format json'
complete -c cass -n "__fish_cass_using_subcommand search" -l robot-meta -d 'Include extended metadata in robot output (`elapsed_ms`, `wildcard_fallback`, `cache_stats`)'
complete -c cass -n "__fish_cass_using_subcommand search" -l today -d 'Filter to today only'
complete -c cass -n "__fish_cass_using_subcommand search" -l yesterday -d 'Filter to yesterday only'
complete -c cass -n "__fish_cass_using_subcommand search" -l week -d 'Filter to last 7 days'
complete -c cass -n "__fish_cass_using_subcommand search" -l explain -d 'Include query explanation in output (shows parsed query, index strategy, cost estimate)'
complete -c cass -n "__fish_cass_using_subcommand search" -l dry-run -d 'Validate and analyze query without executing (returns explanation, estimated cost, warnings)'
complete -c cass -n "__fish_cass_using_subcommand search" -l highlight -d 'Highlight matching terms in output (uses **bold** markers in text, <mark> in HTML)'
complete -c cass -n "__fish_cass_using_subcommand search" -l approximate -d 'Use approximate nearest neighbor (ANN) search with HNSW for faster semantic/hybrid queries. Trades slight accuracy loss for O(log n) search complexity instead of O(n). Only affects semantic and hybrid modes; ignored for lexical search. Requires an HNSW index built with `cass index --semantic --approximate`'
complete -c cass -n "__fish_cass_using_subcommand search" -l rerank -d 'Enable reranking of search results for improved relevance. Requires a reranker model to be available'
complete -c cass -n "__fish_cass_using_subcommand search" -l daemon -d 'Use daemon for warm model inference (faster repeated queries). If daemon is unavailable, falls back to direct inference'
complete -c cass -n "__fish_cass_using_subcommand search" -l no-daemon -d 'Disable daemon usage even if available (force direct inference)'
complete -c cass -n "__fish_cass_using_subcommand search" -l two-tier -d 'Enable two-tier progressive search: fast results immediately, refined via daemon. Returns initial results from fast embedder (~1ms), then refines with quality embedder via daemon (~130ms). Best of both worlds for interactive search'
complete -c cass -n "__fish_cass_using_subcommand search" -l fast-only -d 'Fast-only search: use lightweight embedder for instant results, no refinement. Ideal for real-time search-as-you-type scenarios where latency is critical'
complete -c cass -n "__fish_cass_using_subcommand search" -l quality-only -d 'Quality-only search: wait for full transformer model results. Higher latency (~130ms) but most accurate semantic matching. Requires daemon to be available; falls back to fast if unavailable'
complete -c cass -n "__fish_cass_using_subcommand search" -l refresh -l catch-up -d 'Run an incremental `cass index` pass before the search so new conversations created since the last index are matched. No-op when the index is already current; indexing errors are logged and the search runs against the existing index (non-fatal)'
complete -c cass -n "__fish_cass_using_subcommand search" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand pack" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l limit -d 'Max candidate hits to fetch before answer-pack planning. 0 uses the planner default' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l fields -d 'Select answer-pack top-level fields. Presets: minimal, summary, all' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l max-tokens -d 'Soft pack token budget' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l max-sessions -d 'Maximum distinct sessions represented in the pack' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l max-evidence -d 'Maximum evidence items selected into the pack' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l context-lines -d 'Context lines requested around evidence hits' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l max-excerpt-chars -d 'Maximum excerpt characters per evidence item' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l request-id -d 'Request ID to echo in pack metadata' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l display -d 'Human-readable display format. Only markdown is supported for pack' -r -f -a "table\t'Aligned columns with headers (default human-readable)'
lines\t'One-liner per result with key info'
markdown\t'Markdown with role headers and code blocks'"
complete -c cass -n "__fish_cass_using_subcommand pack" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand pack" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l until -d 'Filter to entries until ISO date / keyword / relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific source hostname' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l sessions-from -d 'Filter to sessions from file (one path per line). Use \'-\' for stdin' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l mode -d 'Search mode: hybrid-preferred (default), lexical, or semantic' -r -f -a "lexical\t'Lexical (BM25) search - keyword matching'
semantic\t'Semantic search - embedding similarity'
hybrid\t'Hybrid-preferred search - RRF fusion of lexical and semantic when available'"
complete -c cass -n "__fish_cass_using_subcommand pack" -l freshness-policy -d 'Freshness policy for evidence selection' -r -f -a "prefer-recent\t''
strict\t''
allow-stale\t''"
complete -c cass -n "__fish_cass_using_subcommand pack" -l freshness-window-seconds -d 'Evidence freshness window in seconds' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l timeout -d 'Timeout in milliseconds' -r
complete -c cass -n "__fish_cass_using_subcommand pack" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand pack" -l json -l robot -d 'Output as JSON (--robot also works). Equivalent to --robot-format json'
complete -c cass -n "__fish_cass_using_subcommand pack" -l today -d 'Filter to today only'
complete -c cass -n "__fish_cass_using_subcommand pack" -l yesterday -d 'Filter to yesterday only'
complete -c cass -n "__fish_cass_using_subcommand pack" -l week -d 'Filter to last 7 days'
complete -c cass -n "__fish_cass_using_subcommand pack" -l require-evidence -d 'Return an error instead of an empty successful pack'
complete -c cass -n "__fish_cass_using_subcommand pack" -l explain-selection -d 'Include selection score component details in evidence'
complete -c cass -n "__fish_cass_using_subcommand pack" -l refresh -l catch-up -d 'Run an incremental `cass index` pass before packing'
complete -c cass -n "__fish_cass_using_subcommand pack" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand stats" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand stats" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific source hostname' -r
complete -c cass -n "__fish_cass_using_subcommand stats" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand stats" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand stats" -l by-source -d 'Show breakdown by source'
complete -c cass -n "__fish_cass_using_subcommand stats" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand diag" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand diag" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand diag" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand diag" -l quarantine -d 'Include quarantine and retained-asset inspection details'
complete -c cass -n "__fish_cass_using_subcommand diag" -s v -l verbose -d 'Include verbose information (file sizes, timestamps)'
complete -c cass -n "__fish_cass_using_subcommand diag" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand storage" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand storage" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand storage" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand storage" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand dedup" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand dedup" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand dedup" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand dedup" -l apply -d 'Actually delete the duplicate rows. Without this, runs as a dry-run (inspect only, no mutation)'
complete -c cass -n "__fish_cass_using_subcommand dedup" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand status" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand status" -l stale-threshold -d 'Staleness threshold in seconds (default: 1800 = 30 minutes)' -r
complete -c cass -n "__fish_cass_using_subcommand status" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand status" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand status" -l robot-meta -d 'Include _meta block (elapsed, freshness, data_dir/db_path)'
complete -c cass -n "__fish_cass_using_subcommand status" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand capabilities" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand capabilities" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand capabilities" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand triage" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand triage" -l stale-threshold -d 'Staleness threshold in seconds (default: 300)' -r
complete -c cass -n "__fish_cass_using_subcommand triage" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand triage" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand triage" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand support-bundle" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand support-bundle" -l stale-threshold -d 'Staleness threshold in seconds (default: 300)' -r
complete -c cass -n "__fish_cass_using_subcommand support-bundle" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand support-bundle" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand support-bundle" -l include-full-paths -d 'Include full filesystem paths in the bundle (default: basename-only)'
complete -c cass -n "__fish_cass_using_subcommand support-bundle" -l include-raw-evidence -d 'Include raw session/tool payloads in the bundle (default: suppressed)'
complete -c cass -n "__fish_cass_using_subcommand support-bundle" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand state" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand state" -l stale-threshold -d 'Staleness threshold in seconds (default: 1800 = 30 minutes)' -r
complete -c cass -n "__fish_cass_using_subcommand state" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand state" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand state" -l robot-meta -d 'Include _meta block (elapsed, freshness, data_dir/db_path)'
complete -c cass -n "__fish_cass_using_subcommand state" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand api-version" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand api-version" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand api-version" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand introspect" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand introspect" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand introspect" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand view" -l source -d 'Exact source_id from search output (e.g. \'local\', \'work-laptop\')' -r
complete -c cass -n "__fish_cass_using_subcommand view" -s n -l line -d 'Line number to show (1-indexed)' -r
complete -c cass -n "__fish_cass_using_subcommand view" -s C -l context -d 'Number of context lines before/after' -r
complete -c cass -n "__fish_cass_using_subcommand view" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand view" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand view" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand health" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand health" -l stale-threshold -d 'Staleness threshold in seconds (default: 300)' -r
complete -c cass -n "__fish_cass_using_subcommand health" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand health" -l json -l robot -d 'Output as JSON (`{"healthy": bool, "latency_ms": N}`)'
complete -c cass -n "__fish_cass_using_subcommand health" -l robot-meta -d 'Include _meta block (elapsed, freshness, data_dir/db_path)'
complete -c cass -n "__fish_cass_using_subcommand health" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand onboarding" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand onboarding" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand onboarding" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand onboarding" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand guide" -l fixture -d 'Deterministic preflight-facts source: a JSON file shaped like `{ "facts": { "<fact>": true, ... }, "intent"?: "<intent>" }`' -r -F
complete -c cass -n "__fish_cass_using_subcommand guide" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand guide" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand guide" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand guide" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand doctor" -l archive-target -d 'Target directory for `cass doctor archive export|relocate`' -r -F
complete -c cass -n "__fish_cass_using_subcommand doctor" -l backup-id -d 'Backup id from `cass doctor backups list --json`' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l baseline-id -d 'Baseline id from `cass doctor baseline save|diff <id>`' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l baseline-path -d 'Explicit baseline file path for save/diff/update' -r -F
complete -c cass -n "__fish_cass_using_subcommand doctor" -l support-bundle-path -d 'Explicit support bundle directory or manifest path for verify' -r -F
complete -c cass -n "__fish_cass_using_subcommand doctor" -l sensitive-attachment -d 'Sensitive attachment path for `cass doctor support-bundle --include-sensitive-attachments`' -r -F
complete -c cass -n "__fish_cass_using_subcommand doctor" -l sensitive-attachment-max-bytes -d 'Maximum total sensitive attachment bytes copied into a support bundle' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l plan-fingerprint -d 'Plan fingerprint from `cass doctor repair --dry-run --json`' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l undo -d 'Undo the named run by id (or `latest`). Walks `<run-dir>/actions.jsonl` in reverse, verifies hashes, and restores byte-identically from the per-run backups. Refuses on any post-mutation tampering. The undo itself produces a fresh run-id' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l diff -d 'Show what `--fix` would change vs the current state. Read-only. Optional `<REF>` compares against a prior run-id instead' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l gc-before -d 'Quarantine doctor runs older than `<ISO8601>`. Renames into `<data_dir>/doctor/quarantine/runs/`; never deletes. Requires both `--gc-before` AND `--yes` (per the destructive-action gate)' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l watch-interval-ms -d 'World-class-doctor pass-6: poll interval for `--watch`. Default 5000 ms. Bounded to [500, 60000]' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l watch-iterations -d 'World-class-doctor pass-6: stop after this many polls. 0 = run forever (until SIGINT). Useful in tests + bounded automation' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l explain -d 'World-class-doctor pass-8: explain a prior run by id (or `latest`). Returns a single envelope with the run\'s manifest, every action recorded, and a flattened band timeline. Read-only' -r
complete -c cass -n "__fish_cass_using_subcommand doctor" -l recover-from-archive -d 'Rebuild the source JSONL tree from the canonical archive\'s preserved `extra_json`/`extra_bin` events into `<DIR>`, so a corrupt archive can be re-ingested from cass\'s own data with `cass index --full` (no stock-sqlite `.recover` needed). Opens the archive read-only' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand doctor" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand doctor" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l check -d 'Run the bounded read-only doctor truth surface (`cass doctor check --json`)'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l fix -d 'Legacy safe auto-run: apply only contract-declared safe repairs, preserving archive/source evidence'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l repair -d 'Hidden normalized form for `cass doctor repair ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l cleanup -d 'Hidden normalized form for `cass doctor cleanup ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l archive-scan -d 'Hidden normalized form for `cass doctor archive-scan ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l archive-normalize -d 'Hidden normalized form for `cass doctor archive-normalize ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l backups-list -d 'Hidden normalized form for `cass doctor backups list ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l backups-verify -d 'Hidden normalized form for `cass doctor backups verify ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l backups-restore -d 'Hidden normalized form for `cass doctor backups restore ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l baseline-save -d 'Hidden normalized form for `cass doctor baseline save ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l baseline-diff -d 'Hidden normalized form for `cass doctor baseline diff ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l baseline-update -d 'Hidden normalized form for `cass doctor baseline update ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l support-bundle -d 'Hidden normalized form for `cass doctor support-bundle ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l support-bundle-verify -d 'Hidden normalized form for `cass doctor support-bundle verify ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l archive-export -d 'Hidden normalized form for `cass doctor archive export ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l archive-relocate -d 'Hidden normalized form for `cass doctor archive relocate ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l archive-export-verify -d 'Hidden normalized form for `cass doctor archive export verify ...`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l include-sensitive-attachments -d 'Include explicitly provided sensitive attachments in the support bundle'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l dry-run -d 'Preview a fingerprinted repair plan without mutating any cass files'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l yes -d 'Confirm a previously inspected fingerprinted repair plan'
complete -c cass -n "__fish_cass_using_subcommand doctor" -s v -l verbose -d 'Run all checks verbosely (show passed checks too)'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l force-rebuild -l force -d 'Request a derived rebuild; never bypasses archive coverage gates or plan fingerprints'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l allow-repeated-repair -d 'Permit a mutating repair even when a previous failure marker exists'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l ls -d 'List per-run artifact directories under `<data_dir>/doctor/runs/`. Read-only. Output is JSON when combined with `--json`/`--robot`. Returns the run-id, started/ended timestamps, mode, exit_code, action_count and status (completed|incomplete|unknown) per run, newest-first'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l robot-triage -d 'Mega-command for agents: returns one envelope with summary, findings, actions_planned, recommended_command, capabilities_url. Read-only; composes the existing read-only doctor check with planning hints'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l watch -d 'World-class-doctor pass-6: long-running monitor mode. Periodically re-reads `<data_dir>/doctor/runs/` and emits one JSONL event per observed change to stdout. Stops on Ctrl+C or after `--watch-iterations`'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l emit-capabilities -d 'World-class-doctor pass-8: emit the doctor\'s extended capability surface — detectors[], fixers[], exit_codes[], data_paths[], env_vars[] — in one envelope. Read-only'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l rebuild-canonical-fts -d 'Drop and rebuild the canonical FTS5 shadow tables in place. Use when the canonical messages/conversations rows are intact but a derived FTS5 structure (e.g. fts_messages_docsize) is corrupt. Requires `--yes`; never modifies canonical rows'
complete -c cass -n "__fish_cass_using_subcommand doctor" -l cleanup-interrupted-artifacts -d 'Quarantine interrupted `raw_mirror_capture` staging artifacts that block doctor mutation, instead of forcing a manual `rm` inside the data dir. Requires `--yes`; artifacts are renamed into a quarantine dir, never deleted'
complete -c cass -n "__fish_cass_using_subcommand doctor" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand context" -l source -d 'Exact source_id from search output (e.g. \'local\', \'work-laptop\')' -r
complete -c cass -n "__fish_cass_using_subcommand context" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand context" -l limit -d 'Maximum results per relation type (default: 5)' -r
complete -c cass -n "__fish_cass_using_subcommand context" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand context" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand context" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sessions" -l workspace -d 'Filter to sessions for this workspace/project directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand sessions" -l limit -d 'Maximum sessions to return (defaults: 10, or 1 with --current)' -r
complete -c cass -n "__fish_cass_using_subcommand sessions" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand sessions" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sessions" -l current -d 'Resolve the current workspace automatically and return the most recent match'
complete -c cass -n "__fish_cass_using_subcommand sessions" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand sessions" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand resume" -l agent -d 'Override the detected harness (see `--help` for accepted values)' -r
complete -c cass -n "__fish_cass_using_subcommand resume" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand resume" -l exec -d 'Replace the current process with the resolved resume command. Mutually exclusive with `--shell` and `--json`'
complete -c cass -n "__fish_cass_using_subcommand resume" -l shell -d 'Emit a single shell-escaped command line on stdout (suitable for `eval "$(cass resume ...)"`). Mutually exclusive with `--json`'
complete -c cass -n "__fish_cass_using_subcommand resume" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand resume" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand upgrade" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand upgrade" -l check -d 'Print current vs latest version and exit. No install. Exits 0 when up to date, 1 when an update is available'
complete -c cass -n "__fish_cass_using_subcommand upgrade" -l force -d 'Bypass the 1-hour update-check cadence and re-fetch the GitHub release API immediately. Combine with `--check` to refresh status without installing'
complete -c cass -n "__fish_cass_using_subcommand upgrade" -s y -l yes -d 'Skip the interactive prompt and run the installer immediately. Suitable for scripts; mutually exclusive with `--check`'
complete -c cass -n "__fish_cass_using_subcommand upgrade" -l json -l robot -d 'Output as JSON (for automation). Combines naturally with `--check`; ignored when an install actually runs because the installer execs over the current process'
complete -c cass -n "__fish_cass_using_subcommand upgrade" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand export" -l source -d 'Exact source_id from search output (e.g. \'local\', \'work-laptop\')' -r
complete -c cass -n "__fish_cass_using_subcommand export" -l format -d 'Output format' -r -f -a "markdown\t'Markdown with headers and formatting'
text\t'Plain text'
json\t'JSON array of messages'
html\t'HTML with styling'"
complete -c cass -n "__fish_cass_using_subcommand export" -s o -l output -d 'Output file (stdout if not specified)' -r -F
complete -c cass -n "__fish_cass_using_subcommand export" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand export" -s c -l clipboard -d 'Copy the formatted export to the system clipboard instead of printing to stdout. Falls back to stdout with a stderr warning when no clipboard tool is available (e.g. headless / SSH)'
complete -c cass -n "__fish_cass_using_subcommand export" -l include-tools -d 'Include tool use details in export'
complete -c cass -n "__fish_cass_using_subcommand export" -l include-skills -d 'Include skill content in export (default: stripped for privacy)'
complete -c cass -n "__fish_cass_using_subcommand export" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l source -d 'Exact source_id from search output (e.g. \'local\', \'work-laptop\')' -r
complete -c cass -n "__fish_cass_using_subcommand export-html" -l output-dir -d 'Output directory (default: current directory)' -r -F
complete -c cass -n "__fish_cass_using_subcommand export-html" -l filename -d 'Custom filename (default: auto-generated from session metadata)' -r
complete -c cass -n "__fish_cass_using_subcommand export-html" -l theme -d 'Default theme (dark or light)' -r
complete -c cass -n "__fish_cass_using_subcommand export-html" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand export-html" -l encrypt -d 'Enable password encryption (Web Crypto compatible)'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l password-stdin -d 'Read password from stdin (secure, no echo)'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l include-tools -d 'Include tool calls in export (default: true)'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l show-timestamps -d 'Show message timestamps'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l no-cdns -d 'Disable CDN references (fully offline, larger file)'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l include-skills -d 'Include skill content in export (default: stripped for privacy). Skills injected by Claude Code/Codex contain proprietary SKILL.md content that should not appear in shared/published exports'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l dry-run -d 'Validate without writing file'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l explain -d 'Show export plan without executing'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l open -d 'Open file in browser after export'
complete -c cass -n "__fish_cass_using_subcommand export-html" -l json -l robot -d 'JSON output (for automation)'
complete -c cass -n "__fish_cass_using_subcommand export-html" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand expand" -l source -d 'Exact source_id from search output (e.g. \'local\', \'work-laptop\')' -r
complete -c cass -n "__fish_cass_using_subcommand expand" -s n -l line -d 'Line number to show context around' -r
complete -c cass -n "__fish_cass_using_subcommand expand" -s C -l context -d 'Number of messages before/after (default: 3)' -r
complete -c cass -n "__fish_cass_using_subcommand expand" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand expand" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand expand" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand timeline" -l since -d 'Start time (ISO date, \'today\', \'yesterday\', \'Nd\' for N days ago, or relative `-7d`/`-24h`/`-30m`/`-1w`). `allow_hyphen_values` lets dash-prefixed offsets pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand timeline" -l until -d 'End time (ISO date, keyword, or relative offset)' -r
complete -c cass -n "__fish_cass_using_subcommand timeline" -l agent -d 'Filter by agent (can be repeated)' -r
complete -c cass -n "__fish_cass_using_subcommand timeline" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand timeline" -l group-by -d 'Group by: hour, day, or none' -r -f -a "hour\t'Group by hour'
day\t'Group by day'
none\t'No grouping (flat list)'"
complete -c cass -n "__fish_cass_using_subcommand timeline" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific source hostname' -r
complete -c cass -n "__fish_cass_using_subcommand timeline" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand timeline" -l today -d 'Show today only'
complete -c cass -n "__fish_cass_using_subcommand timeline" -l json -l robot -d 'Output as JSON (--robot also works). Equivalent to --robot-format json'
complete -c cass -n "__fish_cass_using_subcommand timeline" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand pages" -l export-only -d 'Export only (skip wizard and encryption) to specified directory' -r -F
complete -c cass -n "__fish_cass_using_subcommand pages" -l verify -d 'Verify an existing export bundle (for CI/CD)' -r -F
complete -c cass -n "__fish_cass_using_subcommand pages" -l agents -d 'Filter by agent (comma-separated)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l workspaces -d 'Filter by workspace (comma-separated)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l since -d 'Filter entries since ISO date, keyword, or relative offset (`-7d`, `-1w`, etc.). `allow_hyphen_values` lets dash-prefixed values pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l until -d 'Filter entries until ISO date, keyword, or relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l path-mode -d 'Path mode: relative (default), basename, full, hash' -r -f -a "relative\t''
basename\t''
full\t''
hash\t''"
complete -c cass -n "__fish_cass_using_subcommand pages" -l target -d 'Deployment target: local, github, cloudflare' -r -f -a "local\t'Local export only'
github\t'GitHub Pages deployment'
cloudflare\t'Cloudflare Pages deployment'"
complete -c cass -n "__fish_cass_using_subcommand pages" -l project -d 'Cloudflare project name (also used for GitHub repo name)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l branch -d 'Cloudflare production branch (default: main)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l account-id -d 'Cloudflare account ID (or CLOUDFLARE_ACCOUNT_ID env)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l api-token -d 'Cloudflare API token (or CLOUDFLARE_API_TOKEN env)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l secrets-allow -d 'Allowlist regex patterns to suppress findings (repeatable or comma-separated)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l secrets-deny -d 'Denylist regex patterns to force findings (repeatable or comma-separated)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l preview -d 'Preview an existing export locally (starts HTTP server)' -r -F
complete -c cass -n "__fish_cass_using_subcommand pages" -l port -d 'Port for preview server (default: 8080)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l config -d 'JSON config file for non-interactive export (use "-" for stdin)' -r
complete -c cass -n "__fish_cass_using_subcommand pages" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand pages" -l dry-run -d 'Dry run (don\'t write files)'
complete -c cass -n "__fish_cass_using_subcommand pages" -l scan-secrets -d 'Scan for secrets and exit (no export)'
complete -c cass -n "__fish_cass_using_subcommand pages" -l fail-on-secrets -d 'Fail with non-zero exit if secrets are detected (for CI)'
complete -c cass -n "__fish_cass_using_subcommand pages" -l json -l robot -d 'Output results as JSON (for verify and secret scan)'
complete -c cass -n "__fish_cass_using_subcommand pages" -s v -l verbose -d 'Verbose output (show detailed check results)'
complete -c cass -n "__fish_cass_using_subcommand pages" -l no-encryption -d 'Export without encryption (DANGEROUS - all content publicly readable)'
complete -c cass -n "__fish_cass_using_subcommand pages" -l i-understand-unencrypted-risks -d 'Acknowledge unencrypted export risks (required in robot/JSON mode with --no-encryption)'
complete -c cass -n "__fish_cass_using_subcommand pages" -l no-open -d 'Don\'t auto-open browser when starting preview server'
complete -c cass -n "__fish_cass_using_subcommand pages" -l validate-config -d 'Validate config file without running export'
complete -c cass -n "__fish_cass_using_subcommand pages" -l example-config -d 'Show example config file'
complete -c cass -n "__fish_cass_using_subcommand pages" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and not __fish_seen_subcommand_from list clear retry help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand quarantine; and not __fish_seen_subcommand_from list clear retry help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and not __fish_seen_subcommand_from list clear retry help" -f -a "list" -d 'List quarantined conversations: id, schema version, attempt count, reason, age'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and not __fish_seen_subcommand_from list clear retry help" -f -a "clear" -d 'Remove quarantine entries (dry-run by default; `--apply` to clear). Optionally filter by a conversation-id substring'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and not __fish_seen_subcommand_from list clear retry help" -f -a "retry" -d 'Re-attempt retry-eligible quarantined conversations (bounded; dry-run by default). Clears eligible (legacy / version-stale) entries so they are re-ingested on the next `cass index` pass; irreducible same-version entries are reported but never cleared unless `--force-irreducible`'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and not __fish_seen_subcommand_from list clear retry help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from list" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from list" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from list" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from list" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from clear" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from clear" -l filter -d 'Only clear entries whose conversation_id contains this substring. Omit to target all entries' -r
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from clear" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from clear" -l apply -d 'Actually remove the matching entries. Without this, runs as a dry-run (inspect only)'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from clear" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from clear" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from retry" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from retry" -l max-attempts -d 'Cap the number of entries attempted in this pass (bounded, resumable). Omit to attempt every eligible entry. Deferred entries are reported, never dropped — re-run to resume' -r
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from retry" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from retry" -l force-irreducible -d 'Also retry irreducible same-version entries (an explicit operator override of the safe eligible-only default)'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from retry" -l apply -d 'Actually clear eligible entries so the next index re-ingests them. Without this, runs as a dry-run (classify only)'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from retry" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from retry" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from help" -f -a "list" -d 'List quarantined conversations: id, schema version, attempt count, reason, age'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from help" -f -a "clear" -d 'Remove quarantine entries (dry-run by default; `--apply` to clear). Optionally filter by a conversation-id substring'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from help" -f -a "retry" -d 'Re-attempt retry-eligible quarantined conversations (bounded; dry-run by default). Clears eligible (legacy / version-stale) entries so they are re-ingested on the next `cass index` pass; irreducible same-version entries are reported but never cleared unless `--force-irreducible`'
complete -c cass -n "__fish_cass_using_subcommand quarantine; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand forget" -l source-glob -d 'Glob over conversation `source_path` (e.g. `**/subagents/*.jsonl`)' -r
complete -c cass -n "__fish_cass_using_subcommand forget" -l db -d 'Override db path' -r -F
complete -c cass -n "__fish_cass_using_subcommand forget" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand forget" -l apply -d 'Actually delete the matching conversations. Without this, runs as a dry-run (inspect only)'
complete -c cass -n "__fish_cass_using_subcommand forget" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand forget" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand mirror; and not __fish_seen_subcommand_from prune help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand mirror; and not __fish_seen_subcommand_from prune help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand mirror; and not __fish_seen_subcommand_from prune help" -f -a "prune" -d 'Plan or apply raw-mirror manifest/blob retention'
complete -c cass -n "__fish_cass_using_subcommand mirror; and not __fish_seen_subcommand_from prune help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l older-than -d 'Retire captures older than a duration such as 90d, 24h, or 3600s' -r
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l max-size -d 'Retire oldest captures until unique raw blob bytes are at or below this size' -r
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l keep-tag -d 'Preserve raw mirror captures linked to conversations with this tag' -r
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l safety-hold-down -d 'Refuse to prune blobs referenced by captures newer than this duration' -r
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l dry-run -d 'Preview only. This is the default; accepted for explicit automation'
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l apply -d 'Apply the prune plan. Without this flag, cass only writes a dry-run audit record'
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from prune" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from help" -f -a "prune" -d 'Plan or apply raw-mirror manifest/blob retention'
complete -c cass -n "__fish_cass_using_subcommand mirror; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "list" -d 'List configured sources'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "add" -d 'Add a new remote source'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "remove" -d 'Remove a configured source'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "doctor" -d 'Diagnose source connectivity and configuration issues'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "sync" -d 'Synchronize sessions from remote sources'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "reingest" -d 'Re-ingest an already-synced mirror into the canonical archive WITHOUT re-running the rsync transfer'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "artifact-manifest" -d 'Build or write a lexical artifact evidence manifest for remote exchange'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "mappings" -d 'Manage path mappings for a source (P6.3)'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "agents" -d 'Manage persisted agent indexing exclusions'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "discover" -d 'Auto-discover SSH hosts from ~/.ssh/config'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "setup" -d 'Interactive wizard to discover, configure, and set up remote sources'
complete -c cass -n "__fish_cass_using_subcommand sources; and not __fish_seen_subcommand_from list add remove doctor sync reingest artifact-manifest mappings agents discover setup help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from list" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from list" -s v -l verbose -d 'Show detailed information'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from list" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from list" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from add" -l name -d 'Friendly name for this source (becomes source_id)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from add" -l preset -d 'Use preset paths for platform (macos-defaults, linux-defaults)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from add" -s p -l path -d 'Paths to sync (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from add" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from add" -l no-test -d 'Skip connectivity test'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from add" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from remove" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from remove" -l purge -d 'Also delete synced session data from index'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from remove" -s y -l yes -d 'Skip confirmation prompt'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from remove" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from doctor" -s s -l source -d 'Check only specific source (defaults to all)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from doctor" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from doctor" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from doctor" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from sync" -s s -l source -d 'Sync only specific source(s)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from sync" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from sync" -l no-index -d 'Don\'t re-index after sync'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from sync" -s v -l verbose -d 'Show detailed transfer information'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from sync" -l dry-run -d 'Dry run - show what would be synced without actually syncing'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from sync" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from sync" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from reingest" -s s -l source -d 'Re-ingest only specific source(s) (defaults to all remote sources)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from reingest" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from reingest" -l from-mirror -d 'Re-ingest from the existing mirror without re-running rsync. This is the default and only mode today; the flag documents intent and keeps the `cass sources reingest --from-mirror` spelling explicit'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from reingest" -l full -d 'Rebuild the full index from the mirror (cass index --full) instead of an incremental ingest pass'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from reingest" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from reingest" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -l index-path -d 'Exact lexical index path. Defaults to <data-dir>/index/<schema-version>' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -l data-dir -d 'Override cass data dir used to resolve the lexical index path' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -l expected-manifest -d 'Producer manifest to compare against when verifying a copied artifact' -r -F
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -l write -d 'Write evidence-bundle-manifest.json next to the lexical artifact'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -l verify-existing -d 'Verify the existing evidence-bundle-manifest.json without regenerating it'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from artifact-manifest" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from mappings" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from mappings" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from mappings" -f -a "list" -d 'List path mappings for a source'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from mappings" -f -a "add" -d 'Add a path mapping'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from mappings" -f -a "remove" -d 'Remove a path mapping by index'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from mappings" -f -a "test" -d 'Test how a path would be rewritten'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from mappings" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from agents" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from agents" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from agents" -f -a "list" -d 'List globally excluded agents/connectors'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from agents" -f -a "exclude" -d 'Exclude an agent/connector from future indexing runs'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from agents" -f -a "include" -d 'Re-include an agent/connector in future indexing runs'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from agents" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from discover" -l preset -d 'Platform preset for default paths (macos-defaults, linux-defaults)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from discover" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from discover" -l skip-existing -d 'Skip hosts that are already configured as sources'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from discover" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from discover" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l hosts -d 'Configure only these hosts (comma-separated SSH aliases, skips discovery/selection)' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l timeout -d 'SSH connection timeout in seconds' -r
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l dry-run -d 'Preview what would happen without making changes'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l non-interactive -d 'Skip interactive prompts (use auto-detected defaults for scripting)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l skip-install -d 'Skip cass installation on remotes that don\'t have it'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l skip-index -d 'Skip running `cass index` on remotes'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l skip-sync -d 'Skip syncing data after setup completes'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l resume -d 'Resume from previous interrupted setup (reads ~/.cache/cass/setup_state.json)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -s v -l verbose -d 'Show detailed progress output'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -l json -l robot -d 'Output progress as JSON (implies non-interactive, for scripting)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from setup" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "list" -d 'List configured sources'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "add" -d 'Add a new remote source'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "remove" -d 'Remove a configured source'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "doctor" -d 'Diagnose source connectivity and configuration issues'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "sync" -d 'Synchronize sessions from remote sources'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "reingest" -d 'Re-ingest an already-synced mirror into the canonical archive WITHOUT re-running the rsync transfer'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "artifact-manifest" -d 'Build or write a lexical artifact evidence manifest for remote exchange'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "mappings" -d 'Manage path mappings for a source (P6.3)'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "agents" -d 'Manage persisted agent indexing exclusions'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "discover" -d 'Auto-discover SSH hosts from ~/.ssh/config'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "setup" -d 'Interactive wizard to discover, configure, and set up remote sources'
complete -c cass -n "__fish_cass_using_subcommand sources; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -f -a "status" -d 'Show model installation status'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -f -a "install" -d 'Download and install the semantic search model'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -f -a "verify" -d 'Verify model integrity (SHA256 checksums)'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -f -a "backfill" -d 'Run one bounded semantic backfill batch from the canonical DB'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -f -a "remove" -d 'Remove model files to free disk space'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -f -a "check-update" -d 'Check for model updates'
complete -c cass -n "__fish_cass_using_subcommand models; and not __fish_seen_subcommand_from status install verify backfill remove check-update help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from status" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from status" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from status" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from install" -l model -d 'Model to install (default: all-minilm-l6-v2)' -r
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from install" -l mirror -d 'Custom HTTP(S) mirror base URL for downloading' -r
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from install" -l from-file -d 'Install from local model directory (for air-gapped environments)' -r -F
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from install" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from install" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from install" -s y -l yes -d 'Skip confirmation prompt'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from install" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from verify" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from verify" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from verify" -l repair -d 'Attempt to repair corrupted files'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from verify" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from verify" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l tier -d 'Semantic tier to backfill: fast or quality' -r
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l embedder -d 'Embedder implementation: hash or fastembed' -r
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l batch-conversations -d 'Maximum canonical conversations to process in this batch' -r
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l db -d 'Override cass DB path' -r -F
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l scheduled -l background -d 'Apply idle/load scheduler gates before running this batch'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from backfill" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from remove" -l model -d 'Model to remove (default: all-minilm-l6-v2)' -r
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from remove" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from remove" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from remove" -s y -l yes -d 'Skip confirmation prompt'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from remove" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from check-update" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from check-update" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from check-update" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from check-update" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from help" -f -a "status" -d 'Show model installation status'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from help" -f -a "install" -d 'Download and install the semantic search model'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from help" -f -a "verify" -d 'Verify model integrity (SHA256 checksums)'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from help" -f -a "backfill" -d 'Run one bounded semantic backfill batch from the canonical DB'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from help" -f -a "remove" -d 'Remove model files to free disk space'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from help" -f -a "check-update" -d 'Check for model updates'
complete -c cass -n "__fish_cass_using_subcommand models; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand fleet; and not __fish_seen_subcommand_from upgrade-rehearsal help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand fleet; and not __fish_seen_subcommand_from upgrade-rehearsal help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand fleet; and not __fish_seen_subcommand_from upgrade-rehearsal help" -f -a "upgrade-rehearsal" -d 'Rehearse the fleet-safe upgrade journey (dry run): per-host plan with archive-risk preflight, separately gated upgrade actions, and the bounded post-upgrade checks each action must clear'
complete -c cass -n "__fish_cass_using_subcommand fleet; and not __fish_seen_subcommand_from upgrade-rehearsal help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -l target-version -d 'Version the fleet is converging to (default: this binary\'s version)' -r
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -l source -d 'With `--live`, limit the probe to a single configured source by name' -r
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -l live -d 'Opt in to live SSH probes of configured remote sources. Without it the rehearsal covers the local host from cass-owned local evidence only and never contacts a remote machine'
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -l verify -d 'Also run the bounded post-upgrade check battery against the local host and emit a classified `PostUpgradeVerification`'
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from upgrade-rehearsal" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from help" -f -a "upgrade-rehearsal" -d 'Rehearse the fleet-safe upgrade journey (dry run): per-host plan with archive-risk preflight, separately gated upgrade actions, and the bounded post-upgrade checks each action must clear'
complete -c cass -n "__fish_cass_using_subcommand fleet; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand lessons; and not __fish_seen_subcommand_from list search view help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand lessons; and not __fish_seen_subcommand_from list search view help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand lessons; and not __fish_seen_subcommand_from list search view help" -f -a "list" -d 'List durable lessons mined from local evidence'
complete -c cass -n "__fish_cass_using_subcommand lessons; and not __fish_seen_subcommand_from list search view help" -f -a "search" -d 'Search durable lessons by substring over topic, summary, and applies-to'
complete -c cass -n "__fish_cass_using_subcommand lessons; and not __fish_seen_subcommand_from list search view help" -f -a "view" -d 'View one lesson by its stable lesson id'
complete -c cass -n "__fish_cass_using_subcommand lessons; and not __fish_seen_subcommand_from list search view help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l fixture -d 'Read evidence from a single lessons fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l fixture-dir -d 'Read evidence from a lessons fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l fixture-id -d 'Fixture id within --fixture-dir (resolves to `<id>.evidence.json`)' -r
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l status -d 'Lifecycle filter: active, superseded, outdated, or all' -r
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l kind -d 'Restrict to one lesson kind (e.g. gotcha, security_warning, invariant)' -r
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l limit -d 'Cap the number of lessons returned' -r
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from list" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from search" -l fixture -d 'Read evidence from a single lessons fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from search" -l fixture-dir -d 'Read evidence from a lessons fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from search" -l fixture-id -d 'Fixture id within --fixture-dir (resolves to `<id>.evidence.json`)' -r
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from search" -l limit -d 'Cap the number of lessons returned' -r
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from search" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from search" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from search" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from view" -l fixture -d 'Read evidence from a single lessons fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from view" -l fixture-dir -d 'Read evidence from a lessons fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from view" -l fixture-id -d 'Fixture id within --fixture-dir (resolves to `<id>.evidence.json`)' -r
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from view" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from view" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from view" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from help" -f -a "list" -d 'List durable lessons mined from local evidence'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from help" -f -a "search" -d 'Search durable lessons by substring over topic, summary, and applies-to'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from help" -f -a "view" -d 'View one lesson by its stable lesson id'
complete -c cass -n "__fish_cass_using_subcommand lessons; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "status" -d 'Summarize Beads, Agent Mail, git, build, cass, and evidence state'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "work-packet" -d 'Build a read-only advisory work packet for one ready bead'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "lint" -d 'Lint coordination hygiene without mutating Agent Mail, Beads, git, or reservations'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "evidence" -d 'Assemble verification evidence for recent commits or a named bead'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "proof-debt" -d 'Summarize proof debt and read-only remediation suggestions'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "failure-patterns" -d 'Mine recurring failure patterns and regression-test suggestions'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "dependency-drift" -d 'Detect pinned sibling dependency drift without mutating git or running builds'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "resource-plan" -d 'Estimate read-only resource impact for indexing, exports, and verification'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "privacy-preview" -d 'Preview privacy exposure before indexing, exporting, or support capture'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "context-pack" -d 'Select the smallest useful bead-scoped context pack under a token budget'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "workflow-analytics" -d 'Aggregate workflow outcome analytics (skills, commands, proof gates, closures)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "replay-fixture" -d 'Generate a scrubbed, deterministic replay fixture from a raw swarm timeline'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "macros" -d 'List advisory workflow macros for repeatable operator journeys'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "repro-capsule" -d 'Generate a redacted reproduction capsule for a failure or search hit'
complete -c cass -n "__fish_cass_using_subcommand swarm; and not __fish_seen_subcommand_from status work-packet lint evidence proof-debt failure-patterns dependency-drift resource-plan privacy-preview context-pack workflow-analytics replay-fixture macros repro-capsule help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from status" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from status" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from status" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from status" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from status" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from status" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from work-packet" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from work-packet" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from work-packet" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from work-packet" -l bead -d 'Build the packet for a specific bead id instead of the first ready bead' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from work-packet" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from work-packet" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from work-packet" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from lint" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from lint" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from lint" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from lint" -l bead -d 'Restrict findings to a specific bead id' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from lint" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from lint" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from lint" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from evidence" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from evidence" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from evidence" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from evidence" -l bead -d 'Restrict the evidence ledger to a specific bead id' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from evidence" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from evidence" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from evidence" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from proof-debt" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from proof-debt" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from proof-debt" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from proof-debt" -l bead -d 'Restrict the proof-debt ledger to a specific bead id' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from proof-debt" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from proof-debt" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from proof-debt" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from failure-patterns" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from failure-patterns" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from failure-patterns" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from failure-patterns" -l bead -d 'Restrict suggestions to a specific bead id' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from failure-patterns" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from failure-patterns" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from failure-patterns" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from dependency-drift" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from dependency-drift" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from dependency-drift" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from dependency-drift" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from dependency-drift" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from dependency-drift" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from resource-plan" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from resource-plan" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from resource-plan" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from resource-plan" -l action -d 'Limit the what-if output to one action' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from resource-plan" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from resource-plan" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from resource-plan" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from privacy-preview" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from privacy-preview" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from privacy-preview" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from privacy-preview" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from privacy-preview" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from privacy-preview" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from context-pack" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from context-pack" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from context-pack" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from context-pack" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from context-pack" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from context-pack" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from workflow-analytics" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from workflow-analytics" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from workflow-analytics" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from workflow-analytics" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from workflow-analytics" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from workflow-analytics" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from replay-fixture" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from replay-fixture" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from replay-fixture" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from replay-fixture" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from replay-fixture" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from replay-fixture" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from macros" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from macros" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from macros" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from macros" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from macros" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from macros" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from repro-capsule" -l fixture -d 'Read provider input from a single swarm fixture file' -r -F
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from repro-capsule" -l fixture-dir -d 'Read provider input from a swarm fixture directory' -r -f -a "(__fish_complete_directories)"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from repro-capsule" -l fixture-id -d 'Fixture id within --fixture-dir. Defaults to healthy for the pinned command shape' -r
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from repro-capsule" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from repro-capsule" -l json -l robot -d 'Output as JSON (`--robot` also works)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from repro-capsule" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "status" -d 'Summarize Beads, Agent Mail, git, build, cass, and evidence state'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "work-packet" -d 'Build a read-only advisory work packet for one ready bead'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "lint" -d 'Lint coordination hygiene without mutating Agent Mail, Beads, git, or reservations'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "evidence" -d 'Assemble verification evidence for recent commits or a named bead'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "proof-debt" -d 'Summarize proof debt and read-only remediation suggestions'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "failure-patterns" -d 'Mine recurring failure patterns and regression-test suggestions'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "dependency-drift" -d 'Detect pinned sibling dependency drift without mutating git or running builds'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "resource-plan" -d 'Estimate read-only resource impact for indexing, exports, and verification'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "privacy-preview" -d 'Preview privacy exposure before indexing, exporting, or support capture'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "context-pack" -d 'Select the smallest useful bead-scoped context pack under a token budget'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "workflow-analytics" -d 'Aggregate workflow outcome analytics (skills, commands, proof gates, closures)'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "replay-fixture" -d 'Generate a scrubbed, deterministic replay fixture from a raw swarm timeline'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "macros" -d 'List advisory workflow macros for repeatable operator journeys'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "repro-capsule" -d 'Generate a redacted reproduction capsule for a failure or search hit'
complete -c cass -n "__fish_cass_using_subcommand swarm; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand import; and not __fish_seen_subcommand_from chatgpt help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand import; and not __fish_seen_subcommand_from chatgpt help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand import; and not __fish_seen_subcommand_from chatgpt help" -f -a "chatgpt" -d 'Import ChatGPT web export (conversations.json)'
complete -c cass -n "__fish_cass_using_subcommand import; and not __fish_seen_subcommand_from chatgpt help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand import; and __fish_seen_subcommand_from chatgpt" -l output-dir -d 'Output directory (default: ChatGPT app support dir on macOS, or ~/.local/share/cass/chatgpt/ on Linux)' -r -F
complete -c cass -n "__fish_cass_using_subcommand import; and __fish_seen_subcommand_from chatgpt" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand import; and __fish_seen_subcommand_from chatgpt" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand import; and __fish_seen_subcommand_from help" -f -a "chatgpt" -d 'Import ChatGPT web export (conversations.json)'
complete -c cass -n "__fish_cass_using_subcommand import; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -f -a "status" -d 'Summary of analytics data health: row counts, freshness, coverage, drift warnings'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -f -a "tokens" -d 'Token usage over time, with dimensional breakdowns'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -f -a "tools" -d 'Per-tool invocation counts and derived metrics'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -f -a "models" -d 'Top models by usage and coverage statistics'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -f -a "rebuild" -d 'Rebuild / backfill analytics rollup tables with progress output'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -f -a "validate" -d 'Check rollup invariants and detect drift between raw data and aggregates'
complete -c cass -n "__fish_cass_using_subcommand analytics; and not __fish_seen_subcommand_from status tokens tools models rebuild validate help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS), keyword (`today`/`yesterday`/`now`), or relative offset (`-7d`/`-24h`/`-30m`/`-1w`). `allow_hyphen_values` lets dash-prefixed values pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l until -d 'Filter to entries until ISO date, keyword, or relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific hostname' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from status" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS), keyword (`today`/`yesterday`/`now`), or relative offset (`-7d`/`-24h`/`-30m`/`-1w`). `allow_hyphen_values` lets dash-prefixed values pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l until -d 'Filter to entries until ISO date, keyword, or relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific hostname' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l group-by -d 'Time bucket for aggregation' -r -f -a "hour\t'Group by hour'
day\t'Group by day'
week\t'Group by week (ISO weeks)'
month\t'Group by calendar month'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tokens" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS), keyword (`today`/`yesterday`/`now`), or relative offset (`-7d`/`-24h`/`-30m`/`-1w`). `allow_hyphen_values` lets dash-prefixed values pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l until -d 'Filter to entries until ISO date, keyword, or relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific hostname' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l group-by -d 'Time bucket for aggregation' -r -f -a "hour\t'Group by hour'
day\t'Group by day'
week\t'Group by week (ISO weeks)'
month\t'Group by calendar month'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l limit -d 'Maximum tools to return (default 20)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from tools" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS), keyword (`today`/`yesterday`/`now`), or relative offset (`-7d`/`-24h`/`-30m`/`-1w`). `allow_hyphen_values` lets dash-prefixed values pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l until -d 'Filter to entries until ISO date, keyword, or relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific hostname' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l group-by -d 'Time bucket for aggregation' -r -f -a "hour\t'Group by hour'
day\t'Group by day'
week\t'Group by week (ISO weeks)'
month\t'Group by calendar month'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from models" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS), keyword (`today`/`yesterday`/`now`), or relative offset (`-7d`/`-24h`/`-30m`/`-1w`). `allow_hyphen_values` lets dash-prefixed values pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l until -d 'Filter to entries until ISO date, keyword, or relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific hostname' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -l force -d 'Force full rebuild even if rollups appear fresh'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from rebuild" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l since -d 'Filter to entries since ISO date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS), keyword (`today`/`yesterday`/`now`), or relative offset (`-7d`/`-24h`/`-30m`/`-1w`). `allow_hyphen_values` lets dash-prefixed values pass clap (reality-check bead hr0z4)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l until -d 'Filter to entries until ISO date, keyword, or relative offset' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l days -d 'Filter to last N days' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l agent -d 'Filter by agent slug (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l workspace -d 'Filter by workspace path (can be specified multiple times)' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l source -d 'Filter by source: \'local\', \'remote\', \'all\', or a specific hostname' -r
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l data-dir -d 'Override data dir' -r -F
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l json -l robot -d 'Output as JSON (for automation)'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -l fix -d 'Attempt safe automatic repair of fixable Track A issues and report skipped non-fixable problems'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from validate" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from help" -f -a "status" -d 'Summary of analytics data health: row counts, freshness, coverage, drift warnings'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from help" -f -a "tokens" -d 'Token usage over time, with dimensional breakdowns'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from help" -f -a "tools" -d 'Per-tool invocation counts and derived metrics'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from help" -f -a "models" -d 'Top models by usage and coverage statistics'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from help" -f -a "rebuild" -d 'Rebuild / backfill analytics rollup tables with progress output'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from help" -f -a "validate" -d 'Check rollup invariants and detect drift between raw data and aggregates'
complete -c cass -n "__fish_cass_using_subcommand analytics; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l from -d 'Read a ReleaseVerifyRequest JSON from a file (or `-` for stdin) and evaluate it offline. Mutually exclusive with --live' -r -F
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l expected-version -d 'Expected release version under test (required for --live)' -r
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l repo -d 'GitHub owner/repo for the release channel (defaults to the cass repo)' -r
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l crate-name -d 'crates.io crate name (defaults to the cass crate)' -r
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l homebrew-formula-url -d 'Raw URL of the Homebrew formula file (enables the homebrew channel)' -r
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l scoop-manifest-url -d 'Raw URL of the Scoop manifest JSON (enables the scoop channel)' -r
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l robot-format -d 'Output format for robot mode (overrides --json when specified)' -r -f -a "json\t'Pretty-printed JSON object (default, backward compatible)'
jsonl\t'Newline-delimited JSON: one object per line with optional _meta header'
compact\t'Compact single-line JSON (no pretty printing)'
sessions\t'Session paths only: one source_path per line (for chained searches)'
toon\t'Token-Optimized Object Notation (encodes via toon crate)'"
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l live -d 'Gather live per-channel observations over the network (explicit opt-in)'
complete -c cass -n "__fish_cass_using_subcommand release-verify" -l json -l robot -d 'Output as JSON (`--robot` also works). Default for this command'
complete -c cass -n "__fish_cass_using_subcommand release-verify" -s h -l help -d 'Print help (see more with \'--help\')'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "tui" -d 'Launch interactive TUI'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "index" -d 'Run indexer'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "completions" -d 'Generate shell completions to stdout'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "man" -d 'Generate man page to stdout'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "robot-docs" -d 'Machine-focused docs for automation agents'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "search" -d 'Run a one-off search and print results to stdout'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "pack" -d 'Build a deterministic answer pack for agent handoffs'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "stats" -d 'Show statistics about indexed data'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "diag" -d 'Output diagnostic information for troubleshooting'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "storage" -d 'On-disk storage footprint breakdown by component (DB, WAL, lexical index, raw mirror, semantic, quarantine)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "dedup" -d 'Collapse pre-existing duplicate conversation rows (projects/<rel> vs <rel> external_id twins) created before the dedup fix'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "status" -d 'Quick health check for agents: index freshness, db stats, recommended action'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "capabilities" -d 'First-stop agent self-description: workflows, mistake recoveries, commands, flags, env vars, exit codes, and limits'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "triage" -d 'One-shot agent triage: readiness, next command, workflows, docs, and schemas'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "support-bundle" -d 'Assemble a redacted, share-safe recovery/support evidence bundle'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "state" -d 'Quick state/health check (alias of status)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "api-version" -d 'Show API + contract version info'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "introspect" -d 'Full API schema introspection - commands, arguments, and response schemas'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "view" -d 'View a source file at a specific line (follow up on search results)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "health" -d 'Minimal health check (<50ms). Exit 0=healthy, 1=unhealthy. For agent pre-flight checks'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "onboarding" -d 'First-run source onboarding + readiness wizard. Read-only: explains what CASS found, what it will index, what is missing, and the single safest next command. Scriptable via `--json`; never launches a bare TUI'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "guide" -d 'Intent-to-command planner for guided safe workflows. Read-only: maps an operator intent (fix-ci, investigate-search-miss, prepare-release, repair-assets, export-session, onboard-source, support-capsule) to an exact safe command plan — steps, prerequisites, proof gates, forbidden shortcuts, rch target-dir hints, cost/risk, privacy notes, and stop conditions. Never mutates and never launches a bare TUI. Omit the intent to list the known intents'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "doctor" -d 'Diagnose cass installation issues. Legacy `cass doctor --json` maps to the read-only check surface. Legacy `--fix` maps to safe-auto-run and may only apply contract-declared safe repairs'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "context" -d 'Find related sessions for a given source path'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "sessions" -d 'List recent sessions, with optional workspace/current-session filtering'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "resume" -d 'Resolve a session path into a ready-to-run resume command for its native harness (Claude Code, Codex, OpenCode, pi_agent, Gemini)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "upgrade" -d 'Check for a newer cass release and (optionally) install it'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "export" -d 'Export a conversation to markdown or other formats'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "export-html" -d 'Export session as beautiful, self-contained HTML (with optional encryption)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "expand" -d 'Show messages around a specific line in a session file'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "timeline" -d 'Show activity timeline for a time range'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "pages" -d 'Export encrypted searchable archive for static hosting (P4.x)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "quarantine" -d 'Inspect and manage the conversation-ingest quarantine (list / clear)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "forget" -d 'Prune an already-indexed subset of conversations by source-path glob (dry-run by default; `--apply` to commit). Removes matching rows from the canonical DB and rebuilds derived search/analytics assets'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "mirror" -d 'Inspect and prune raw-mirror evidence under explicit operator control'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "sources" -d 'Manage remote sources (P5.x)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "models" -d 'Manage semantic search models'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "fleet" -d 'Fleet-safe upgrade rehearsal and bounded post-upgrade verification'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "lessons" -d 'Mine and query durable lessons from local evidence (commits, beads, proofs)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "swarm" -d 'Read-only swarm operations status, work packets, and coordination lint'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "import" -d 'Import data from external sources'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "analytics" -d 'Token usage, tool, and model analytics'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "release-verify" -d 'Verify release distribution channels (GitHub, Homebrew, Scoop, crates.io, installer)'
complete -c cass -n "__fish_cass_using_subcommand help; and not __fish_seen_subcommand_from tui index completions man robot-docs search pack stats diag storage dedup status capabilities triage support-bundle state api-version introspect view health onboarding guide doctor context sessions resume upgrade export export-html expand timeline pages quarantine forget mirror sources models fleet lessons swarm import analytics release-verify help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from quarantine" -f -a "list" -d 'List quarantined conversations: id, schema version, attempt count, reason, age'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from quarantine" -f -a "clear" -d 'Remove quarantine entries (dry-run by default; `--apply` to clear). Optionally filter by a conversation-id substring'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from quarantine" -f -a "retry" -d 'Re-attempt retry-eligible quarantined conversations (bounded; dry-run by default). Clears eligible (legacy / version-stale) entries so they are re-ingested on the next `cass index` pass; irreducible same-version entries are reported but never cleared unless `--force-irreducible`'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from mirror" -f -a "prune" -d 'Plan or apply raw-mirror manifest/blob retention'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "list" -d 'List configured sources'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "add" -d 'Add a new remote source'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "remove" -d 'Remove a configured source'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "doctor" -d 'Diagnose source connectivity and configuration issues'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "sync" -d 'Synchronize sessions from remote sources'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "reingest" -d 'Re-ingest an already-synced mirror into the canonical archive WITHOUT re-running the rsync transfer'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "artifact-manifest" -d 'Build or write a lexical artifact evidence manifest for remote exchange'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "mappings" -d 'Manage path mappings for a source (P6.3)'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "agents" -d 'Manage persisted agent indexing exclusions'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "discover" -d 'Auto-discover SSH hosts from ~/.ssh/config'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from sources" -f -a "setup" -d 'Interactive wizard to discover, configure, and set up remote sources'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from models" -f -a "status" -d 'Show model installation status'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from models" -f -a "install" -d 'Download and install the semantic search model'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from models" -f -a "verify" -d 'Verify model integrity (SHA256 checksums)'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from models" -f -a "backfill" -d 'Run one bounded semantic backfill batch from the canonical DB'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from models" -f -a "remove" -d 'Remove model files to free disk space'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from models" -f -a "check-update" -d 'Check for model updates'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from fleet" -f -a "upgrade-rehearsal" -d 'Rehearse the fleet-safe upgrade journey (dry run): per-host plan with archive-risk preflight, separately gated upgrade actions, and the bounded post-upgrade checks each action must clear'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from lessons" -f -a "list" -d 'List durable lessons mined from local evidence'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from lessons" -f -a "search" -d 'Search durable lessons by substring over topic, summary, and applies-to'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from lessons" -f -a "view" -d 'View one lesson by its stable lesson id'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "status" -d 'Summarize Beads, Agent Mail, git, build, cass, and evidence state'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "work-packet" -d 'Build a read-only advisory work packet for one ready bead'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "lint" -d 'Lint coordination hygiene without mutating Agent Mail, Beads, git, or reservations'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "evidence" -d 'Assemble verification evidence for recent commits or a named bead'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "proof-debt" -d 'Summarize proof debt and read-only remediation suggestions'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "failure-patterns" -d 'Mine recurring failure patterns and regression-test suggestions'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "dependency-drift" -d 'Detect pinned sibling dependency drift without mutating git or running builds'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "resource-plan" -d 'Estimate read-only resource impact for indexing, exports, and verification'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "privacy-preview" -d 'Preview privacy exposure before indexing, exporting, or support capture'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "context-pack" -d 'Select the smallest useful bead-scoped context pack under a token budget'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "workflow-analytics" -d 'Aggregate workflow outcome analytics (skills, commands, proof gates, closures)'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "replay-fixture" -d 'Generate a scrubbed, deterministic replay fixture from a raw swarm timeline'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "macros" -d 'List advisory workflow macros for repeatable operator journeys'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from swarm" -f -a "repro-capsule" -d 'Generate a redacted reproduction capsule for a failure or search hit'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from import" -f -a "chatgpt" -d 'Import ChatGPT web export (conversations.json)'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from analytics" -f -a "status" -d 'Summary of analytics data health: row counts, freshness, coverage, drift warnings'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from analytics" -f -a "tokens" -d 'Token usage over time, with dimensional breakdowns'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from analytics" -f -a "tools" -d 'Per-tool invocation counts and derived metrics'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from analytics" -f -a "models" -d 'Top models by usage and coverage statistics'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from analytics" -f -a "rebuild" -d 'Rebuild / backfill analytics rollup tables with progress output'
complete -c cass -n "__fish_cass_using_subcommand help; and __fish_seen_subcommand_from analytics" -f -a "validate" -d 'Check rollup invariants and detect drift between raw data and aggregates'
