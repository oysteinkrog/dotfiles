# TypeScript / Bun / Deno Recipe — Building `<tool> doctor`

## Packages (Node + Bun)

- `commander` (or `yargs`) — CLI surface
- `zod` — JSON schemas
- `proper-lockfile` — advisory file locks
- `node:crypto` — SHA-256 (stdlib)
- `node:fs` — atomic write via writeFileSync to temp + renameSync (stdlib)

`package.json`:

```json
{
  "dependencies": {
    "commander": "^12",
    "zod": "^3",
    "proper-lockfile": "^4"
  }
}
```

For Deno, use `deno.land/std` or `npm:` imports. For Bun, prefer Bun-native APIs (`Bun.write`, `Bun.file`).

## CLI surface (commander)

```typescript
import { Command } from "commander";

const program = new Command("<tool>");
const doctor = new Command("doctor")
    .description("Diagnose and (optionally) repair workspace state");

const commonOpts = (cmd: Command) => cmd
    .option("--fix", "Apply fixers for findings", false)
    .option("--dry-run", "Print the plan; do not execute", false)
    .option("--only <ids...>", "Scope to a subset")
    .option("--skip <ids...>", "Inverse of --only")
    .option("--since <run-id>", "Diff against an earlier run")
    .option("--online", "Enable network probes", false)
    .option("--explain <id>", "Expand a single finding")
    .option("--quick", "Run only fast-path detectors", false)
    .option("--json", "Stable JSON to stdout", false)
    .option("--robot", "Alias for --json with structured wrapper", false)
    .option("--quiet", "Suppress diagnostic stderr", false)
    .option("--robot-triage", "Mega-command", false)
    .option("--no-color", "Force-disable ANSI", false)
    .option("--no-progress", "Force-disable spinners", false)
    .option("-v, --verbose", "Increase verbosity (repeatable)",
        (_, prev: number) => prev + 1, 0)
    .option("--force", "Override exit-4 (requires --yes)", false)
    .option("--yes", "Skip confirmations", false);

commonOpts(doctor).action(async (opts) => { await runDiagnose(opts); });

doctor.command("diagnose").action(runDiagnose);
doctor.command("fix").action(runFix);
doctor.command("undo <run-id>")
    .option("--strict / --no-strict", "Refuse on hash mismatch", true)
    .action(runUndo);
doctor.command("explain <finding-id>").action(runExplain);
doctor.command("capabilities").action(runCapabilities);
doctor.command("health").action(runHealth);
doctor.command("robot-docs").action(runRobotDocs);
doctor.command("gc")
    .option("--before <date>", "Cutoff date")
    .action(runGc);
doctor.command("ls").action(runLs);

program.addCommand(doctor);
program.parseAsync(process.argv);
```

## `mutate()` chokepoint

