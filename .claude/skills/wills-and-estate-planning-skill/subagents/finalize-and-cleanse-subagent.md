# Subagent: Finalize and Cleanse

Walks the user through saving, emailing, and then deliberately deleting the intermediate work products and session paper trail that the skill produced.

## Purpose

AI chat transcripts and the skill's intake architecture (intake record, decision ledger, drafts, analyses, letter of wishes) inadvertently build exactly the kind of contemporaneous record a will-contest lawyer would love to see in litigation. Recent case law has held that consumer-grade AI conversations can forfeit attorney-client privilege on the same subject in a later conversation with a real lawyer. For HNW/UHNW testators who anticipate contest, reducing that paper trail on files the user owns, at a time when no litigation is pending, is legitimate and not spoliation.

This subagent is how the skill offers that cleanup safely, with multiple human-in-the-loop gates.

## When to offer

Offer `finalize-and-cleanse` **at the end of any session where a final deliverable has been produced** and the user has confirmed they are done. Do not offer it to users who say they are still iterating. Do not offer it automatically when the user says something ambiguous like "that looks good" — ask explicitly whether they are done producing changes or still in draft.

## When NOT to offer (hard rules)

- **Bedside / deathbed drafting or capacity-fragile scenarios.** These require a human attorney as drafter and witness. Tell the user so and do not offer cleanup.
- **Active or anticipated litigation.** If the user mentions a probate dispute, a contested estate, a pending challenge, or any ongoing legal matter connected to this plan, refuse to offer cleanup and refer them to their attorney. Deleting records during pending litigation is spoliation.
- **User is a professional fiduciary handling someone else's estate.** Cleanup is for the testator's own files. An executor is dealing with records that are not fully theirs.
- **Regulatory / business-records obligation.** If the user is a business owner whose estate documents may be subject to business-records retention (e.g. SEC, FINRA, healthcare records), refer to counsel before cleanup.

## Inputs

- Confirmation that the user is done producing changes
- The project directory path
- What the user considers "the final package" (usually the Attorney Engagement Brief + supporting deliverables, or a directly-executable will if they are skipping the lawyer)
- Evidence the user has saved and emailed the final package

## The flow

### Step 1 — Confirm readiness

Ask, in plain language:

> "Are you fully done producing changes to the estate-planning documents in this folder? Once we run the cleanup, the drafts, analyses, intake record, decision ledger, and session logs will be permanently deleted. Only what you explicitly curate as 'final' stays."

If the user says anything other than an unambiguous yes, stop. Do not offer cleanup.

### Step 2 — Curate the final subset

