# JVM Recipe — Java / Kotlin / Scala / Clojure

The four major JVM languages share atomic-write idioms (Files API), JSON ecosystems (Jackson / kotlinx-serialization), and lockfile primitives (`FileChannel.lock`). One recipe covers all four with language-specific entry points.

## Build systems

- **Java**: Maven (`pom.xml`) or Gradle (`build.gradle`). Discovered by `discover-cli.sh`.
- **Kotlin**: typically Gradle (`build.gradle.kts`). Single binary via `application` plugin.
- **Scala**: sbt (`build.sbt`).
- **Clojure**: Leiningen (`project.clj`) or deps (`deps.edn`).

CLI binaries are typically launched via shell wrappers (`./gradlew run`, `./mvnw exec:java`, `clj -M:run`) or fat jars (`java -jar app.jar`). For the doctor's perspective, the `<tool>` is the wrapper script.

## Dependencies

| Concern | Java | Kotlin | Scala | Clojure |
|---------|------|--------|-------|---------|
| CLI parsing | picocli | clikt | scopt | tools.cli |
| JSON | jackson-databind | kotlinx-serialization | upickle | data.json |
| Atomic write | `Files.write` + `Files.move(ATOMIC_MOVE)` | same | same | same |
| Lock | `FileChannel.tryLock()` | same | same | same |
| Hashing | `MessageDigest.getInstance("SHA-256")` | same | same | same |
| TTY check | `System.console() != null` | same | same | same |

## CLI surface (Java + picocli)

```java
@CommandLine.Command(name = "<tool>", subcommands = {DoctorCommand.class})
public class Main implements Runnable {
    public static void main(String[] args) {
        int rc = new CommandLine(new Main()).execute(args);
        System.exit(rc);
    }
    @Override public void run() {}
}

@CommandLine.Command(name = "doctor", subcommands = {
    Diagnose.class, Fix.class, Undo.class, Explain.class,
    Capabilities.class, Health.class, RobotDocs.class, Gc.class, Ls.class
})
class DoctorCommand implements Runnable {
    @CommandLine.Option(names = "--fix") boolean fix;
    @CommandLine.Option(names = "--dry-run") boolean dryRun;
    @CommandLine.Option(names = "--only", split = ",") List<String> only = new ArrayList<>();
    @CommandLine.Option(names = "--skip", split = ",") List<String> skip = new ArrayList<>();
    @CommandLine.Option(names = "--since") String since;
    @CommandLine.Option(names = "--online") boolean online;
    @CommandLine.Option(names = "--explain") String explain;
    @CommandLine.Option(names = "--severity", defaultValue = "P3") Severity severity;
    @CommandLine.Option(names = "--quick") boolean quick;
    @CommandLine.Option(names = "--json") boolean json;
    @CommandLine.Option(names = "--robot") boolean robot;
    @CommandLine.Option(names = "--quiet") boolean quiet;
    @CommandLine.Option(names = "--robot-triage") boolean robotTriage;
    @CommandLine.Option(names = "--no-color") boolean noColor;
    @CommandLine.Option(names = "--no-progress") boolean noProgress;
    @CommandLine.Option(names = "-v") boolean[] verbose = new boolean[]{};
    @CommandLine.Option(names = "--force") boolean force;
    @CommandLine.Option(names = "--yes") boolean yes;
    @Override public void run() { /* default = diagnose */ }
}
```

## `mutate()` chokepoint (Java)

