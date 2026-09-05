# Other Languages — Compact Recipes

For each language: framework, atomic-write idiom, lockfile idiom, hashing idiom, and the `mutate()` chokepoint in 30–50 lines.

---

## Ruby

- **CLI**: `thor` or `optparse`
- **JSON**: `json` (stdlib)
- **Atomic write**: `Tempfile.create(dir: parent) { |t| t.write(...); t.close; File.rename(t.path, target) }`
- **Lockfile**: `File.flock(File::LOCK_EX | File::LOCK_NB)`
- **Hashing**: `Digest::SHA256.hexdigest(bytes)`

```ruby
require "json"; require "digest"; require "tempfile"; require "fileutils"

class Mutator
  def initialize(run_id:, run_dir:, capabilities:, actions_io:, fixer_id:, repo_root:, dry_run: false)
    @run_id = run_id; @run_dir = run_dir; @capabilities = capabilities
    @actions_io = actions_io; @actions_mu = Mutex.new
    @fixer_id = fixer_id; @repo_root = repo_root; @dry_run = dry_run
    @start_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  end

  def mutate(path, op)
    # Lock-path uses a dotted-prefix form (foo/bar.txt -> foo/.bar.txt.doctor-lock)
    # to avoid sibling-file collisions. Matches the Python, Rust, Go, Bash, JVM
    # recipes' convention.
    lock_path = File.join(File.dirname(path), ".#{File.basename(path)}.doctor-lock")
    File.open(lock_path, "a+") do |lock|
      raise "lock_held" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      before = File.exist?(path) ? File.binread(path) : ""
      before_hash = "sha256:" + Digest::SHA256.hexdigest(before)

      ensure_in_scope!(path)

      rel = path.sub(/^#{Regexp.escape(@repo_root)}\/?/, "")
      backup = File.join(@run_dir, "backups", rel)
      unless @dry_run
        FileUtils.mkdir_p(File.dirname(backup))
        FileUtils.cp(path, backup, preserve: true) if File.exist?(path)
      end

      started_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - @start_ns
      return { ok: true, before_hash:, after_hash: before_hash } if @dry_run

      execute_atomic(path, op)

      after = File.exist?(path) ? File.binread(path) : ""
      after_hash = "sha256:" + Digest::SHA256.hexdigest(after)
      finished_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - @start_ns

      # For Rename ops, include `rename_to` so `doctor undo` can reverse the
      # move. Required per OUTPUT-SCHEMA.md § Per-op fields.
      record = {
        path: rel, op: op[:kind],
        before_hash:, after_hash:,
        started_at_ns: started_ns, finished_at_ns: finished_ns,
        run_id: @run_id, fixer_id: @fixer_id, ok: true,
      }
      record[:rename_to] = op[:target].to_s if op[:kind] == "Rename"
      @actions_mu.synchronize do
        @actions_io.puts(record.to_json)
        @actions_io.flush
        @actions_io.fsync
      end

      { ok: true, before_hash:, after_hash: }
    end
  end

  private

  def ensure_in_scope!(path)
    real = realpath_existing_or_parent(path)
    return if @capabilities[:write_scopes].any? do |s|
      scope = realpath_existing_or_parent(s)
      real == scope || real.start_with?(scope + File::SEPARATOR)
    end
    raise "path #{path} outside write_scopes"
  end

  def realpath_existing_or_parent(path)
    File.realpath(path)
  rescue Errno::ENOENT
    File.join(File.realpath(File.dirname(path)), File.basename(path))
  end

  def execute_atomic(path, op)
    parent = File.dirname(path)
    case op[:kind]
    when "WriteFile"
      Tempfile.create(".doctor.tmp.", parent) do |tmp|
        tmp.binmode; tmp.write(op[:content]); tmp.flush; tmp.fsync
        FileUtils.chmod(op[:mode] || 0o644, tmp.path)
        File.rename(tmp.path, path)
      end
    when "Rename"
      FileUtils.mkdir_p(File.dirname(op[:target]))
      File.rename(path, op[:target])
    when "Chmod"
      FileUtils.chmod(op[:mode], path)
    end
  end
end
```

