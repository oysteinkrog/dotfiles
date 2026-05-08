# Cloud Fuzzing: Scaling Campaigns Beyond Local Hardware

When a local machine is saturated — all cores busy, coverage plateauing, multiple
targets queued — cloud infrastructure lets you throw hundreds of vCPUs at the problem
for hours or days, then tear everything down.

---

## When Cloud Fuzzing

Move to cloud when any of these apply:

- **All local cores are busy.** Your 16-core workstation is maxed and you have more
  targets or need faster results.
- **Campaign needs 100+ vCPUs.** Critical security targets (parsers, TLS stacks,
  kernel interfaces) warrant brute-force coverage.
- **Multiple targets in parallel.** Five targets each need 24h of fuzzing. Locally
  that's 5 days sequential; in cloud, 24h parallel.
- **Continuous fuzzing.** Always-on fuzzing that catches regressions on every commit,
  a la ClusterFuzz or OSS-Fuzz.
- **Ensemble campaigns.** Running AFL++ + libFuzzer + honggfuzz across dozens of cores
  with shared corpus needs more hardware than most workstations provide.

Stay local when:
- Target is simple and saturates coverage in under an hour on 4 cores.
- You're iterating on the harness (edit-compile-fuzz cycle is faster locally).
- Cost sensitivity — even spot instances add up over multi-day campaigns.

---

## Cost Estimation

### Formula

```
Total cost = vCPUs x hours x $/vCPU-hr
```

### Instance Rates (approximate, US regions, 2024-2025)

| Instance         | vCPUs | On-Demand $/hr | Spot $/hr   | Notes                |
|------------------|-------|----------------|-------------|----------------------|
| AWS c6i.xlarge   | 4     | $0.17          | $0.05       | Intel, compute-opt   |
| AWS c7g.xlarge   | 4     | $0.14          | $0.04       | Graviton (ARM)       |
| AWS c6i.8xlarge  | 32    | $1.36          | $0.41       | Workhorse for AFL++  |
| GCE c2-std-4     | 4     | $0.17          | $0.05       | Intel, compute-opt   |
| GCE c2-std-60    | 60    | $2.54          | $0.76       | Large campaigns      |
| Azure F4s_v2     | 4     | $0.17          | $0.04       | Compute-optimized    |

### Example Campaigns

| Campaign           | Setup               | Duration | Cost (spot) |
|--------------------|----------------------|----------|-------------|
| Quick audit        | 16 vCPUs             | 4h       | ~$3.20      |
| Standard campaign  | 64 vCPUs             | 24h      | ~$82        |
| Deep security      | 256 vCPUs            | 72h      | ~$922       |
| Continuous (month) | 32 vCPUs always-on   | 720h     | ~$1,152     |

### Cost Optimization

- **Spot/preemptible instances** — 60-80% cheaper. Use for all fuzzing workloads.
- **ARM instances** (Graviton, Ampere) — 20-30% cheaper per vCPU. AFL++ and
  libFuzzer both support ARM. Honggfuzz hardware features (Intel PT) are x86-only.
- **Autoscaling** — Start with fewer instances. If coverage is still growing after 4h,
  scale up. If plateaued, scale down.
- **Scheduled teardown** — Set instance termination timers. Never leave fuzzing VMs
  running indefinitely.

---

## Spot/Preemptible Instances

Spot instances are 2-5x cheaper but can be reclaimed with 2 minutes notice (AWS) or
30 seconds (GCP). Fuzzing is an ideal spot workload because:

1. Fuzzing is stateless — the process can restart from the corpus.
2. Crashes are written to disk immediately.
3. AFL++ has built-in resume support.

### Handling Preemption

```bash
# AFL++ auto-resume: restarts from where it left off
export AFL_AUTORESUME=1
afl-fuzz -i- -o /mnt/persistent/afl-out -- ./target @@
# -i- means "resume from output directory"

# Sync corpus to persistent storage every 5 minutes
while true; do
  aws s3 sync /mnt/persistent/afl-out/main/queue/ s3://fuzzing-corpus/target/ \
    --quiet --no-progress
  aws s3 sync /mnt/persistent/afl-out/main/crashes/ s3://fuzzing-crashes/target/ \
    --quiet --no-progress
  sleep 300
done
```

### Preemption Detection