```java
public final class Mutate {
    public sealed interface Op permits WriteFile, AppendFile, Rename, Chmod, SymlinkAtomic, DbExec, DbMigrate {}
    public record WriteFile(byte[] content, int mode) implements Op {}
    public record AppendFile(byte[] content) implements Op {}
    public record Rename(Path to) implements Op {}
    public record Chmod(int mode) implements Op {}
    public record SymlinkAtomic(Path target) implements Op {}
    public record DbExec(String sql) implements Op {}
    public record DbMigrate(int from, int to) implements Op {}

    public record ActionResult(boolean ok, String beforeHash, String afterHash, String error) {}

    public static ActionResult mutate(MutateContext ctx, Path path, Op op) throws IOException {
        Path lockPath = path.getParent().resolve("." + path.getFileName() + ".doctor-lock");
        Files.createDirectories(lockPath.getParent());

        try (FileChannel lockChan = FileChannel.open(lockPath, StandardOpenOption.CREATE,
                StandardOpenOption.READ, StandardOpenOption.WRITE);
             FileLock lock = lockChan.tryLock()) {

            if (lock == null) {
                return new ActionResult(false, "", "", "lock_held");
            }

            byte[] before = Files.exists(path) ? Files.readAllBytes(path) : new byte[0];
            String beforeHash = sha256Hex(before);

            ensureInScope(ctx.capabilities, path);

            Path rel = ctx.repoRoot.relativize(path);
            Path backup = ctx.runDir.resolve("backups").resolve(rel);

            if (!ctx.dryRun && Files.exists(path)) {
                Files.createDirectories(backup.getParent());
                Files.copy(path, backup, StandardCopyOption.COPY_ATTRIBUTES);
                if (!Arrays.equals(Files.readAllBytes(path), Files.readAllBytes(backup))) {
                    throw new IOException("backup verify failed (cmp-strict)");
                }
            }

            long startNs = System.nanoTime() - ctx.startNs;
            if (ctx.dryRun) {
                System.err.printf("[dry-run] would mutate %s: %s%n", path, op.getClass().getSimpleName());
                return new ActionResult(true, beforeHash, beforeHash, null);
            }

            executeAtomic(path, op);

            byte[] after = Files.exists(path) ? Files.readAllBytes(path) : new byte[0];
            String afterHash = sha256Hex(after);
            long finishedNs = System.nanoTime() - ctx.startNs;

            // Per-op field: rename_to is the destination for Rename ops.
            // doctor undo reads this to reverse the move. Required per
            // OUTPUT-SCHEMA.md § Per-op fields. Other ops pass null.
            String renameTo = (op instanceof Rename r) ? r.to().toString() : null;
            ActionRecord record = new ActionRecord(rel.toString(), op.getClass().getSimpleName(),
                    beforeHash, afterHash, startNs, finishedNs,
                    ctx.runId, ctx.fixerId, true, renameTo, null, null);
            String line = MAPPER.writeValueAsString(record) + "\n";

            synchronized (ctx.actionsLock) {
                Files.writeString(ctx.actionsFile, line, StandardOpenOption.APPEND);
                ctx.actionsChannel.force(true);
            }

            return new ActionResult(true, beforeHash, afterHash, null);
        }
    }

    private static void executeAtomic(Path path, Op op) throws IOException {
        Path parent = path.getParent();
        switch (op) {
            case WriteFile wf -> {
                Path tmp = Files.createTempFile(parent, ".doctor.tmp.", "");
                Files.write(tmp, wf.content(), StandardOpenOption.WRITE);
                if (wf.mode() != 0) {
                    Files.setPosixFilePermissions(tmp, modeBits(wf.mode()));
                }
                Files.move(tmp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            }
            case AppendFile af -> Files.write(path, af.content(),
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            case Rename r -> {
                Files.createDirectories(r.to().getParent());
                Files.move(path, r.to(), StandardCopyOption.ATOMIC_MOVE);
            }
            case Chmod c -> Files.setPosixFilePermissions(path, modeBits(c.mode()));
            case SymlinkAtomic sa -> {
                Path tmp = parent.resolve(path.getFileName() + ".doctor-symlink-tmp." + System.nanoTime());
                Files.createSymbolicLink(tmp, sa.target());
                Files.move(tmp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            }
            case DbExec de -> { /* project-specific */ }
            case DbMigrate dm -> { /* project-specific */ }
        }
    }

    private static String sha256Hex(byte[] bytes) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder sb = new StringBuilder("sha256:");
            for (byte b : digest) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }
}
```

## Kotlin variant

Same shape, more concise:

```kotlin
sealed class Op {
    data class WriteFile(val content: ByteArray, val mode: Int) : Op()
    data class Rename(val to: Path) : Op()
    data class Chmod(val mode: Int) : Op()
    object AppendFile : Op()                  // (parameterless variant for example)
    data class SymlinkAtomic(val target: Path) : Op()
}

@Serializable
data class ActionRecord(
    val path: String, val op: String,
    @SerialName("before_hash") val beforeHash: String,
    @SerialName("after_hash") val afterHash: String,
    @SerialName("started_at_ns") val startedAtNs: Long,
    @SerialName("finished_at_ns") val finishedAtNs: Long,
    @SerialName("run_id") val runId: String,
    @SerialName("fixer_id") val fixerId: String,
    val ok: Boolean,
    // Per-op field: only populated for Op.Rename. doctor undo reads this
    // to reverse the move. Required per OUTPUT-SCHEMA.md § Per-op fields.
    @SerialName("rename_to") val renameTo: String? = null,
    val error: String? = null,
    @SerialName("rolled_back") val rolledBack: Boolean? = null,
)

fun mutate(ctx: MutateContext, path: Path, op: Op): ActionResult {
    val lockPath = path.parent.resolve(".${path.fileName}.doctor-lock")
    Files.createDirectories(lockPath.parent)
    FileChannel.open(lockPath, StandardOpenOption.CREATE,
                     StandardOpenOption.READ, StandardOpenOption.WRITE).use { chan ->
        val lock = chan.tryLock() ?: return ActionResult(ok = false, error = "lock_held")
        try {
            // 2-8: same as Java version, with .also { ... } chains
        } finally {
            lock.release()
        }
    }
}
```

## TTY / NO_COLOR detection

```java
boolean useColor() {
    if (System.getenv("NO_COLOR") != null) return false;
    if (System.getenv("CI") != null) return false;
    if ("dumb".equals(System.getenv("TERM"))) return false;
    return System.console() != null;
}
```

## Signal handling

```java
Signal.handle(new Signal("INT"), sig -> {
    // The atomic Files.move(ATOMIC_MOVE) means worst case is a half-written
    // .doctor.tmp.* file in the parent dir; next run's recovery quarantines.
    System.exit(130);
});
Signal.handle(new Signal("TERM"), sig -> System.exit(143));
```

## Common pitfalls (JVM)

- **`Files.move` without `ATOMIC_MOVE`** falls back to copy+delete. Always use `StandardCopyOption.ATOMIC_MOVE`.
- **`Files.write` without explicit options** opens with `CREATE, TRUNCATE_EXISTING, WRITE` — that's fine for the temp file but NOT atomic. The atomicity comes from `Files.move`.
- **`FileChannel.tryLock()` returns null on contention**, NOT throws. Check for null.
- **`Files.copy` doesn't preserve permissions by default.** Use `StandardCopyOption.COPY_ATTRIBUTES`.
- **Windows POSIX permissions**: `setPosixFilePermissions` throws `UnsupportedOperationException` on FAT/NTFS. Wrap in try/catch and skip on Windows.
- **`System.console()` returns null when piped, even on a real terminal.** Use a more sophisticated check (e.g., the `jansi` library) if you need to distinguish "user piping intentionally" from "headless / non-TTY".
- **Maven shade plugin merges resource files;** if multiple deps have `META-INF/services/...` for SPI, use `ServicesResourceTransformer`.

## Swift recipe (mini)

For Swift CLIs (e.g., `swift-cli`-built tools):

- **CLI parsing**: ArgumentParser (Apple's official).
- **JSON**: `JSONEncoder` / `JSONDecoder` (Foundation).
- **Atomic write**: `try data.write(to: tempURL, options: .atomic)` writes via temp + rename atomically. ✓
- **Lock**: `flock(fd, LOCK_EX | LOCK_NB)` via Darwin module.
- **Hash**: CryptoKit `SHA256.hash(data:)`.

```swift
@main
struct ToolCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "<tool>",
        subcommands: [DoctorCommand.self]
    )
}

struct DoctorCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "doctor",
        subcommands: [
            DiagnoseCommand.self, FixCommand.self, UndoCommand.self,
            ExplainCommand.self, CapabilitiesCommand.self, HealthCommand.self,
            RobotDocsCommand.self, GcCommand.self, LsCommand.self,
        ]
    )
    @Flag(name: .long) var fix = false
    @Flag(name: .long) var dryRun = false
    @Option(name: .long, parsing: .upToNextOption) var only: [String] = []
    // ... rest of flags
}
```

`mutate()` follows the same shape as Java. Use `FileManager` with custom atomic-write helpers; `data.write(to:options:.atomic)` is the canonical primitive.

## Common pitfalls (Swift)

- **`FileManager.default.copyItem` doesn't preserve permissions perfectly.** Use the lower-level `linkItem` or set permissions explicitly post-copy.
- **`String(contentsOfFile:)` reads as UTF-8 by default.** For byte-identical comparison, use `Data(contentsOf:)`.
- **`NSLock` and `NSRecursiveLock`** are in-process locks. For file locking across processes, use `flock` via Darwin.
