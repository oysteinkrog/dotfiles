# Go Recipe — Building `<tool> doctor`

## Modules

- `github.com/spf13/cobra` — CLI surface
- `encoding/json` — JSON shapes (stdlib)
- `crypto/sha256` — hashing (stdlib)
- `golang.org/x/sys/unix` (or `syscall.Flock`) — advisory file locks
- `golang.org/x/term` — TTY detection
- `os/signal` — SIGINT/SIGTERM handling

`go.mod`:

```
require (
    github.com/spf13/cobra v1.8.0
    golang.org/x/sys v0.16.0
    golang.org/x/term v0.16.0
)
```

## CLI surface (cobra)

```go
package cmd

import (
    "encoding/json"
    "fmt"
    "os"
    "github.com/spf13/cobra"
)

var doctorCmd = &cobra.Command{
    Use:   "doctor",
    Short: "Diagnose and (optionally) repair workspace state",
    RunE: func(cmd *cobra.Command, args []string) error {
        // Default subcommand is "diagnose"
        return runDiagnose(cmd, args)
    },
}

var (
    flagFix         bool
    flagDryRun      bool
    flagOnly        []string
    flagSkip        []string
    flagSince       string
    flagOnline      bool
    flagExplain     string
    flagQuick       bool
    flagJSON        bool
    flagRobot       bool
    flagQuiet       bool
    flagRobotTriage bool
    flagNoColor     bool
    flagNoProgress  bool
    flagVerbose     int
    flagForce       bool
    flagYes         bool
)

func init() {
    pf := doctorCmd.PersistentFlags()
    pf.BoolVar(&flagFix, "fix", false, "Apply fixers for findings")
    pf.BoolVar(&flagDryRun, "dry-run", false, "Print the plan; do not execute")
    pf.StringSliceVar(&flagOnly, "only", nil, "Scope to a subset")
    pf.StringSliceVar(&flagSkip, "skip", nil, "Inverse of --only")
    pf.StringVar(&flagSince, "since", "", "Diff against an earlier run")
    pf.BoolVar(&flagOnline, "online", false, "Enable network probes")
    pf.StringVar(&flagExplain, "explain", "", "Expand a single finding")
    pf.BoolVar(&flagQuick, "quick", false, "Run only fast-path detectors")
    pf.BoolVar(&flagJSON, "json", false, "Stable JSON to stdout")
    pf.BoolVar(&flagRobot, "robot", false, "Alias for --json with structured wrapper")
    pf.BoolVar(&flagQuiet, "quiet", false, "Suppress diagnostic stderr")
    pf.BoolVar(&flagRobotTriage, "robot-triage", false, "Mega-command")
    pf.BoolVar(&flagNoColor, "no-color", false, "Force-disable ANSI")
    pf.BoolVar(&flagNoProgress, "no-progress", false, "Force-disable spinners")
    pf.CountVarP(&flagVerbose, "verbose", "v", "Verbosity")
    pf.BoolVar(&flagForce, "force", false, "Override exit-4 (requires --yes)")
    pf.BoolVar(&flagYes, "yes", false, "Skip confirmations")

    doctorCmd.AddCommand(doctorDiagnoseCmd)
    doctorCmd.AddCommand(doctorFixCmd)
    doctorCmd.AddCommand(doctorUndoCmd)
    doctorCmd.AddCommand(doctorExplainCmd)
    doctorCmd.AddCommand(doctorCapabilitiesCmd)
    doctorCmd.AddCommand(doctorHealthCmd)
    doctorCmd.AddCommand(doctorRobotDocsCmd)
    doctorCmd.AddCommand(doctorGcCmd)
    doctorCmd.AddCommand(doctorLsCmd)

    rootCmd.AddCommand(doctorCmd)
}
```

## `mutate()` chokepoint

