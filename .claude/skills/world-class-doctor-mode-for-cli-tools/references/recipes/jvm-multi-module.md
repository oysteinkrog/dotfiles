# Recipe: JVM multi-module workspace (Maven, Gradle)

**When to use.** Target is a JVM project with multiple modules: Maven multi-module (`pom.xml` at root with `<modules>` plus per-module `pom.xml`) or Gradle multi-project (`settings.gradle{,.kts}` with `include` directives plus per-module `build.gradle{,.kts}`).

This recipe parallels [monorepo-multi-cli.md](monorepo-multi-cli.md) and [bazel-monorepo.md](bazel-monorepo.md). Differs in: build tool invocation (`mvn` / `gradle`), packaging (jar / fat-jar / GraalVM native-image), JVM-specific failure modes, and where the doctor module lives.

---

## Discovery

`scripts/discover-cli.sh` should detect:
- `pom.xml` (Maven)
- `build.gradle` / `build.gradle.kts` (Gradle)
- `settings.gradle` / `settings.gradle.kts` (Gradle multi-project marker)

Binary candidates for Maven: scan child `pom.xml` files for `<packaging>jar</packaging>` modules with a Main-Class manifest entry. For Gradle: scan child `build.gradle{,.kts}` for `application` plugin + `mainClass`.

```bash
# Maven candidate enumeration:
find . -maxdepth 4 -name pom.xml ! -path "./target/*" \
    | xargs -I{} sh -c 'grep -l "<packaging>jar</packaging>" "{}" 2>/dev/null'

# Gradle candidate enumeration:
find . -maxdepth 4 \( -name build.gradle -o -name build.gradle.kts \) ! -path "./build/*" \
    | xargs -I{} sh -c 'grep -lE "id [\"'\''](application|com.gradleup.shadow)[\"'\'']" "{}" 2>/dev/null'
```

(Implementing as a `discover-cli.sh` branch is round-56 forward work.)

---

## Where the doctor lives

A new module: `<repo>-doctor/`. Either:
- **Maven module**: `<repo>-doctor/pom.xml` with `<artifactId>doctor</artifactId>` and a `<mainClass>` packed via `maven-shade-plugin` to a fat-jar.
- **Gradle subproject**: `tools/doctor/build.gradle.kts` applying the `application` plugin and naming `mainClass.set("...")`.

Invocation pattern (canonical):

```bash
# Fat-jar form:
java -jar build/libs/<repo>-doctor-all.jar diagnose
java -jar build/libs/<repo>-doctor-all.jar --fix

# Maven exec:
mvn -pl <repo>-doctor exec:java -Dexec.args="diagnose"

# Gradle:
./gradlew :tools:doctor:run --args="diagnose"
```

Phase 0 SHOULD prefer the fat-jar form for the `health` subcommand (lowest startup latency once JIT warms; Maven/Gradle wrappers add 2-5s of build-tool overhead per invocation). Phase 8 integration-wirer wires `health` to the fat-jar path via a wrapper script `bin/<tool>-doctor` so users get an `am`-style ergonomic invocation.

---

## Capabilities aggregation

Same as [monorepo-multi-cli.md](monorepo-multi-cli.md). Each binary module's doctor declares its sub-CLI status; the parent fat-jar aggregates.

---

## JVM-specific failure modes

These belong in any JVM project's corpus filter (`query-corpus.py --language jvm`):

- **`fm-jvm-classpath-drift`** — runtime classpath includes stale module JARs after a `mvn clean install` of a sibling. Detector: compare each loaded JAR's mtime against the source `pom.xml`'s mtime.
- **`fm-jvm-m2-cache-corruption`** — `~/.m2/repository/<group>/<artifact>/.../<jar>` truncated after a network blip. Detector: per-jar SHA against the Central manifest.
- **`fm-jvm-gradle-cache-rot`** — `~/.gradle/caches/` accumulates unused JARs. Detector: count + age. Fixer: NOT auto-fixable (cache-clear is deletion-equivalent; offer `gc --before <date> --yes` instead).
- **`fm-jvm-graalvm-config-stale`** — `META-INF/native-image/<group>/<artifact>/reflect-config.json` out of sync with current source. Detector: re-run `native-image-agent` and diff.
- **`fm-jvm-version-mismatch`** — `JAVA_HOME` differs from the toolchain declared in `pom.xml`'s `<maven.compiler.release>` or `build.gradle`'s `java.toolchain.languageVersion`. Detector: compare runtime `System.getProperty("java.specification.version")` against declared.

---

## Phase 8 integration (CI)

```yaml
- uses: actions/setup-java@v4
  with: { java-version: 21, distribution: temurin }
- run: ./gradlew :tools:doctor:installShadowDist
- run: build/install/doctor-shadow/bin/doctor --quick --json
- run: |
    rc=0
    build/install/doctor-shadow/bin/doctor --json > /tmp/run.json || rc=$?
    case "$rc" in 0|1) ;; *) exit "$rc";; esac
    # ... regression check via jq, per integration-wirer canonical
```

---

## Known sharp edges

1. **JVM startup latency.** Even minimal Java programs take ~500ms to start. The `health` subcommand's <200ms target is unreachable WITHOUT GraalVM native-image. Either compile to native (preferred for production doctors), or relax the target to <2s for JVM-only.
2. **`./gradlew` with daemon.** First invocation spawns the Gradle daemon (~5s); subsequent invocations are fast. The doctor MUST NOT depend on the daemon; use the fat-jar form for routine invocation.
3. **Maven repository proxies.** If the user's `settings.xml` proxies through a private Nexus, the doctor's m2-cache detector should fall back to checking against the proxy's manifest, not Central.
4. **Multi-module test isolation.** `mvn test` runs all modules' tests; this is wrong for Phase 5 (we only want the doctor's own tests). Use `mvn -pl <repo>-doctor test`.

---

## Phase 4 implementer guidance

`scripts/scaffold-doctor.sh --language jvm` is round-56-pending; until then:
1. Start from the canonical Java skeleton in `references/recipes/jvm.md` (the existing JVM recipe — it covers single-binary, this multi-module recipe extends it).
2. Hand-write the parent module's pom.xml or build.gradle.kts.
3. Wire the fat-jar build via `maven-shade-plugin` (Maven) or `com.gradleup.shadow` (Gradle).