---

## C / C++

- **CLI**: CLI11 (C++) or `getopt_long` (C)
- **JSON**: nlohmann/json (C++) or jansson (C)
- **Atomic write**: `mkostemp(template, O_RDWR)` → write → `fdatasync` → `rename`
- **Lockfile**: `flock(fd, LOCK_EX | LOCK_NB)` (POSIX) or `LockFileEx` (Windows)
- **Hashing**: OpenSSL `SHA256`

```cpp
// C++ skeleton (paste-ready for the chokepoint)
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#include <openssl/sha.h>
#include <nlohmann/json.hpp>
#include <fstream>
#include <filesystem>
#include <mutex>

struct Capabilities { std::vector<std::filesystem::path> write_scopes; };

struct MutateContext {
    std::string run_id, fixer_id;
    std::filesystem::path run_dir, repo_root;
    Capabilities capabilities;
    std::ofstream& actions_file;
    std::mutex& actions_mu;
    bool dry_run = false;
    int64_t start_ns;
};

std::string sha256_hex(const std::vector<uint8_t>& bytes) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(bytes.data(), bytes.size(), digest);
    char buf[2 * SHA256_DIGEST_LENGTH + 8] = "sha256:";
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        sprintf(buf + 7 + 2*i, "%02x", digest[i]);
    }
    return buf;
}

// mutate() implementation — same shape as the Rust/Go versions:
// 1. flock(); 2. before_hash; 3. ensure_in_scope; 4. copy backup + cmp-strict;
// 5. plan; 6. mkostemp + write + fdatasync + rename; 7. after_hash; 8. write actions.jsonl line.
```

For C, use the same shape with `getopt_long`, `stdio.h`, `errno.h`. Use `mkostemp` (Linux) or `mkstemp` (POSIX). Lock the file with `flock(int fd, LOCK_EX | LOCK_NB)`. Append to `actions.jsonl` via `fopen("a")`, `fprintf`, `fflush`, `fsync(fileno(f))`.

---

## Zig

- **CLI**: `std.process.argsAlloc` + manual parsing (or `clap` package)
- **JSON**: `std.json`
- **Atomic write**: `std.fs.cwd().createFile(tmp, .{})` → write → `file.sync()` → `std.fs.cwd().rename(tmp, target)`
- **Lockfile**: `std.os.flock(fd, .EX | .NB)` (Zig 0.11+ may differ; check std)
- **Hashing**: `std.crypto.hash.sha2.Sha256`

```zig
const std = @import("std");

const Op = union(enum) {
    WriteFile: struct { content: []const u8, mode: std.fs.File.Mode },
    Rename: struct { target: []const u8 },
    Chmod: struct { mode: std.fs.File.Mode },
};

// mutate() chokepoint — sketch:
fn mutate(
    allocator: std.mem.Allocator,
    ctx: *MutateContext,
    path: []const u8,
    op: Op,
) !ActionResult {
    // 1. Per-path advisory lock.
    // Lock-path uses a dotted-prefix form (foo/bar.txt -> foo/.bar.txt.doctor-lock)
    // to avoid sibling-file collisions; matches the Python/Rust/Go/Bash/JVM convention.
    const dirpath = std.fs.path.dirname(path) orelse ".";
    const basename = std.fs.path.basename(path);
    const lock_path = try std.fmt.allocPrint(allocator, "{s}/.{s}.doctor-lock", .{ dirpath, basename });
    defer allocator.free(lock_path);
    const lock = try std.fs.cwd().createFile(lock_path, .{ .read = true });
    defer lock.close();
    try std.os.flock(lock.handle, std.os.LOCK.EX | std.os.LOCK.NB);

    // 2-8: same shape as other languages.
    // ...
}
```

---

## Elixir