```bash
# AWS: metadata endpoint signals termination 2 min ahead
# GCP: metadata endpoint signals 30 sec ahead

# AWS spot termination watcher
while true; do
  if curl -s http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q stop; then
    echo "Spot termination notice — syncing corpus"
    aws s3 sync /mnt/persistent/afl-out/ s3://fuzzing-state/$(hostname)/ --quiet
    break
  fi
  sleep 5
done
```

### Persistent Storage Strategy

```
              +-------------------+
              |  S3 / GCS / Blob  |    <-- durable corpus + crash storage
              +---------+---------+
                        ^
                        | sync every 5 min
              +---------+---------+
              |  Spot Instance    |
              |  /mnt/persistent  |    <-- local SSD (instance store or EBS)
              |   afl-out/        |
              |   corpus/         |
              +---------+---------+
                        ^
                        | AFL_AUTORESUME
              +---------+---------+
              |  New Spot Instance|    <-- pulls corpus from S3 on startup
              +-------------------+
```

---

## Docker Fuzzing Containers

### Base Dockerfile

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Core dependencies
RUN apt-get update && apt-get install -y \
    build-essential clang-18 lld-18 llvm-18 \
    afl++ afl++-clang \
    python3 python3-pip \
    git curl wget \
    libssl-dev pkg-config \
    && apt-get clean && rm -r /var/lib/apt/lists

# Rust toolchain + cargo-fuzz
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . $HOME/.cargo/env \
    && rustup default nightly \
    && cargo install cargo-fuzz honggfuzz

# Set clang as default
RUN update-alternatives --install /usr/bin/cc cc /usr/bin/clang-18 100 \
    && update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-18 100

ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /fuzz
COPY . /fuzz

# Default: run AFL++
CMD ["afl-fuzz", "-i", "corpus", "-o", "out", "--", "./target", "@@"]
```

### Running with Sanitizers

```bash
# ASan requires relaxed seccomp and expanded virtual memory
docker run --rm \
  --security-opt seccomp=unconfined \
  --ulimit core=0 \
  -v $(pwd)/corpus:/fuzz/corpus \
  -v $(pwd)/out:/fuzz/out \
  fuzzing-image:latest

# QEMU mode (for uninstrumented binaries)
docker run --rm \
  --privileged \
  -v $(pwd)/corpus:/fuzz/corpus \
  -v $(pwd)/out:/fuzz/out \
  fuzzing-image:latest \
  afl-fuzz -Q -i corpus -o out -- ./target_no_inst @@
```

### Multi-Target Container

```dockerfile
# Build multiple targets in one image
RUN cd /fuzz/target-json && cargo fuzz build \
    && cd /fuzz/target-xml && cargo fuzz build \
    && cd /fuzz/target-proto && cargo fuzz build

# Entrypoint script selects target via env var
COPY entrypoint.sh /entrypoint.sh
CMD ["/entrypoint.sh"]
```

```bash
# entrypoint.sh
#!/bin/bash
case "$FUZZ_TARGET" in
  json)  cargo fuzz run fuzz_json -- -max_total_time=3600 ;;
  xml)   cargo fuzz run fuzz_xml -- -max_total_time=3600 ;;
  proto) cargo fuzz run fuzz_proto -- -max_total_time=3600 ;;
  *)     echo "Set FUZZ_TARGET to json|xml|proto"; exit 1 ;;
esac
```

---

## Multi-Machine AFL++

AFL++ supports distributed fuzzing through a primary/secondary architecture with a
shared filesystem.

### Architecture

```
  Machine A (primary)          Machine B (secondary)       Machine C (secondary)
  +-------------------+       +-------------------+       +-------------------+
  | afl-fuzz -M main  |       | afl-fuzz -S sec01 |       | afl-fuzz -S sec02 |
  | afl-fuzz -S sec00 |       | afl-fuzz -S sec03 |       | afl-fuzz -S sec04 |
  +--------+----------+       +--------+----------+       +--------+----------+
           |                           |                           |
           v                           v                           v
  +--------+----------+       +--------+----------+       +--------+----------+
  | /nfs/afl-out/main |       | /nfs/afl-out/sec01|       | /nfs/afl-out/sec02|
  | /nfs/afl-out/sec00|       | /nfs/afl-out/sec03|       | /nfs/afl-out/sec04|
  +-------------------+       +-------------------+       +-------------------+
           \                           |                          /
            \                          |                         /
             +-------------------------+------------------------+
                                       |
                              +--------+--------+
                              | NFS / EFS share  |
                              | /nfs/afl-out/    |
                              +-----------------+