```go
package doctor

import (
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "io"
    "os"
    "path/filepath"
    "sync"
    "syscall"
    "time"
)

type Op struct {
    Kind   string `json:"kind"` // "WriteFile" | "AppendFile" | "Rename" | "Chmod" | "SymlinkAtomic" | "DbExec" | "DbMigrate"
    Bytes  []byte `json:"-"`
    Mode   uint32 `json:"mode,omitempty"`
    Target string `json:"target,omitempty"` // for rename / symlink
    SQL    string `json:"sql,omitempty"`
}

type Capabilities struct {
    WriteScopes []string
}

type MutateContext struct {
    RunID         string
    RunDir        string
    Capabilities  *Capabilities
    ActionsFile   *os.File
    actionsMu     sync.Mutex
    FixerID       string
    RepoRoot      string
    DryRun        bool
    StartNS       int64
}

type ActionResult struct {
    OK         bool
    BeforeHash string
    AfterHash  string
    Err        error
}

type ActionRecord struct {
    Path         string `json:"path"`
    Op           string `json:"op"`
    BeforeHash   string `json:"before_hash"`
    AfterHash    string `json:"after_hash"`
    StartedAtNS  int64  `json:"started_at_ns"`
    FinishedAtNS int64  `json:"finished_at_ns"`
    RunID        string `json:"run_id"`
    FixerID      string `json:"fixer_id"`
    OK           bool   `json:"ok"`
    // RenameTo is the destination for Op{Kind:"Rename"}. doctor undo reads
    // this to reverse the move. Required for renames per OUTPUT-SCHEMA.md
    // § Per-op fields. Empty (omitted from JSON) for other ops.
    RenameTo     string `json:"rename_to,omitempty"`
    Error        string `json:"error,omitempty"`
    RolledBack   bool   `json:"rolled_back,omitempty"`
}

func sha256Hex(b []byte) string {
    h := sha256.Sum256(b)
    return "sha256:" + hex.EncodeToString(h[:])
}

func readOrEmpty(path string) ([]byte, error) {
    b, err := os.ReadFile(path)
    if err != nil && os.IsNotExist(err) {
        return nil, nil
    }
    return b, err
}

func ensureInScope(caps *Capabilities, path string) error {
    abs, err := realpathExistingOrParent(path)
    if err != nil { return err }
    for _, s := range caps.WriteScopes {
        sa, err := realpathExistingOrParent(s)
        if err != nil { return err }
        rel, err := filepath.Rel(sa, abs)
        if err == nil && !startsWithDotDot(rel) {
            return nil
        }
    }
    return fmt.Errorf("path %s outside write_scopes", path)
}

func realpathExistingOrParent(path string) (string, error) {
    if real, err := filepath.EvalSymlinks(path); err == nil {
        return filepath.Abs(real)
    }
    parent, err := filepath.EvalSymlinks(filepath.Dir(path))
    if err != nil { return "", err }
    return filepath.Abs(filepath.Join(parent, filepath.Base(path)))
}

func startsWithDotDot(rel string) bool {
    return rel == ".." || (len(rel) >= 3 && rel[:3] == "../")
}

func copyVerbatim(src, dst string) error {
    if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
        return err
    }
    in, err := os.Open(src)
    if err != nil { return err }
    defer in.Close()
    out, err := os.OpenFile(dst, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0o600)
    if err != nil { return err }
    defer out.Close()
    if _, err := io.Copy(out, in); err != nil { return err }
    if err := out.Sync(); err != nil { return err }
    info, err := os.Stat(src)
    if err != nil { return err }
    return os.Chmod(dst, info.Mode())
}

func cmpStrict(a, b string) error {
    ba, err := os.ReadFile(a); if err != nil { return err }
    bb, err := os.ReadFile(b); if err != nil { return err }
    if string(ba) != string(bb) {
        return fmt.Errorf("backup verify failed (cmp-strict)")
    }
    return nil
}

func acquireFlock(path string) (*os.File, error) {
    // Lock-path uses a dotted-prefix form (matches Python, Rust, Bash, JVM
    // recipes) so the lock can never collide with a real target file:
    // given foo/bar.txt, the lock is foo/.bar.txt.doctor-lock.
    dir := filepath.Dir(path)
    base := filepath.Base(path)
    lockPath := filepath.Join(dir, "."+base+".doctor-lock")
    f, err := os.OpenFile(lockPath, os.O_RDWR|os.O_CREATE, 0o600)
    if err != nil { return nil, err }
    if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
        f.Close()
        return nil, fmt.Errorf("lock_held")
    }
    return f, nil
}

func Mutate(ctx *MutateContext, path string, op Op) (ActionResult, error) {
    lock, err := acquireFlock(path)
    if err != nil { return ActionResult{}, err }
    defer lock.Close()

    before, err := readOrEmpty(path)
    if err != nil { return ActionResult{}, err }
    beforeHash := sha256Hex(before)

    if err := ensureInScope(ctx.Capabilities, path); err != nil {
        return ActionResult{}, err
    }

    rel, _ := filepath.Rel(ctx.RepoRoot, path)
    backup := filepath.Join(ctx.RunDir, "backups", rel)
    if !ctx.DryRun {
        if _, err := os.Stat(path); err == nil {
            if err := copyVerbatim(path, backup); err != nil {
                return ActionResult{}, err
            }
            if err := cmpStrict(path, backup); err != nil {
                return ActionResult{}, err
            }
        }
    }

    started := time.Now().UnixNano() - ctx.StartNS
    if ctx.DryRun {
        fmt.Fprintf(os.Stderr, "[dry-run] would mutate %s: %s\n", path, op.Kind)
        return ActionResult{OK: true, BeforeHash: beforeHash, AfterHash: beforeHash}, nil
    }
    if err := executeAtomic(path, op); err != nil {
        return ActionResult{}, err
    }

    after, err := readOrEmpty(path)
    if err != nil { return ActionResult{}, err }
    afterHash := sha256Hex(after)
    finished := time.Now().UnixNano() - ctx.StartNS

    rec := ActionRecord{
        Path: rel, Op: op.Kind,
        BeforeHash: beforeHash, AfterHash: afterHash,
        StartedAtNS: started, FinishedAtNS: finished,
        RunID: ctx.RunID, FixerID: ctx.FixerID, OK: true,
    }
    // For Rename ops, populate RenameTo so doctor undo can reverse the move.
    if op.Kind == "Rename" { rec.RenameTo = op.Target }
    line, _ := json.Marshal(rec); line = append(line, '\n')
    ctx.actionsMu.Lock()
    defer ctx.actionsMu.Unlock()
    if _, err := ctx.ActionsFile.Write(line); err != nil {
        return ActionResult{}, err
    }
    if err := ctx.ActionsFile.Sync(); err != nil {
        return ActionResult{}, err
    }

    return ActionResult{OK: true, BeforeHash: beforeHash, AfterHash: afterHash}, nil
}

func executeAtomic(path string, op Op) error {
    parent := filepath.Dir(path)
    switch op.Kind {
    case "WriteFile":
        tmp, err := os.CreateTemp(parent, ".doctor.tmp.*")
        if err != nil { return err }
        if _, err := tmp.Write(op.Bytes); err != nil { tmp.Close(); return err }
        if err := tmp.Sync(); err != nil { tmp.Close(); return err }
        if err := tmp.Close(); err != nil { return err }
        if op.Mode != 0 {
            if err := os.Chmod(tmp.Name(), os.FileMode(op.Mode)); err != nil { return err }
        }
        return os.Rename(tmp.Name(), path)
    case "AppendFile":
        f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
        if err != nil { return err }
        defer f.Close()
        if _, err := f.Write(op.Bytes); err != nil { return err }
        return f.Sync()
    case "Rename":
        if err := os.MkdirAll(filepath.Dir(op.Target), 0o755); err != nil { return err }
        return os.Rename(path, op.Target)
    case "Chmod":
        return os.Chmod(path, os.FileMode(op.Mode))
    case "SymlinkAtomic":
        tmp := filepath.Join(
            filepath.Dir(path),
            fmt.Sprintf(".%s.doctor-symlink-tmp.%d", filepath.Base(path), time.Now().UnixNano()),
        )
        if err := os.Symlink(op.Target, tmp); err != nil { return err }
        return os.Rename(tmp, path)
    }
    return fmt.Errorf("unknown op %s", op.Kind)
}
```