```typescript
import { promises as fs, openSync, writeSync, fsyncSync, closeSync, renameSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, dirname, basename, relative } from "node:path";
import lockfile from "proper-lockfile";

export type Op =
    | { kind: "WriteFile"; content: Uint8Array; mode?: number }
    | { kind: "AppendFile"; content: Uint8Array }
    | { kind: "Rename"; target: string }
    | { kind: "Chmod"; mode: number }
    | { kind: "SymlinkAtomic"; target: string }
    | { kind: "DbExec"; sql: string }
    | { kind: "DbMigrate"; from: number; to: number };

export interface Capabilities { writeScopes: string[]; }

export interface MutateContext {
    runId: string;
    runDir: string;
    capabilities: Capabilities;
    actionsFd: number;
    actionsLock: { acquire: () => Promise<void>; release: () => void };
    fixerId: string;
    repoRoot: string;
    dryRun: boolean;
    startNs: bigint;
}

export interface ActionResult {
    ok: boolean;
    beforeHash: string;
    afterHash: string;
    error?: string;
}

function sha256Hex(buf: Uint8Array): string {
    return "sha256:" + createHash("sha256").update(buf).digest("hex");
}

async function readOrEmpty(path: string): Promise<Uint8Array> {
    try { return await fs.readFile(path); }
    catch (e: any) {
        if (e.code === "ENOENT") return new Uint8Array();
        throw e;
    }
}

async function ensureInScope(caps: Capabilities, path: string): Promise<void> {
    const abs = await realpathExistingOrParent(path);
    for (const scope of caps.writeScopes) {
        const sa = await realpathExistingOrParent(scope);
        if (abs === sa || abs.startsWith(sa + "/")) return;
    }
    throw new Error(`path ${path} outside write_scopes`);
}

async function realpathExistingOrParent(path: string): Promise<string> {
    try { return await fs.realpath(path); }
    catch (e: any) {
        if (e.code !== "ENOENT") throw e;
        return join(await fs.realpath(dirname(path)), basename(path));
    }
}

async function copyVerbatim(src: string, dst: string): Promise<void> {
    await fs.mkdir(dirname(dst), { recursive: true });
    await fs.copyFile(src, dst);
    const stat = await fs.stat(src);
    await fs.chmod(dst, stat.mode);
    await fs.utimes(dst, stat.atime, stat.mtime);
}

async function cmpStrict(a: string, b: string): Promise<void> {
    const ba = await fs.readFile(a);
    const bb = await fs.readFile(b);
    if (ba.length !== bb.length || !ba.equals(bb)) {
        throw new Error("backup verify failed (cmp-strict)");
    }
}

export async function mutate(
    ctx: MutateContext, path: string, op: Op,
): Promise<ActionResult> {
    // 1. Per-path advisory lock.
    // Lock-path uses a dotted-prefix form (foo/bar.txt -> foo/.bar.txt.doctor-lock-target)
    // so the lock target file can never collide with a real target file in the
    // sibling tree. Matches the Python/Rust/Go/Bash/JVM/Ruby/Zig/Elixir convention.
    const lockTarget = join(dirname(path), "." + basename(path) + ".doctor-lock-target");
    let release: (() => Promise<void>) | undefined;
    try {
        await fs.mkdir(dirname(path), { recursive: true });
        await fs.writeFile(lockTarget, "", { flag: "a" });
        release = await lockfile.lock(lockTarget, {
            stale: 60_000, retries: { retries: 0 },
        });
    } catch {
        return { ok: false, beforeHash: "", afterHash: "", error: "lock_held" };
    }

    try {
        // 2. before_hash.
        const before = await readOrEmpty(path);
        const beforeHash = sha256Hex(before);

        // 3. Preconditions.
        await ensureInScope(ctx.capabilities, path);

        // 4. Verbatim backup.
        const rel = relative(ctx.repoRoot, path);
        const backup = join(ctx.runDir, "backups", rel);
        if (!ctx.dryRun) {
            try { await fs.access(path); }
            catch { /* file doesn't exist; skip backup */ }
            if (await fileExists(path)) {
                await copyVerbatim(path, backup);
                await cmpStrict(path, backup);
            }
        }

        const startedNs = process.hrtime.bigint() - ctx.startNs;
        if (ctx.dryRun) {
            process.stderr.write(`[dry-run] would mutate ${path}: ${op.kind}\n`);
            return { ok: true, beforeHash, afterHash: beforeHash };
        }

        await executeAtomic(path, op);

        // 7. after_hash.
        const after = await readOrEmpty(path);
        const afterHash = sha256Hex(after);
        const finishedNs = process.hrtime.bigint() - ctx.startNs;

        // 8. Record.
        // For Rename ops, include `rename_to` so `doctor undo` can reverse
        // the move. Required per OUTPUT-SCHEMA.md § Per-op fields.
        const record: Record<string, unknown> = {
            path: rel, op: op.kind,
            before_hash: beforeHash, after_hash: afterHash,
            started_at_ns: Number(startedNs),
            finished_at_ns: Number(finishedNs),
            run_id: ctx.runId, fixer_id: ctx.fixerId,
            ok: true,
        };
        if (op.kind === "Rename" && "target" in op) {
            record.rename_to = (op as { target: string }).target;
        }
        const line = JSON.stringify(record) + "\n";
        await ctx.actionsLock.acquire();
        try {
            writeSync(ctx.actionsFd, line);
            fsyncSync(ctx.actionsFd);
        } finally { ctx.actionsLock.release(); }

        return { ok: true, beforeHash, afterHash };
    } finally {
        if (release) await release();
    }
}

async function fileExists(p: string): Promise<boolean> {
    try { await fs.access(p); return true; } catch { return false; }
}

async function executeAtomic(path: string, op: Op): Promise<void> {
    const parent = dirname(path);
    await fs.mkdir(parent, { recursive: true });
    switch (op.kind) {
        case "WriteFile": {
            const tmp = `${path}.doctor.tmp.${process.pid}`;
            const fd = openSync(tmp, "w", op.mode ?? 0o644);
            try {
                writeSync(fd, op.content);
                fsyncSync(fd);
            } finally { closeSync(fd); }
            renameSync(tmp, path);
            break;
        }
        case "AppendFile": {
            const fd = openSync(path, "a", 0o644);
            try {
                writeSync(fd, op.content);
                fsyncSync(fd);
            } finally { closeSync(fd); }
            break;
        }
        case "Rename": {
            await fs.mkdir(dirname(op.target), { recursive: true });
            await fs.rename(path, op.target);
            break;
        }
        case "Chmod":
            await fs.chmod(path, op.mode);
            break;
        case "SymlinkAtomic": {
            const tmp = join(
                dirname(path),
                `.${basename(path)}.doctor-symlink-tmp.${process.pid}.${process.hrtime.bigint()}`
            );
            await fs.symlink(op.target, tmp);
            await fs.rename(tmp, path);
            break;
        }
        default:
            throw new Error(`unknown op ${(op as any).kind}`);
    }
}
```