Ask the user which files in `deliverables/` they consider the final package. Those go into `deliverables/final/` (create it if it doesn't exist). Everything else in `deliverables/` is going to be wiped.

Typical items in `deliverables/final/`:

- `attorney-engagement-brief.md` (if they are handing off to a lawyer)
- The will itself (draft that the attorney will refine, or — if the user is skipping the lawyer — the signed will as PDF)
- Healthcare / financial POA drafts
- Letter of wishes (FINAL version only, not drafts)
- Any document index / inventory the user wants to keep locally

Walk them through copying (not moving, for safety) the relevant files into `deliverables/final/` so the originals still exist during the confirmation step. After they confirm in Step 4, the originals will be wiped but the curated `deliverables/final/` copies will stay.

### Step 3 — Save and email

Explicitly instruct the user:

> "Before we delete anything, I need you to do two things that can't be undone if something goes wrong:
>
> 1. **Save** the full final package to at least one durable location outside this folder: cloud storage (Dropbox, iCloud, Google Drive), an encrypted USB stick, or a backup drive. The files in `deliverables/final/` will remain in this folder, but you should not rely on that as your only copy.
>
> 2. **Email** the full final package (or a link to it) to at least one address that is not on this laptop. Examples: a personal email address at a different provider from the one you use every day; your attorney; your spouse; your named executor. This gives you a second copy that survives if this computer dies."

Wait for the user to confirm they have done both before continuing.

### Step 4 — Manual save-marker file

Ask the user to create `FINAL_PACKAGE_SAVED.txt` in the working folder **by hand**. This is the human-in-the-loop checkpoint; the agent does not create this file. Tell them to include:

- Where they saved it (cloud path, USB stick location, encrypted drive name)
- Who they emailed it to (at least one email address must appear)
- The words SAVED or STORED (describing the save) and EMAILED or SENT (describing the email)

The cleanup script refuses to run without this file, and checks that the words and the '@' sign are present.

Suggested template the user can copy:

```
I SAVED the final estate plan to:
  - Dropbox folder: /Dropbox/Estate/2026-04/
  - USB stick in the home safe

I EMAILED the final estate plan to:
  - myself at my-backup-address@example.com
  - my attorney at janedoe@examplefirm.com
  - my spouse at spouse@example.com

Date: 2026-04-19
```

### Step 5 — Show the plan in plain language, then confirm

Paraphrase to the user, in their own words, what will be deleted and what will be preserved:

- **Deleted**: all drafts, all analyses, the intake record, the decision ledger, any session logs, any `*.tmp` / `SCRATCH_*` / `*.draft.md` files, everything in `deliverables/` except `deliverables/final/`.
- **Preserved**: `FINAL_PACKAGE_SAVED.txt`, `deliverables/final/` (the user's curated package), `user-provided/` (original uploads), anything listed in `intake-inputs.txt`, and everything outside the swept directories.

Then tell the user they will be asked to type the exact string:

    YES I SAVED AND EMAILED THE FINAL PACKAGE

at the terminal prompt to proceed. If they want to abort, they can type anything else or press enter.

### Step 6 — Run the cleanup

Invoke the script:

```
bash scripts/finalize-and-cleanse.sh <project-dir> --confirm-i-saved-the-final-package
```

Do **not** pass `--yes-delete`. The interactive prompt is part of the human-in-the-loop design; bypassing it defeats the purpose. The subagent's job is to prepare the user to answer the prompt, not to answer it for them.

If the user is running the skill in a headless environment without a terminal (uncommon for this skill), inform them that cleanup requires an interactive terminal and stop.

### Step 7 — Report the result

After the script finishes, show the user `CLEANED.md` from the working folder. Summarize:

- How many items were removed
- What is still in the folder (list the preserved top-level entries)
- A reminder that the email copy and cloud/backup copy they made in Step 3 are now the primary record

## Failure modes and recovery

- **User aborts at the prompt.** No files deleted. Offer to revisit in a later session.
- **Script refuses due to missing FINAL_PACKAGE_SAVED.txt content.** Show the specific error; help the user fix the marker file (add the '@', add the word EMAILED, add the word SAVED) and try again.
- **Script refuses due to containment check (shallow path, home directory, root).** The user's project folder is in the wrong place. Help them create a proper subfolder like `~/Documents/my-estate-plan/` and move the files there.
- **User discovers they forgot to save something after cleanup.** This is recoverable only if they followed Step 3 (cloud backup + email). If they did not, tell them plainly that the intermediate files are gone and the email/cloud copy is authoritative.

## Outputs

- A working folder cleansed of the intermediate paper trail
- `CLEANED.md` — a summary of what was removed (permanent record of the cleanup operation itself)
- `FINAL_PACKAGE_SAVED.txt` — the user's own save marker
- `deliverables/final/` (or nothing, if the user wanted nothing preserved locally)

## Related

- Uses: [`scripts/finalize-and-cleanse.sh`](../scripts/finalize-and-cleanse.sh)
- Related methodology: [LITIGATION-DEFENSE](../references/methodology/LITIGATION-DEFENSE.md) — the broader context for contest-resilient drafting, of which this cleanup is one narrow part.
