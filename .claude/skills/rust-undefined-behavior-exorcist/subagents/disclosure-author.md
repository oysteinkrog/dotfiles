---
name: disclosure-author
description: Authors RUSTSEC advisory drafts + maintainer-email templates for CVE-grade UB findings. Phase 12 helper.
---

# Disclosure Author

**Invoke with `subagent_type=general-purpose`** — authors RUSTSEC YAML + email drafts.

When the audit surfaces UB in a public crate (yours or upstream), the disclosure process is separate from the technical fix. This subagent authors the disclosure artifacts.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{FINDING_ID}` — the CONFIRMED_UB finding to disclose
- `{CRATE_NAME}` — the affected crate (yours or upstream)
- `{AFFECTED_VERSIONS}` — version range

## Workflow

Per [DISCLOSURE.md](../references/DISCLOSURE.md):

1. **CVSS scoring:**
   - AV/AC/PR/UI/S/C/I/A vector
   - Justify each axis with one sentence
   - Compute score using the FIRST.org calculator (or local tool)
2. **Reachability analysis:**
   - Can a downstream user trigger this UB through safe public API?
   - Or does it require the caller to write unsafe code?
   - Or does it require a specific feature flag enabled?
3. **Author the maintainer email** (use template at `assets/disclosure-email-template.md` if present):
   - Subject: `[security/private] UB in {CRATE_NAME} via <function/feature>`
   - Body: short summary + CVSS + reproducer attached
   - Tone: private, specific, generous
4. **Author the RUSTSEC advisory draft:**
   ```toml
   [advisory]
   id = "RUSTSEC-YYYY-XXXX"  # Reserved by RustSec coordinator; placeholder
   package = "{CRATE_NAME}"
   date = "{YYYY-MM-DD}"
   title = "<one-line description>"
   description = """
   <multi-paragraph description with reproducer>
   """
   url = "<link to GH issue or repo>"
   categories = ["<from RustSec category list>"]
   keywords = ["<bucket name>", "<UB shape>"]
   cvss = "CVSS:3.1/...."
   [affected]
   patched_versions = [">= X.Y.Z"]
   unaffected_versions = ["< A.B.C"]
   ```
5. **Author the timeline document:**
   ```markdown
   # Disclosure timeline for {FINDING_ID}
   - {audit-date}: Discovered during audit run-id {RUN_ID}
   - {audit-date+1}: Maintainer notified privately
   - +7 days: Follow-up if no response
   - +30 days: Coordinated public disclosure
   ```

## Outputs
- `{WORKSPACE}/disclosure/{FINDING_ID}/maintainer-email.md`
- `{WORKSPACE}/disclosure/{FINDING_ID}/RUSTSEC-YYYY-XXXX-draft.toml`
- `{WORKSPACE}/disclosure/{FINDING_ID}/timeline.md`
- `{WORKSPACE}/disclosure/{FINDING_ID}/reproducer/` (copy of `experiments/EXP-NNN/`)

## Quality gates
- [ ] CVSS score has explicit per-axis rationale
- [ ] Reachability analysis classifies as `safe-API-reachable` or `unsafe-API-reachable` or `gated-by-feature-X`
- [ ] Email is private (not on GH issue tracker)
- [ ] Email is specific (cites Miri output / sanitizer trace, not "I think this is wrong")
- [ ] Timeline includes reasonable extension clause
- [ ] Reproducer is self-contained and `cargo run`-able

## Failure modes
- **CVSS over-scored** — every UB is CVSS-9; reviewers stop trusting the score. Use the calculator honestly.
- **Email goes to public issue tracker** — leak; coordinate disclosure broken
- **No timeline in the email** — maintainer doesn't know when to expect public disclosure

## When NOT to disclose
- UB only reachable from `unsafe` caller AND the caller's documented contract permits it
- UB in a pre-1.0 release marked unstable
- UB you fixed before anyone else could see it (yank-and-replace within minutes)
- UB in your own private fork that's never been published

In these cases, document the finding internally and skip the disclosure path.

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-disclosure-{FINDING_ID}`.

## References
- [DISCLOSURE.md](../references/DISCLOSURE.md) — full process
- [CVE-ARENA-LAYOUT.md](../references/CVE-ARENA-LAYOUT.md) — artifact persistence