## Detector + Fixer pair

```typescript
import { z } from "zod";

export const FindingSchema = z.object({
    id: z.string(),
    severity: z.enum(["P0", "P1", "P2", "P3"]),
    subsystem: z.string(),
    title: z.string(),
    evidence: z.record(z.unknown()),
    remediation: z.object({
        command: z.string(),
        explain_command: z.string(),
        auto_fixable: z.boolean(),
        estimated_actions: z.number(),
    }),
});
export type Finding = z.infer<typeof FindingSchema>;

export async function detectMcpConfigDrift(repo: string): Promise<Finding | null> {
    const expected = await fs.readFile(join(repo, ".mcp.canonical.json"), "utf8");
    const actual = await fs.readFile(join(repo, ".mcp.json"), "utf8");
    if (expected === actual) return null;
    return {
        id: "fm-configs-mcp-drift",
        severity: "P2",
        subsystem: "configs",
        title: "MCP config differs from canonical",
        evidence: { file: ".mcp.json", expected_hash: sha256Hex(Buffer.from(expected)) },
        remediation: {
            command: "<tool> doctor --fix --only fm-configs-mcp-drift",
            explain_command: "<tool> doctor explain fm-configs-mcp-drift",
            auto_fixable: true,
            estimated_actions: 1,
        },
    };
}

export async function fixMcpConfigDrift(repo: string, ctx: MutateContext): Promise<void> {
    const canonical = await fs.readFile(join(repo, ".mcp.canonical.json"));
    await mutate(ctx, join(repo, ".mcp.json"),
        { kind: "WriteFile", content: canonical, mode: 0o644 });
}
```

## TTY / NO_COLOR detection

```typescript
function useColor(): boolean {
    if (process.env.NO_COLOR) return false;
    if (process.env.CI) return false;
    if (process.env.TERM === "dumb") return false;
    return process.stdout.isTTY === true;
}
```

## Signal handling

```typescript
function installSignalHandlers() {
    const handler = () => {
        // Atomic temp+rename means worst case is a .doctor.tmp.<pid> file;
        // next run's recovery detector quarantines.
        process.exit(130);
    };
    process.on("SIGINT", handler);
    process.on("SIGTERM", handler);
}
```

## Common pitfalls (TS / Node / Bun / Deno)

- **`fs.renameSync` cross-FS** is NOT atomic on Linux (works on macOS/Windows by copy+delete). Always put the temp file in `dirname(target)`.
- **`fs.writeFileSync` does NOT fsync.** Use `openSync` → `writeSync` → `fsyncSync` → `closeSync` then `renameSync`.
- **`Buffer` vs `Uint8Array`.** Some Node APIs expect `Buffer`; the modern approach is `Uint8Array` everywhere. Convert at boundaries with `Buffer.from(uint8)`.
- **`proper-lockfile.lock` returns a release function** — call it. Wrap in `try/finally`.
- **`process.hrtime.bigint()` requires `Number()` cast** for JSON emission. Beware overflow if you keep as bigint past JSON serialization.
- **Bun-native APIs**: `Bun.write` is convenient but doesn't expose fsync the same way; for the chokepoint stick with `node:fs` even on Bun for atomicity guarantees.
- **Deno**: file paths are the same; replace `node:fs` with `Deno.writeFile`, `Deno.rename`, `Deno.symlink`. Use `Deno.makeTempFile({ dir: parent })` for the atomic-rename pattern.
