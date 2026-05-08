# Self-Test: testing-fuzzing

## Positive Triggers (MUST activate)

- "Fuzz this parser"
- "cargo-fuzz" / "cargo fuzz" / "libfuzzer"
- "Find crashes in this code"
- "Security audit this input processing"
- "Write a fuzz target for this"
- "Structure-aware fuzzing"
- "Differential fuzzing"
- "AFL++" / "honggfuzz" / "bolero"
- "AddressSanitizer" / "ASan" / "sanitizer"
- "How do I fuzz this protocol?"
- "Corpus management" / "seed corpus"
- "This parser handles untrusted input — how do I test it?"
- "Coverage-guided testing"
- "Set up OSS-Fuzz for my project"
- "My fuzzer isn't finding new coverage"
- "Fuzz regression in CI"
- "How to fuzz a Go function"
- "Jazzer" / "JQF" / "Atheris"
- "fast-check property testing"
- "Hypothesis fuzzing"
- "proptest"
- "Schemathesis" / "API fuzzing"
- "boofuzz" / "network protocol fuzzing"
- "Echidna" / "forge fuzz" / "smart contract fuzzing"
- "Make this code fuzzable"
- "What should I fuzz in this project?"
- "Custom mutator for compressed format"
- "ClusterFuzz" / "ClusterFuzzLite"
- "zzuf"
- "radamsa"
- "cargo careful" / "miri"
- "fuzz_target"
- "FuzzedDataProvider"
- "How to find crashes in this code"
- "libprotobuf-mutator"
- "oss-fuzz" / "OSS-Fuzz"
- "generative testing"
- "QuickCheck"
- "LLVMFuzzerTestOneInput"
- "Medusa"
- "syzkaller"

## Negative Triggers (MUST NOT activate)

- "Test this ML model's accuracy" (use /testing-metamorphic)
- "Compare against reference implementation only" (use /testing-conformance-harnesses)
- "Snapshot test this output" (use /testing-golden-artifacts)
- "Mock-free database tests" (use /testing-real-service-e2e-no-mocks)
- "Write unit tests for this function" (standard testing)
- "Optimize this slow function" (use /extreme-software-optimization)
- "Formal verification" / "prove this correct" (use /lean-formal-feedback-loop)
- "Load testing" / "stress testing" / "benchmark performance" (performance testing, not fuzzing)
- "Chaos testing" / "fault injection" / "chaos monkey" (resilience testing)
- "Mutation testing" / "mutant killing" (code mutation, not input mutation)

## Boundary Cases

- "proptest" → Activate (proptest is a fuzzing/PBT framework)
- "fast-check" → Activate (property-based testing is fuzzing-adjacent)
- "Hypothesis" → Activate (Python's PBT framework, directly used for fuzzing)
- "Round-trip testing" → Activate if testing serialization robustness; otherwise /testing-conformance-harnesses
- "Find bugs in this code" → Activate if input-processing code; otherwise /multi-pass-bug-hunting
- "Property-based testing" → Activate (PBT is the gateway to fuzzing; this skill covers PBT frameworks)
- "Random testing" → Activate if input-processing; otherwise may be standard randomized tests
- "Pen testing" / "security testing" → Activate if focused on input-processing / crash discovery; NOT for auth/access-control testing
- "Symbolic execution" / "concolic testing" → NOT primarily (adjacent technique), but activate if asked about hybrid fuzzing
- "Regression testing with crash inputs" → Activate (this is the triage workflow)
- "Coverage-guided testing" → Activate (core fuzzing concept)
- "Mutation testing" → NOT (mutating code, not inputs — completely different technique despite similar name)
- "AFL" without "++" → Activate (vanilla AFL is still fuzzing)
- "Generative testing" → Activate (synonym for PBT in some ecosystems)
- "QuickCheck" → Activate (Haskell-origin PBT concept, applies broadly)
- "Load testing" / "stress testing" → NOT (performance testing, not input fuzzing)
- "Chaos engineering" / "fault injection" → NOT (resilience, not input fuzzing)