```

### Setup

```bash
# Machine A — NFS server + primary fuzzer
sudo apt install nfs-kernel-server
echo "/data/afl-out *(rw,sync,no_subtree_check)" >> /etc/exports
sudo exportfs -a

afl-fuzz -M main -i /data/corpus -o /data/afl-out -- ./target @@
afl-fuzz -S sec00 -i /data/corpus -o /data/afl-out -p rare -- ./target @@

# Machine B — mount NFS + run secondaries
sudo mount machine-a:/data/afl-out /data/afl-out
afl-fuzz -S sec01 -i /data/corpus -o /data/afl-out -- ./target @@
afl-fuzz -S sec03 -i /data/corpus -o /data/afl-out -p explore -- ./target @@

# Machine C — same pattern
sudo mount machine-a:/data/afl-out /data/afl-out
afl-fuzz -S sec02 -i /data/corpus -o /data/afl-out -p exploit -- ./target @@
afl-fuzz -S sec04 -i /data/corpus -o /data/afl-out -- ./target @@
```

### Alternative: rsync-Based Sharing

If NFS is not available (e.g., cross-region), use periodic rsync:

```bash
# On each secondary, every 10 minutes:
while true; do
  # Push local findings to primary
  rsync -a /data/afl-out/sec01/queue/ primary:/data/afl-out/sec01/queue/
  # Pull primary and other secondaries' findings
  rsync -a primary:/data/afl-out/main/queue/ /data/afl-out/main/queue/
  sleep 600
done
```

### Power Schedule Diversity

Assign different power schedules to secondaries for maximum diversity:

```bash
# main:    default (explore)
# sec00:   -p rare        (prioritize rarely-hit edges)
# sec01:   -p fast        (favor fast inputs)
# sec02:   -p exploit     (focus on high-coverage inputs)
# sec03:   -p explore     (balanced)
# sec04:   -p coe         (cut-the-edges, novel coverage)
```

---

## AWS/GCP/Azure Patterns

### AWS EC2 Spot Fleet

```bash
# Launch spot fleet with 8 c6i.4xlarge instances (128 vCPUs total)
aws ec2 request-spot-fleet --spot-fleet-request-config '{
  "TargetCapacity": 8,
  "SpotPrice": "0.20",
  "LaunchSpecifications": [{
    "ImageId": "ami-fuzzing-base",
    "InstanceType": "c6i.4xlarge",
    "KeyName": "fuzzing-key",
    "SecurityGroups": [{"GroupId": "sg-fuzzing"}],
    "UserData": "<base64-encoded startup script>"
  }],
  "TerminateInstancesWithExpiration": true,
  "ValidUntil": "2025-01-15T00:00:00Z"
}'

# Corpus storage: S3
aws s3 mb s3://fuzzing-corpus-project-x
# Startup script pulls corpus, starts AFL++, syncs results to S3
```

### GCP Preemptible VMs

```bash
# Create instance template
gcloud compute instance-templates create fuzz-template \
  --machine-type=c2-standard-16 \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --image-family=ubuntu-2404-lts \
  --image-project=ubuntu-os-cloud \
  --metadata-from-file=startup-script=fuzz-startup.sh

# Create managed instance group
gcloud compute instance-groups managed create fuzz-group \
  --template=fuzz-template \
  --size=8 \
  --zone=us-central1-a

# Corpus storage: GCS
gsutil mb gs://fuzzing-corpus-project-x
```

### Azure Spot VMs

```bash
# Create spot VM scale set
az vmss create \
  --resource-group fuzzing-rg \
  --name fuzz-vmss \
  --image Ubuntu2404 \
  --vm-sku Standard_F16s_v2 \
  --instance-count 8 \
  --priority Spot \
  --eviction-policy Deallocate \
  --max-price 0.20 \
  --custom-data fuzz-startup.sh

# Corpus storage: Azure Blob
az storage container create --name fuzzing-corpus --account-name fuzzstore
```

### Startup Script Template (all providers)

```bash
#!/bin/bash
set -euo pipefail

# Install dependencies
apt-get update && apt-get install -y afl++ awscli

# Pull corpus from object storage
aws s3 sync s3://fuzzing-corpus/target/ /data/corpus/ || true

# Pull pre-built target binary
aws s3 cp s3://fuzzing-binaries/target_afl /data/target_afl
chmod +x /data/target_afl

# Determine instance role (first instance is primary)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
if [ "$INSTANCE_ID" = "i-first-instance-id" ]; then
  MODE="-M main"