## Detector + Fixer pair

```go
type Finding struct {
    ID          string                 `json:"id"`
    Severity    string                 `json:"severity"`
    Subsystem   string                 `json:"subsystem"`
    Title       string                 `json:"title"`
    Evidence    map[string]interface{} `json:"evidence"`
    Remediation Remediation            `json:"remediation"`
}

type Remediation struct {
    Command         string `json:"command"`
    ExplainCommand  string `json:"explain_command"`
    AutoFixable     bool   `json:"auto_fixable"`
    EstimatedActions int   `json:"estimated_actions"`
}

func detectStaleLockfile(repo string) (*Finding, error) {
    lockPath := filepath.Join(repo, ".beads", "beads.lock")
    info, err := os.Stat(lockPath)
    if os.IsNotExist(err) { return nil, nil }
    if err != nil { return nil, err }
    pid, err := readLockPID(lockPath)
    if err != nil { return nil, err }
    if isProcessAlive(pid) { return nil, nil }
    return &Finding{
        ID: "fm-concurrency-primitives-lockfile-orphaned",
        Severity: "P1",
        Subsystem: "concurrency_primitives",
        Title: fmt.Sprintf("Stale lockfile from PID %d (not alive)", pid),
        Evidence: map[string]interface{}{
            "file": ".beads/beads.lock",
            "pid": pid,
            "mtime": info.ModTime().Format(time.RFC3339),
        },
        Remediation: Remediation{
            Command: "br doctor --fix --only fm-concurrency-primitives-lockfile-orphaned",
            ExplainCommand: "br doctor explain fm-concurrency-primitives-lockfile-orphaned",
            AutoFixable: true,
            EstimatedActions: 1,
        },
    }, nil
}

func fixStaleLockfile(repo string, ctx *MutateContext) error {
    lockPath := filepath.Join(repo, ".beads", "beads.lock")
    quarantine := filepath.Join(ctx.RunDir, "quarantine", "locks", "beads.lock")
    _, err := Mutate(ctx, lockPath, Op{Kind: "Rename", Target: quarantine})
    return err
}
```

