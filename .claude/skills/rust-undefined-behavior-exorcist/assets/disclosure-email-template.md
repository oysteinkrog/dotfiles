# Disclosure Email Template (Private to Maintainer)

Use this template for the FIRST contact with a crate maintainer about a confirmed
UB finding. Keep it short, specific, and respectful — you are asking for their
time on a security matter.

The template fields are placeholders; **fill them in manually** from your
`UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` block and your reachability analysis.
Do not auto-generate this email; the tone has to be human.

---

```
To: <security@crate-owner.example> OR <maintainer-from-Cargo.toml>
Cc: (leave empty for first contact)
Subject: [security/private] UB in {CRATE_NAME} {VERSION_RANGE} via {ENTRY_POINT}

Hi {MAINTAINER_FIRST_NAME},

I'm writing privately to report what I believe is undefined behavior in
{CRATE_NAME} (versions {VERSION_RANGE_AFFECTED}, current main as of {COMMIT_SHA}).
This message is private; I have not filed a public advisory yet and will not
do so until you've had a chance to look or until {DISCLOSURE_DEADLINE_DATE}
(90 days from today by default).

Summary
-------
{ONE_SENTENCE: what UB shape, which API surface, what the consequence is.}

Example: "Calling {API}() with a slice longer than `isize::MAX / 4` triggers
out-of-bounds in {INTERNAL_FUNCTION} because the length is computed with
wrapping arithmetic and used as a raw-pointer offset."

Severity (my estimate, please correct)
--------------------------------------
- CVSS v3.1: {SCORE} ({VECTOR})
- Reachability: triggerable from {SAFE_PUBLIC_API | UNSAFE_PUBLIC_API | FEATURE_FLAG_<NAME>}
- Exploitability in practice: {LOW | MEDIUM | HIGH} — {ONE_SENTENCE_RATIONALE}

Reproducer
----------
A self-contained Miri-clean reproducer is attached as `repro.tar.gz`. It
contains a single-file crate (`Cargo.toml` + `src/main.rs`) that builds and
demonstrates the issue under:

  cargo +nightly miri run

Expected output (clean run): {EXPECTED_LINE}
Actual output:               {ACTUAL_LINE_OR_MIRI_ABORT}

The Miri stderr is in `miri_output.txt` inside the tarball.

Suggested remediation
---------------------
{ONE_SENTENCE: smallest behaviorally-equivalent fix.}

I've sketched two alternatives in `remediation_options.md` (scored 0–4 on
correctness margin, perf delta, blast radius, reviewability, maintainability).
Happy to send a PR against {BRANCH} if useful, or to wait for you to drive
the fix — whichever fits your maintenance flow.

Next steps + disclosure timeline
--------------------------------
- Today ({YYYY-MM-DD}): private notification to you.
- +7 days: I'd appreciate an acknowledgment that you've received this and
  whether you intend to fix it / whether the timeline below works.
- +30 days: target for a fix to land in a published release.
- +90 days ({DISCLOSURE_DEADLINE_DATE}): I plan to file a RustSec advisory.
  If you need more time, just say so — I'm flexible if there's a credible plan.

Contact
-------
{YOUR_NAME}
{YOUR_EMAIL}
{YOUR_GPG_KEY_ID or "no GPG key — email is fine"}

Thanks for maintaining {CRATE_NAME}; this report is meant as help, not as a
public-shaming exercise.

— {YOUR_NAME}
```

---

## Notes on style

- **Lead with the summary.** Maintainers triage many inbound mails; the first
  paragraph has to telegraph "this is real and specific" or it gets deprioritized.
- **Estimate severity, don't insist on it.** Your CVSS is a starting point; the
  maintainer often knows the deployment surface better.
- **Offer a fix, but don't require it.** Some maintainers prefer to drive the
  remediation themselves; some prefer a PR. Defer to them.
- **Set a disclosure deadline.** 90 days is the well-known industry standard
  (Google Project Zero default). Extend if asked, but write the date down so
  the timeline is clear from message #1.
- **Never include the reproducer body inline.** Attach as a tarball so it
  doesn't get word-wrapped or quote-mangled in mail clients.
- **Send from a personal email address** (you, the human doing the audit) — not
  from a bot, shared role account, or anything that looks automated. This is
  a human-to-human conversation about a security finding; tone matters.

## Related templates

- `scripts/disclosure-template-author.sh` — generates a draft `RUSTSEC-YYYY-XXXX.md`
  advisory from a CONFIRMED_UB EXP-NNN block. Use that for the *public* advisory
  draft; use THIS template for the initial private email.
- [references/DISCLOSURE.md](../references/DISCLOSURE.md) — full coordinated-disclosure
  playbook (timeline, embargo handling, advisory drafting).