else
  MODE="-S ${INSTANCE_ID}"
fi

# Start fuzzing with auto-resume
export AFL_AUTORESUME=1
afl-fuzz $MODE -i /data/corpus -o /data/afl-out -- /data/target_afl @@ &

# Background sync loop
while true; do
  aws s3 sync /data/afl-out/ s3://fuzzing-state/$(hostname)/ --quiet
  sleep 300
done
```

---

## ClusterFuzz Architecture

Google's ClusterFuzz runs fuzzing at massive scale. Understanding its architecture
helps you decide whether to build something similar or use ClusterFuzzLite.

### How ClusterFuzz Works

```
  +------------------+
  | Web Dashboard    |    <-- Crash reports, coverage stats, bisection results
  +--------+---------+
           |
  +--------+---------+
  | Task Queue       |    <-- Pub/Sub: fuzz, minimize, reproduce, bisect, verify
  +--------+---------+
           |
  +--------+---------+
  | Bot VMs (100s)   |    <-- Preemptible GCE instances
  |  - Pull tasks    |
  |  - Run fuzzers   |
  |  - Upload crashes|
  |  - Report results|
  +--------+---------+
           |
  +--------+---------+
  | GCS Buckets      |    <-- Corpus, crashes, coverage data, build artifacts
  +------------------+
```

### Core Components

1. **Bot VMs** — Preemptible instances that pull tasks from a queue, run fuzzers for a
   set duration, upload results.
2. **Task queue** — Distributes work: fuzz task, minimize task, reproduce task,
   bisect task, fix-verification task.
3. **Crash processing** — Deduplicates crashes, minimizes test cases, finds regression
   ranges via git bisection.
4. **Coverage tracking** — Periodic coverage builds to measure progress.
5. **Fix verification** — After a fix lands, re-runs the crash to confirm it's fixed.

### ClusterFuzzLite

For most teams, ClusterFuzzLite is the right choice. It runs as GitHub Actions or
Cloud Build, requires minimal setup, and handles:

- Continuous fuzzing on every PR or nightly.
- Crash reporting as GitHub issues.
- Corpus management via GCS.
- Coverage reporting.

```yaml
# .github/workflows/clusterfuzzlite.yml
name: ClusterFuzzLite
on:
  schedule:
    - cron: '0 0 * * *'  # Nightly
jobs:
  Fuzzing:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google/clusterfuzzlite/actions/build_fuzzers@v1
        with:
          language: rust
      - uses: google/clusterfuzzlite/actions/run_fuzzers@v1
        with:
          fuzz-seconds: 600
          mode: batch
```

### When to Build Your Own vs. Use ClusterFuzzLite

| Factor                    | ClusterFuzzLite          | Custom ClusterFuzz       |
|---------------------------|--------------------------|--------------------------|
| Setup time                | Hours                    | Weeks                    |
| Scale                     | GitHub Actions runners   | Unlimited cloud VMs      |
| Cost                      | Free tier available      | Significant infra cost   |
| Crash management          | GitHub issues            | Full dashboard           |
| Bisection                 | No                       | Yes                      |
| Fix verification          | No                       | Yes                      |
| Multi-engine              | Limited                  | Full ensemble support    |
| Who should use            | Most projects            | Large security teams     |

---

## Monitoring and Alerting

### Metrics to Track

| Metric             | Source                          | Alert Threshold              |
|--------------------|---------------------------------|------------------------------|
| exec/s per core    | AFL++ stats, fuzzer stderr      | < 50% of initial rate        |
| Corpus size        | File count in corpus dir        | Growing > 10%/hr (bloat)     |
| Edge coverage      | afl-showmap, llvm-cov           | Plateau > 4h                 |
| Crash count        | Crash directory                 | Any new crash                |
| Unique crashes     | After dedup via afl-cmin/casr   | Any new unique crash         |
| Bot health         | Instance status, process check  | Bot down > 10 min            |
| Corpus sync lag    | S3 sync timestamps              | > 30 min behind              |

### Prometheus + Grafana Setup

```python
#!/usr/bin/env python3
"""Minimal AFL++ stats exporter for Prometheus."""
import os, time, glob
from prometheus_client import start_http_server, Gauge

execs_per_sec = Gauge('afl_execs_per_sec', 'Executions per second', ['instance'])
total_crashes = Gauge('afl_total_crashes', 'Total crashes', ['instance'])
corpus_count = Gauge('afl_corpus_count', 'Corpus entries', ['instance'])
coverage_edges = Gauge('afl_coverage_edges', 'Bitmap coverage', ['instance'])