## TTY / NO_COLOR detection

```go
import "golang.org/x/term"

func useColor() bool {
    if os.Getenv("NO_COLOR") != "" { return false }
    if os.Getenv("CI") != "" { return false }
    if os.Getenv("TERM") == "dumb" { return false }
    return term.IsTerminal(int(os.Stdout.Fd()))
}
```

## Signal handling

```go
import "os/signal"

func installSignalHandlers() {
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    go func() {
        <-c
        // Atomic writes via temp+rename mean the worst case is a half-written
        // .doctor.tmp.* file, which next run's recovery detector quarantines.
        os.Exit(130)
    }()
}
```

## Common pitfalls (Go)

- **`os.Rename` cross-FS** is NOT atomic. Always use `os.CreateTemp(filepath.Dir(target), ...)` so the temp lives on the same FS.
- **`syscall.Flock` is Linux-specific.** Use `golang.org/x/sys/unix` for cross-OS or fall back to `LockFileEx` on Windows. For doctor we typically scope to *nix.
- **`json.Marshal` reorders maps** — Go map iteration is random. For stable JSON, use sorted struct fields, not maps for top-level ordering-sensitive fields.
- **`os.WriteFile` does NOT fsync.** Wrap in temp+rename for atomicity.
- **cobra `RunE` returning an error** prints to stderr automatically; don't double-print.