- **CLI**: `Optimus`
- **JSON**: `Jason`
- **Atomic write**: `:erlang.term_to_binary` on a temp path → `File.rename!`. For raw bytes: `File.write!(tmp, ...) ; File.rename!(tmp, target)`.
- **Lockfile**: `:gen_server` advisory lock or `:flock` via NIF. Use a persistent lock inode and release the advisory lock; do not use create-and-delete lock files.
- **Hashing**: `:crypto.hash(:sha256, bytes)`

```elixir
defmodule Doctor.Mutator do
  defstruct [:run_id, :run_dir, :capabilities, :actions_io, :fixer_id, :repo_root, :dry_run, :start_ns]

  def mutate(ctx, path, op) do
    # Lock-path uses a dotted-prefix form (foo/bar.txt -> foo/.bar.txt.doctor-lock)
    # to avoid sibling-file collisions; matches the Python/Rust/Go/Bash/JVM convention.
    lock_path = Path.join(Path.dirname(path), "." <> Path.basename(path) <> ".doctor-lock")
    {:ok, lock} = Flock.acquire(lock_path)
    try do
      before = if File.exists?(path), do: File.read!(path), else: ""
      before_hash = "sha256:" <> Base.encode16(:crypto.hash(:sha256, before), case: :lower)

      ensure_in_scope!(ctx.capabilities, path)

      rel = Path.relative_to(path, ctx.repo_root)
      backup = Path.join([ctx.run_dir, "backups", rel])
      unless ctx.dry_run do
        File.mkdir_p!(Path.dirname(backup))
        if File.exists?(path), do: File.cp!(path, backup)
      end

      execute_atomic!(path, op)

      after_bin = if File.exists?(path), do: File.read!(path), else: ""
      after_hash = "sha256:" <> Base.encode16(:crypto.hash(:sha256, after_bin), case: :lower)

      # For Rename ops, include `rename_to` so `doctor undo` can reverse the
      # move. Required per OUTPUT-SCHEMA.md § Per-op fields.
      record = %{
        path: rel, op: op.kind,
        before_hash: before_hash, after_hash: after_hash,
        run_id: ctx.run_id, fixer_id: ctx.fixer_id, ok: true,
      }
      record = if op.kind == "Rename",
                 do: Map.put(record, :rename_to, op.target |> to_string()),
                 else: record
      IO.puts(ctx.actions_io, Jason.encode!(record))

      %{ok: true, before_hash: before_hash, after_hash: after_hash}
    after
      Flock.release(lock)
    end
  end

  defp execute_atomic!(path, %{kind: "WriteFile", content: content, mode: mode}) do
    tmp = path <> ".doctor.tmp.#{System.system_time(:microsecond)}"
    File.write!(tmp, content)
    File.chmod!(tmp, mode)
    File.rename!(tmp, path)
  end
  defp execute_atomic!(path, %{kind: "Rename", target: target}) do
    File.mkdir_p!(Path.dirname(target))
    File.rename!(path, target)
  end
end
```

---

## Bash

- **CLI**: `getopts` (stdlib) + a tiny parser
- **JSON**: `jq`
- **Atomic write**: `mktemp -p $(dirname target)` → `mv` (uses `rename(2)`)
- **Lockfile**: `flock` (util-linux) or `mkdir` for advisory lock
- **Hashing**: `sha256sum`

