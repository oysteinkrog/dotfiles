# Fuzzer Internals

How coverage-guided fuzzers actually work, from bitmap mechanics to mutation
scheduling. Every section ends with a practical "so what" -- the diagnostic
action you take when that subsystem is the bottleneck.

---

## Table of Contents

1. [The Coverage Feedback Loop](#the-coverage-feedback-loop)
2. [Edge Instrumentation](#edge-instrumentation)
3. [The Coverage Bitmap](#the-coverage-bitmap)
4. [Edge vs Block Coverage](#edge-vs-block-coverage)
5. [Bitmap Collisions](#bitmap-collisions)
6. [Energy / Power Scheduling](#energy--power-scheduling)
7. [Mutation Pipeline](#mutation-pipeline)
8. [Mutation Operators Taxonomy](#mutation-operators-taxonomy)
9. [CMPLOG / Redqueen](#cmplog--redqueen)
10. [Value Profile](#value-profile)
11. [Why This Matters Practically](#why-this-matters-practically)
12. [See Also](#see-also)

---

## The Coverage Feedback Loop

Every coverage-guided fuzzer runs the same core loop:

```
                    +------------------+
                    |  Seed Corpus     |
                    +--------+---------+
                             |
                             v
                    +------------------+
            +------>|  Pick a seed     |<---------+
            |       |  (power sched)   |          |
            |       +--------+---------+          |
            |                |                    |
            |                v                    |
            |       +------------------+          |
            |       |  Mutate input    |          |
            |       +--------+---------+          |
            |                |                    |
            |                v                    |
            |       +------------------+          |
            |       |  Execute target  |          |
            |       |  (instrumented)  |          |
            |       +--------+---------+          |
            |                |                    |
            |                v                    |
            |       +------------------+          |
            |       |  Read coverage   |          |
            |       |  bitmap          |          |
            |       +--------+---------+          |
            |                |                    |
            |           New edges?                |
            |           /        \                |
            |         Yes         No              |
            |         /            \              |
            |        v              v             |
            |  +-----------+   +-----------+      |
            |  | Save to   |   | Discard   |      |
            |  | corpus    |   | input     |------+
            |  +-----+-----+   +-----------+
            |        |
            +--------+
```

**Why this works:** Coverage-guided fuzzing is an evolutionary search through
the space of possible inputs. Each input is an "organism." Mutations produce
offspring. The fitness function is "does this input reach code that no
previous input reached?" Inputs that discover new coverage survive (get saved
to the corpus); inputs that don't are discarded. Over thousands of
iterations, the corpus evolves to cover increasingly deep program paths.

This is strictly more effective than random generation because:

- Each saved input represents a checkpoint that the fuzzer can build upon.
- Mutations are local perturbations, so inputs that are "almost right" can
  become "right" in one more mutation step.
- The coverage signal prevents wasting cycles re-exploring already-covered
  paths.

**So what:** If your fuzzer isn't finding new coverage after millions of
executions, the loop is running but the feedback signal is broken. Common
causes: collisions in the bitmap (Section 5), comparisons blocking
exploration (Section 9), or wrong power schedule starving interesting seeds
(Section 6).

---

## Edge Instrumentation

The fuzzer needs to know which code paths an input exercises. This is done
by the compiler injecting tiny probes at every control-flow transition.

### How the compiler does it

**Clang SanitizerCoverage (`-fsanitize-coverage=trace-pc-guard`):**

The compiler inserts a call to `__sanitizer_cov_trace_pc_guard` at every
edge. The fuzzer runtime provides this function, which records the edge hit
into a shared bitmap.

```c
// What the compiler inserts at each edge:
void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
    // *guard is a unique ID assigned at compile time
    __afl_area_ptr[*guard % MAP_SIZE]++;
}
```

**AFL-style instrumentation (`afl-cc`, `afl-clang-fast`):**

AFL computes edge IDs differently. Each basic block gets a random ID at
compile time. The edge ID is computed at runtime as `cur_block XOR prev_block`:

```c
// Pseudocode for AFL edge tracking
cur_location = <compile-time random>;
shared_mem[cur_location ^ prev_location]++;
prev_location = cur_location >> 1;
```

The `>> 1` shift is critical -- it makes `A -> B` and `B -> A` produce
different edge IDs. Without it, both transitions would hash to the same
value (`A XOR B == B XOR A`).

### What "edge" means

A basic block is a straight-line sequence of instructions with one entry
point and one exit point. An **edge** is a transition from one basic block
to another -- the arrows in a control-flow graph.

```
     Block A
    /       \
   v         v
Block B    Block C
    \       /
     v     v
     Block D
```

Edges: `A->B`, `A->C`, `B->D`, `C->D`. Four edges, four basic blocks.

### Instrumentation modes in AFL++

| Mode | Flag | Edge IDs | Collisions |
|---|---|---|---|
| Classic | `afl-clang-fast` | Random XOR | ~2% at 10K edges |
| PCGUARD | `-fsanitize-coverage=trace-pc-guard` | Sequential guards | Lower than classic |
| LTO | `afl-clang-lto` | Assigned at link time | Zero (collision-free) |
| LLVM native | `afl-clang-fast` + LLVM passes | Depends on version | Varies |

**So what:** If you control the build, always use LTO mode
(`afl-clang-lto`). It eliminates bitmap collisions entirely by assigning
edge IDs at link time when the full program is visible. If LTO is not
possible (e.g., pre-built libraries), use PCGUARD mode. Classic XOR mode
is the fallback.

---

## The Coverage Bitmap

The bitmap is a flat array in shared memory. Each byte represents one
edge's hit count.

### Structure

```
shared_mem: uint8_t[MAP_SIZE]   // default MAP_SIZE = 65536 (64 KB)

Index: edge_id % MAP_SIZE
Value: hitcount for that edge (saturating at 255)
```

The fuzzer doesn't track exact hit counts. Instead, it buckets them:

### Hitcount buckets

| Raw count | Bucket value | Meaning |
|---|---|---|
| 1 | 1 | Hit once |
| 2 | 2 | Hit twice |
| 3 | 4 | Hit 3 times |
| 4-7 | 8 | Hit a few times |
| 8-15 | 16 | Hit several times |
| 16-31 | 32 | Hit many times |
| 32-127 | 64 | Hit frequently |
| 128+ | 128 | Hit very frequently |

The bucketing collapses 256 possible raw values into 8 bucket values:

```c
// AFL++ classify_counts
static const uint8_t count_class_lookup8[256] = {
    [0]         = 0,
    [1]         = 1,
    [2]         = 2,
    [3]         = 4,
    [4 ... 7]   = 8,
    [8 ... 15]  = 16,
    [16 ... 31]  = 32,
    [32 ... 127] = 64,
    [128 ... 255] = 128,
};
```

### Why buckets, not exact counts

1. **Stability:** Exact counts are noisy. A loop that runs 47 times on one
   input and 48 times on another is behaviorally identical. Without
   bucketing, the fuzzer would save both as "new coverage," flooding the
   corpus with near-duplicates.

2. **Performance:** Comparing two bitmaps is a hot path (runs on every
   execution). Bucketed values let the fuzzer use fast bitwise comparisons
   instead of per-element arithmetic.

3. **Signal quality:** Bucket transitions (e.g., going from 3 hits to 8
   hits) genuinely indicate different loop behavior. They compress the
   signal without losing meaningful information.

### New coverage detection

After each execution, the fuzzer compares the current bitmap against the
"virgin" bitmap (bitwise OR of all previous executions):

```c
// Simplified: has_new_bits
for (i = 0; i < MAP_SIZE; i++) {
    if (current[i] && (current[i] & ~virgin[i])) {
        // This edge has a new hitcount bucket
        virgin[i] |= current[i];
        return 1;  // new coverage found
    }
}
return 0;
```

**So what:** The bitmap is the fuzzer's memory. If it's too small, edges
collide and the fuzzer forgets coverage (Section 5). If you see the fuzzer
saving thousands of corpus entries that all seem to exercise the same code,
hitcount bucketing may be over-triggering -- check if a non-deterministic
loop is causing bucket oscillation.

---

## Edge vs Block Coverage

These are fundamentally different coverage granularities, and the difference
matters for fuzzing effectiveness.

### Block coverage

"Was this basic block executed at all?"

```
if (A) {
    block_1();   // covered? yes/no
}
if (B) {
    block_2();   // covered? yes/no
}
```

With block coverage, the fuzzer tracks three blocks: `block_1`, `block_2`,
and the implicit else/fallthrough. It cannot distinguish between the path
where both conditions are true vs. the path where only one is.

### Edge coverage

"Which transitions between blocks occurred?"

Same code, but now the fuzzer tracks transitions:

```
        [entry]
        /     \
       v       v
   [A=true]  [A=false]
       \       /
        v     v
       [join1]
        /     \
       v       v
   [B=true]  [B=false]
       \       /
        v     v
       [exit]
```

Edges:
- `entry -> A=true` (A is true)
- `entry -> A=false` (A is false)
- `A=true -> join1`
- `A=false -> join1`
- `join1 -> B=true` (B is true)
- `join1 -> B=false` (B is false)
- `B=true -> exit`
- `B=false -> exit`

With edge coverage, the following four paths are all distinguishable:

| Path | A | B | Edges hit |
|---|---|---|---|
| 1 | T | T | entry->At, At->j1, j1->Bt, Bt->exit |
| 2 | T | F | entry->At, At->j1, j1->Bf, Bf->exit |
| 3 | F | T | entry->Af, Af->j1, j1->Bt, Bt->exit |
| 4 | F | F | entry->Af, Af->j1, j1->Bf, Bf->exit |

Block coverage only distinguishes 3 states (both blocks hit, only block_1
hit, only block_2 hit). Edge coverage distinguishes all 4. Edge coverage
is strictly more informative.

### Practical impact

In real programs, edge coverage catches state-dependent bugs that block
coverage misses. Consider:

```c
int *ptr = NULL;
if (config_flag) ptr = allocate();
// ... many lines later ...
if (use_flag) *ptr;  // NULL deref only when config_flag=false, use_flag=true
```

Block coverage shows both blocks as covered once you've hit each
independently. Edge coverage shows that the specific transition
`config=false -> use=true` is uncovered, directing the fuzzer to find it.

**So what:** Always use edge coverage. All modern fuzzers (AFL++, libFuzzer,
honggfuzz) default to edge coverage. If you're writing a custom fuzzer or
using an unusual framework, verify it's edge-based, not block-based.

---

## Bitmap Collisions

A collision occurs when two distinct edges map to the same bitmap index.
The fuzzer cannot distinguish them, which is equivalent to being blind
to one of the two edges.

### Why collisions happen

With AFL-style `XOR` instrumentation, each edge ID is
`cur_block XOR prev_block`, modulo `MAP_SIZE`. With N edges and a map of
size M:

```
Collision probability for at least one pair (birthday problem):
    P(collision) ~ 1 - e^(-N^2 / (2 * M))

With M = 65536:
    1,000 edges: ~0.5% collision rate
    5,000 edges: ~16% collision rate
    10,000 edges: ~53% collision rate
    20,000 edges: ~95% collision rate
```

A real-world program (libpng, libxml2, OpenSSL) easily has 10,000-50,000
edges. At default map size, **more than half the edges may collide**.

### How collisions hurt

1. **Missed coverage:** Input A covers edge X (bitmap index 42). Input B
   covers edge Y (also bitmap index 42). The fuzzer thinks B adds no new
   coverage and discards it. Edge Y is never explored.

2. **Hitcount confusion:** Edge X is hit 3 times, edge Y is hit 5 times.
   The bitmap stores 8 (the sum, bucketed). The fuzzer can't tell that
   two different edges contributed.

3. **Corpus pollution:** Inputs that change the combined hitcount of
   colliding edges get saved even though they don't represent genuinely
   new behavior.

### Solutions

**Increase map size:** Set `AFL_MAP_SIZE` to a larger power of 2.

```bash
export AFL_MAP_SIZE=262144   # 256 KB, 4x default
```

Doubling the map size halves collision probability. The cost is more memory
and slightly slower bitmap comparison.

**Use LTO collision-free mode:** `afl-clang-lto` assigns edge IDs at link
time using the full program CFG. Each edge gets a unique index. Zero
collisions by construction.

```bash
CC=afl-clang-lto CXX=afl-clang-lto++ ./configure
make
```

**Use PCGUARD:** `__sanitizer_cov_trace_pc_guard` assigns sequential guard
IDs. Collisions only happen if `N_edges > MAP_SIZE`, which is rare with
a sufficiently large map.

### Diagnosing collisions

AFL++ reports `map density` in its status screen:

```
  map density : 5.42% / 8.31%
                ^^^^    ^^^^
                current  ever seen
```

If "ever seen" exceeds ~30%, collisions are likely significant. Increase
`AFL_MAP_SIZE` or switch to LTO.

**So what:** If your fuzzer plateaus early and you're fuzzing a large target,
check map density. If it's high, collisions are actively hiding coverage.
Switch to LTO or increase `AFL_MAP_SIZE` to `2 * N_edges` as a minimum.

---

## Energy / Power Scheduling

Not all corpus entries deserve equal mutation time. Power scheduling
allocates "energy" (number of mutations) to each seed based on properties
that predict its value.

### Seed energy factors

A seed's energy is a function of:

| Factor | Why it matters |
|---|---|
| **Execution speed** | Fast seeds allow more mutations per second |
| **Input size** | Smaller inputs produce more targeted mutations |
| **Coverage contribution** | Seeds that discovered new edges are more promising |
| **Edge rarity** | Seeds covering rare edges explore under-tested code |
| **Depth** | How many mutations deep this seed is from the initial corpus |
| **Creation time** | Newer seeds may explore fresher frontiers |

### AFL++ power schedules (`-p` flag)

| Schedule | Strategy | Best when |
|---|---|---|
| `FAST` | Favors fast, small inputs. Exponential energy scaling for seeds exercised fewer times. | General purpose (default). |
| `EXPLORE` | Uniform energy across all seeds. No favorites. | Early fuzzing when the corpus is small and you want broad exploration. |
| `EXPLOIT` | Concentrates energy on seeds with the highest coverage contribution. | Late-stage fuzzing when new coverage is rare and you want to go deep on promising paths. |
| `RARE` | Strongly favors seeds that cover edges hit by few other seeds. | Targets with large, well-covered surfaces where the remaining bugs hide in rare code paths. |
| `COE` | Cut-Off Exponential. Like FAST but caps energy for seeds that have been fuzzed many times. Prevents one seed from monopolizing the queue. | Large corpora where a few seeds dominate. |
| `MMOPT` | Maximizes the probability of finding the optimal mutation. Combines multiple heuristics. | Research benchmarks. Less predictable in practice. |
| `SEEK` | Similar to EXPLOIT but with decay. Reduces energy for seeds that stop producing new coverage. | Long-running campaigns (24h+) where seed productivity decays over time. |
| `LIN` | Linear scaling. Energy proportional to coverage uniqueness. | Simpler alternative to FAST with more predictable behavior. |
| `QUAD` | Quadratic scaling. Aggressive version of LIN. | When you want even stronger emphasis on high-coverage seeds. |

### Energy in practice

The default (`FAST`) schedule works well for most targets. Switch to
`EXPLORE` if you suspect the fuzzer is fixated on a small number of seeds.
Switch to `RARE` if coverage is plateaued but you believe rare code paths
remain unexplored.

```bash
# Check which seeds are getting mutated
afl-whatsup -s output_dir/

# Switch to RARE schedule
afl-fuzz -p rare -i corpus -o output -- ./target @@
```

**So what:** If your fuzzer has high coverage but isn't finding crashes,
change the power schedule. `FAST` can get stuck in a local optimum. `RARE`
forces exploration of edges that most seeds don't cover, which is where
remaining bugs tend to hide.

---

## Mutation Pipeline

AFL++ applies mutations in stages, from precise to chaotic.

### Stage 1: Deterministic mutations

Applied systematically to every bit/byte position in the input.

```
Bit flips:    flip 1 bit, 2 bits, 4 bits at every position
Byte flips:   flip 1 byte, 2 bytes, 4 bytes at every position
Arithmetic:   add/subtract 1..35 to every 8/16/32-bit value
Interesting:  replace every 8/16/32-bit value with "interesting" constants
```

Deterministic mutations are exhaustive but slow. For a 1 KB input, bit
flips alone require `8192 * 3 = 24,576` executions. This stage dominates
runtime for large inputs.

### Stage 2: Havoc

Random combinations of all mutation operators applied in sequence. Each
havoc round applies 2-128 random transformations to the input:

```
- Random bit flip
- Random byte set
- Random block deletion
- Random block insertion (from another input or random bytes)
- Random arithmetic on random position
- Random dictionary token insertion
- Random byte overwrite with interesting value
- Random chunk duplication
- Random chunk replacement from another corpus entry
```

Havoc is where most bugs are found. It's fast (no systematic enumeration)
and combinatorially powerful (multiple mutations per execution).

### Stage 3: Splice (MOpt)

Combine two corpus entries by splitting each at a random point and
concatenating the first half of one with the second half of another:

```
Input A: [AAAA|AAAAAA]
Input B: [BBBB|BBBBBB]
Splice:  [AAAA|BBBBBB]  (crossover at position 4)
```

This is evolutionary crossover. It combines features from two inputs that
independently found different coverage, hoping the combination reaches
deeper code.

### When deterministic stages run

AFL++ skips deterministic stages when:

- `-d` flag is passed (skip deterministic, go straight to havoc)
- `-p fast` is the power schedule (FAST schedule skips deterministic by
  default for seeds that aren't "favored")
- The input is too large (> 10 KB by default)
- The input was already fuzzed through deterministic stages

libFuzzer has no deterministic stage at all. It only does havoc-like random
mutations. This makes it faster per-execution but less thorough on
individual inputs.

**So what:** For short-running campaigns (< 1 hour), skip deterministic
stages (`-d`). For long campaigns (24h+), let deterministic stages run --
they systematically discover dictionary tokens via bit-flip artifact
detection. For very large inputs (> 10 KB), always skip deterministic.

---

## Mutation Operators Taxonomy

Complete reference for every mutation operator.

### Bit-level operators

| Operator | Description | When most effective |
|---|---|---|
| Bit flip 1/1 | Flip 1 bit, walking through every position | Flag bytes, boolean fields |
| Bit flip 2/1 | Flip 2 adjacent bits, step 1 | Multi-bit flags |
| Bit flip 4/1 | Flip 4 adjacent bits (nibble), step 1 | Nibble-encoded fields |

### Byte-level operators

| Operator | Description | When most effective |
|---|---|---|
| Byte flip 8/8 | Flip entire byte, step 1 byte | Single-byte fields, checksums |
| Byte flip 16/8 | Flip 2 bytes, step 1 byte | 16-bit length/type fields |
| Byte flip 32/8 | Flip 4 bytes, step 1 byte | 32-bit integers, pointers |

### Arithmetic operators

| Operator | Description | When most effective |
|---|---|---|
| Arith 8 +/-1..35 | Add/subtract small values to each byte | Counters, lengths, off-by-one |
| Arith 16 +/-1..35 | Add/subtract to each 16-bit value (both endians) | 16-bit sizes, ports |
| Arith 32 +/-1..35 | Add/subtract to each 32-bit value (both endians) | 32-bit offsets, sizes |

The range +/-35 was chosen empirically by the AFL author. Most interesting
boundary values in real programs are within 35 of the current value.

### Interesting value replacement

| Width | Values |
|---|---|
| 8-bit | `0, 1, 16, 32, 64, 100, 127, 128, 255` |
| 16-bit | `0, 128, 255, 256, 512, 1000, 1024, 4096, 32767, 32768, 65535` |
| 32-bit | `0, 1, 32768, 65535, 65536, 100663045, 2147483647, 2147483648, 4294967295` |

These target boundary conditions: signed/unsigned overflow, power-of-two
boundaries, common buffer sizes, and max values for integer types.

### Dictionary operators

| Operator | Description | When most effective |
|---|---|---|
| Token insert | Insert dictionary token at random position | Keyword-driven parsers |
| Token overwrite | Overwrite bytes at random position with token | Fixed-position magic bytes |
| Auto-dictionary | Tokens discovered by bit-flip artifact detection | Unknown formats |

### Havoc operators

| Operator | Description |
|---|---|
| Random bit flip | Flip random bit |
| Set random byte | Overwrite random byte with random value |
| Delete random block | Remove 1-N bytes at random position |
| Clone random block | Duplicate a chunk at random position |
| Insert random block | Insert random bytes at random position |
| Overwrite with chunk | Copy chunk from elsewhere in same input |
| Overwrite with corpus chunk | Copy chunk from another corpus entry |
| Insert dictionary token | Insert token from user or auto-dictionary |
| Overwrite with interesting value | Replace random int with interesting value |
| Arithmetic on random position | Add/subtract small value at random offset |

### Splice (crossover)

| Operator | Description | When most effective |
|---|---|---|
| Single-point crossover | Split two inputs at a random point, combine halves | Combining independent features from two inputs that found different coverage |

**So what:** When the fuzzer is stuck, think about which operators can
produce the needed input transformation. If the target expects a specific
4-byte magic number, no amount of bit flipping will find it efficiently --
you need a dictionary. If two independently-discovered code paths need to
be combined, splice is the only operator that can do it in one step.

---

## CMPLOG / Redqueen

CMPLOG solves the hardest problem in mutation-based fuzzing: passing
multi-byte comparisons.

### The problem

Consider:

```c
if (memcmp(input, "MAGIC_HEADER", 12) == 0) {
    parse_body(input + 12);  // interesting code behind a 12-byte barrier
}
```

Random mutation needs to guess all 12 bytes correctly. Probability:
`1/256^12 ~ 10^-29`. Even at 10 billion executions per second, the
heat death of the universe arrives first.

### How CMPLOG works

1. **Instrument comparisons:** The compiler inserts hooks on every `cmp`,
   `memcmp`, `strcmp`, `switch`, and similar operations. These hooks log
   both operands to a shared buffer.

2. **Run the input:** Execute the target with CMPLOG instrumentation. For
   each comparison, record `(operand_from_input, operand_from_program)`.

3. **Apply I2S (Input-To-State):** Search the input for bytes matching
   `operand_from_input`. Replace them with `operand_from_program`. If
   the comparison was `memcmp(input+5, "MAGIC", 5)` and `input+5` is
   currently `"AAAAA"`, the fuzzer tries replacing those bytes with
   `"MAGIC"`.

### The I2S correspondence principle

The key insight: if bytes in the input appear as one side of a comparison,
and the other side comes from program constants, then overwriting those
input bytes with the program constant will satisfy the comparison. This
is Input-To-State correspondence -- the input state directly corresponds
to a comparison operand.

```
Before CMPLOG:
  input:   [... A A A A A ...]
  compare: memcmp(input+5, "MAGIC", 5)
  result:  FAIL (AAAAA != MAGIC)

After I2S replacement:
  input:   [... M A G I C ...]
  compare: memcmp(input+5, "MAGIC", 5)
  result:  PASS -- now explores code behind the comparison
```

### What CMPLOG solves

- **Magic bytes:** File format headers (`%PDF`, `GIF89a`, `\x7fELF`)
- **Checksums:** CRC32, Adler32 when the expected value is computed and
  compared
- **Enum matching:** `switch(type)` with many cases
- **String comparisons:** `strcmp(input_field, "expected_value")`
- **Length checks:** `if (len == expected_len)`

### Enabling CMPLOG in AFL++

```bash
# Build the CMPLOG binary (separate from the main fuzz binary)
afl-clang-fast -fsanitize-coverage=trace-cmp -o target_cmplog target.c

# Run with -c flag pointing to the CMPLOG binary
afl-fuzz -i corpus -o output -c ./target_cmplog -- ./target @@
```

CMPLOG adds ~20-30% overhead per execution but can unlock entire program
regions that would otherwise be unreachable.

### CMPLOG levels in AFL++

| Level | Behavior |
|---|---|
| `-l 1` | Basic I2S, transforms on comparison operands |
| `-l 2` | + arithmetic transforms (add/sub on operands) |
| `-l 3` | + exhaustive transforms including partial matches |

Default (`-l 2`) is the best tradeoff. Level 3 is expensive and rarely
worth the overhead.

**So what:** If your target has magic bytes, checksums, or string comparisons
and the fuzzer isn't getting past them, enable CMPLOG. It's the single
highest-impact configuration change you can make for comparison-heavy
targets.

---

## Value Profile

libFuzzer's value profile extends coverage feedback beyond "which edges were
hit" to "what values were compared."

### How it works

With `-use_value_profile=1`, libFuzzer instruments every comparison to
track the Hamming distance between operands:

```c
// Conceptual: what value profile tracks
void __sanitizer_cov_trace_cmp8(uint64_t Arg1, uint64_t Arg2) {
    // Count matching bits between operands
    uint64_t diff = Arg1 ^ Arg2;
    int matching_bits = 64 - __builtin_popcountll(diff);
    // Record matching_bits in coverage feedback
    update_value_profile(pc, matching_bits);
}
```

Every time a comparison gets **closer to matching** (more bits equal),
it's treated as new coverage. This creates a gradient toward satisfying
comparisons.

### Why this is powerful

Standard edge coverage is binary for each comparison: the comparison is
either taken or not. Value profile adds granularity:

```
Attempt 1: compare(input, 0xDEADBEEF) -> 0 matching bits  (far)
Attempt 2: compare(input, 0xDEADBEEF) -> 8 matching bits  (closer)
Attempt 3: compare(input, 0xDEADBEEF) -> 24 matching bits (much closer)
Attempt 4: compare(input, 0xDEADBEEF) -> 32 matching bits (match!)
```

Each step toward the correct value is rewarded, guiding the fuzzer through
comparison barriers incrementally.

### Performance cost

Value profile adds approximately 20% execution overhead. The coverage map
grows significantly because each comparison x bit-count combination is a
separate coverage entry.

### Empirical results

From the libFuzzer documentation and FuzzBench evaluations:

- ~20% slower per execution
- ~30% more bugs found on benchmarks with comparison-heavy targets
- Negligible benefit on targets without multi-byte comparisons

### Value profile vs CMPLOG

| Property | Value Profile | CMPLOG |
|---|---|---|
| Approach | Gradient toward matching | Direct operand substitution |
| Speed | 20% slower | 20-30% slower |
| Comparison solving | Incremental (many steps) | Often 1-shot |
| Works on checksums | Poorly (Hamming distance misleading) | Well (sees expected value) |
| Works on magic bytes | Slowly (bit-by-bit convergence) | Instantly (direct substitution) |
| Implementation | libFuzzer only | AFL++ (also adaptable) |

CMPLOG is generally more effective for direct comparisons. Value profile is
better for complex computed comparisons where I2S correspondence doesn't
hold.

**So what:** If you're using libFuzzer and your target has multi-byte
comparisons, enable value profile. If you're using AFL++, use CMPLOG
instead -- it's more direct and usually faster at solving comparisons.

---

## Why This Matters Practically

Every internal concept maps to a specific diagnostic action when fuzzing
gets stuck.

### Coverage plateau diagnostics

```
Symptom: "Coverage hasn't increased in 2 hours"

Diagnostic flowchart:

1. Check map density (afl-whatsup or status screen)
   -> High (>30%)?
      Fix: increase AFL_MAP_SIZE or use LTO mode
      Why: bitmap collisions hiding real coverage (Section 5)

2. Check comparison coverage (are there multi-byte compares?)
   -> Many uncovered comparison branches?
      Fix: enable CMPLOG (-c flag with cmplog binary)
      Why: random mutation can't solve comparisons (Section 9)

3. Check corpus quality (afl-cmin on corpus)
   -> Many redundant entries?
      Fix: minimize corpus, check for non-determinism in target
      Why: redundant seeds waste mutation cycles

4. Check power schedule (are interesting seeds getting mutated?)
   -> Few seeds dominating execution time?
      Fix: switch to EXPLORE or RARE schedule
      Why: power schedule starving promising seeds (Section 6)

5. Check execution speed (execs/sec in status)
   -> Low speed (<100/sec)?
      Fix: profile target, reduce I/O, use persistent mode
      Why: slow targets need more time per coverage unit

6. Check if stuck at depth
   -> High coverage but no crashes?
      Fix: switch to EXPLOIT or SEEK schedule, add dictionaries
      Why: need to go deeper on existing paths (Section 6)
```

### Quick reference: internal concept to diagnostic action

| Concept | Symptom | Action |
|---|---|---|
| Bitmap collisions | Plateau despite large target | `AFL_MAP_SIZE=262144` or LTO |
| Wrong power schedule | Few seeds dominate queue | `-p rare` or `-p explore` |
| Missing CMPLOG | Stuck at magic bytes / checksums | `-c ./target_cmplog -l 2` |
| Deterministic overhead | Slow on large inputs | `-d` to skip deterministic |
| No dictionary | Parser target stuck at syntax level | `-x dict.txt` with format tokens |
| Hitcount instability | Corpus exploding in size | Check for non-determinism, add `AFL_NO_AFFINITY` |
| Map too small | `map density > 50%` | Double `AFL_MAP_SIZE` |
| Missing edge coverage | Custom fuzzer, block-only | Switch to edge-instrumented build |

### Reading the AFL++ status screen through the lens of internals

```
+----------------------------------------------------+
|        american fuzzy lop ++4.09a          |
+----------------------------------------------------+
| run time : 0 days, 3 hrs, 12 min          |  <- Long enough?
| last new find : 0 days, 1 hrs, 45 min     |  <- STUCK if > 30min
| corpus count : 3847                        |  <- Growing = good
| saved crashes : 12                         |
| exec speed : 4523/sec                      |  <- Want >1000/sec
| map density : 12.43% / 18.72%             |  <- >30% = collisions
| stability : 98.21%                        |  <- <90% = non-determinism
+----------------------------------------------------+
```

Key indicators:
- **last new find > 30 min:** Coverage is stuck. Run the diagnostic
  flowchart above.
- **map density > 30%:** Collisions are significant. Increase map size.
- **stability < 90%:** Target has non-deterministic behavior. The bitmap
  is noisy. Fix the target or use `AFL_NO_AFFINITY`.
- **exec speed < 100/sec:** Target is too slow. Use persistent mode
  or `AFL_TMPDIR` to reduce I/O.

**So what:** The fuzzer status screen is a dashboard into these internals.
Every number maps to a specific subsystem. When something looks wrong,
you now know which knob to turn.

---

## See Also

- [AFLPP.md](AFLPP.md) -- AFL++ configuration, modes, and flags reference
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) -- Execution speed
  optimization, persistent mode, shared memory tuning
- [CORPUS.md](CORPUS.md) -- Corpus management, minimization, seed
  selection, and quality metrics