def parse_stats(path):
    stats = {}
    with open(path) as f:
        for line in f:
            if ':' in line:
                k, v = line.split(':', 1)
                stats[k.strip()] = v.strip()
    return stats

def collect(afl_out):
    for sf in glob.glob(f'{afl_out}/*/fuzzer_stats'):
        instance = os.path.basename(os.path.dirname(sf))
        s = parse_stats(sf)
        execs_per_sec.labels(instance).set(float(s.get('execs_per_sec', 0)))
        total_crashes.labels(instance).set(int(s.get('saved_crashes', 0)))
        corpus_count.labels(instance).set(int(s.get('corpus_count', 0)))
        coverage_edges.labels(instance).set(int(s.get('bitmap_cvg', '0%').rstrip('%')))

if __name__ == '__main__':
    start_http_server(9100)
    while True:
        collect('/data/afl-out')
        time.sleep(15)
```

### Alert Rules

```yaml
# Prometheus alerting rules
groups:
  - name: fuzzing
    rules:
      - alert: FuzzerStalled
        expr: afl_execs_per_sec == 0
        for: 10m
        annotations:
          summary: "Fuzzer instance {{ $labels.instance }} has stopped"

      - alert: CoveragePlateau
        expr: delta(afl_coverage_edges[4h]) == 0
        annotations:
          summary: "No new coverage in 4 hours on {{ $labels.instance }}"

      - alert: NewCrash
        expr: increase(afl_total_crashes[5m]) > 0
        annotations:
          summary: "New crash on {{ $labels.instance }}"

      - alert: CorpusBloat
        expr: rate(afl_corpus_count[1h]) > 1000
        for: 30m
        annotations:
          summary: "Corpus growing rapidly — run cmin on {{ $labels.instance }}"
```

### Dashboard Panels

A useful Grafana dashboard includes:

1. **exec/s over time** — per instance, stacked area chart. Detects stalls.
2. **Coverage growth** — line chart. Should be asymptotic, not flat.
3. **Crash timeline** — event annotations on the coverage chart.
4. **Corpus size** — should stabilize after initial growth.
5. **Cost accumulator** — `sum(instance_count) * hourly_rate * elapsed_hours`.
6. **Instance health** — table showing each VM's status, uptime, last sync.

---

## Operational Playbook

### Campaign Lifecycle

1. **Prepare** — Build instrumented target, create seed corpus, write dictionary.
2. **Estimate** — Calculate cost for desired coverage duration.
3. **Launch** — Deploy spot instances, start fuzzers, enable monitoring.
4. **Monitor** — Watch coverage growth. If plateauing early, adjust (add dictionary,
   enable CMPLOG, switch power schedules).
5. **Triage** — As crashes arrive, minimize and deduplicate. Start root-cause analysis
   on unique crashes without waiting for the campaign to finish.
6. **Scale** — If coverage is still growing at 50% of time budget, consider adding
   instances. If plateaued, consider reducing.
7. **Terminate** — Final corpus sync, tear down instances, archive results.
8. **Report** — Coverage achieved, crashes found, time and cost spent.

### Campaign Termination Criteria

Stop fuzzing when any of:
- Time budget exhausted.
- Coverage has not increased for 12+ hours despite ensemble running.
- All crashes triaged and no new unique crashes for 8+ hours.
- Cost budget reached.

### Post-Campaign

```bash
# Final corpus sync
aws s3 sync /data/afl-out/ s3://fuzzing-archive/campaign-2025-01/

# Generate coverage report
llvm-cov report ./target_cov -instr-profile=merged.profdata

# Archive crash artifacts
tar czf crashes-campaign-2025-01.tar.gz /data/crashes/

# Terminate all instances
aws ec2 cancel-spot-fleet-requests --spot-fleet-request-ids sfr-xxx --terminate-instances
```

---

## See Also

- [ENSEMBLE-FUZZING.md](ENSEMBLE-FUZZING.md) — Multi-engine campaigns on shared corpus
- [CI-FUZZING.md](CI-FUZZING.md) — Integrating fuzzing into CI/CD pipelines
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) — Maximizing exec/s per core
- [CORPUS.md](CORPUS.md) — Corpus construction and maintenance
- [TRIAGE.md](TRIAGE.md) — Crash analysis and deduplication workflows