```bash
#!/usr/bin/env bash
set -euo pipefail

mutate() {
    local path="$1" op_kind="$2" content_path="${3:-}" mode="${4:-644}"

    # Lock-path uses a dotted-prefix form (matches the Python and Rust
    # recipes) so the lock can never collide with a real target file:
    # given path foo/bar.txt, the lock is foo/.bar.txt.doctor-lock.
    # Without the dot prefix, a sibling file literally named bar.txt.doctor-lock
    # would collide (and a `mutate(... ".doctor-lock")` invocation would
    # try to lock itself).
    local _dir _base
    _dir="$(dirname "$path")"
    _base="$(basename "$path")"
    local lock_path="$_dir/.$_base.doctor-lock"

    # 1. Lock.
    exec 9>"$lock_path"
    flock -n 9 || { echo '{"ok":false,"error":"lock_held"}'; return 1; }

    # 2-3. Hash + scope.
    local before_hash="sha256:$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)"
    [ -z "${before_hash#sha256:}" ] && before_hash="sha256:$(printf '' | sha256sum | cut -d' ' -f1)"
    ensure_in_scope "$path" || return 1

    # 4. Backup.
    local rel="${path#"$REPO_ROOT/"}"
    local backup="$RUN_DIR/backups/$rel"
    [ "$DRY_RUN" = "1" ] || { mkdir -p "$(dirname "$backup")"; cp -a "$path" "$backup" 2>/dev/null || true; }
    [ "$DRY_RUN" = "1" ] || cmp -s "$path" "$backup" 2>/dev/null \
        || [ ! -e "$path" ] || { echo "backup verify failed"; return 1; }

    # 5-6. Plan + execute atomically.
    if [ "$DRY_RUN" = "1" ]; then
        echo "[dry-run] would mutate $path: $op_kind" >&2
        echo "{\"ok\":true,\"before_hash\":\"$before_hash\",\"after_hash\":\"$before_hash\"}"
        return 0
    fi

    case "$op_kind" in
        WriteFile)
            local tmp; tmp=$(mktemp -p "$(dirname "$path")" .doctor.tmp.XXXXXX)
            cat "$content_path" > "$tmp"
            chmod "$mode" "$tmp"
            mv "$tmp" "$path"
            ;;
        Rename)
            local target="$3"
            mkdir -p "$(dirname "$target")"
            mv "$path" "$target"
            ;;
    esac

    # 7-8. After hash + actions.jsonl line.
    local after_hash="sha256:$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)"
    [ -z "${after_hash#sha256:}" ] && after_hash="sha256:$(printf '' | sha256sum | cut -d' ' -f1)"
    exec 8>>"${ACTIONS_PATH}.lock"
    flock 8
    # For Rename ops, include `rename_to` (the destination path passed as
    # arg 3) so doctor undo can reverse the move. Required per OUTPUT-SCHEMA.md
    # § Per-op fields. Other ops omit it (jq's `+ {}` is a no-op merge).
    local rename_to_obj='{}'
    [ "$op_kind" = "Rename" ] && rename_to_obj=$(jq -nc --arg t "$3" '{rename_to:$t}')
    jq -nc --arg path "$rel" --arg op "$op_kind" \
        --arg before "$before_hash" --arg after "$after_hash" \
        --arg run_id "$RUN_ID" --arg fixer_id "$FIXER_ID" \
        --argjson extra "$rename_to_obj" \
        '{path:$path,op:$op,before_hash:$before,after_hash:$after,run_id:$run_id,fixer_id:$fixer_id,ok:true} + $extra' \
        >> "$ACTIONS_PATH"
    sync
    flock -u 8
    echo "{\"ok\":true,\"before_hash\":\"$before_hash\",\"after_hash\":\"$after_hash\"}"
}
```

For Bash, the actions-file lock uses a separate FD `8` opened on an actions-file lock path. The per-path lock uses FD `9`. Always honor `NO_COLOR` (no ANSI in bash output by default; only emit color when `[ -t 1 ]` AND `[ -z "${NO_COLOR:-}" ]`).

---

## Common cross-language gotchas

- **Cross-FS rename is not atomic.** Always put the temp file in the same directory as the target — confirmed for every language above.
- **Test the lock primitive on the actual OS.** Linux `flock`, macOS `flock`, Windows `LockFileEx`, Bun's `proper-lockfile` — each has subtly different semantics. The Phase 5 concurrency test catches issues.
- **fsync the file AND its directory** for full crash-recovery on hostile filesystems. The recipes above fsync the file; for highest durability, also `fsync` the parent directory (Linux: open it RDONLY and fsync the fd).
- **Hash collisions across run-ids.** Run-id derivation is `sha256(target_sha + iso8601_utc_seconds)[..6]`. Two parallel runs in the same second collide; the second waits for the next second. Don't use random IDs — collisions become non-deterministic and break replay.
