# Execution Formalities and State-Specific Signing Risk

Execution defects can invalidate good planning. This directory exists to prevent the
agent from treating signing mechanics as a footnote.

Use this directory when the plan depends on:

- state witness rules
- self-proving affidavit practice
- holographic-will treatment
- electronic-will / remote-notarization questions
- transfer-on-death deed or Lady Bird deed availability
- POA or healthcare-directive formality questions

---

## Operating Model

1. Identify the user's domicile state.
2. Identify every state where the user owns real estate.
3. For each state that matters, verify the current rule from a primary source.
4. Log the source in `analyses/official-source-log.md`.
5. Route any uncertain execution question to a state-licensed attorney in the handoff packet.

This directory is a **router**, not a substitute for counsel. The point is to force the
agent to load the right state-sensitive questions before it says a document is "ready."

---

## What To Verify Every Time

- number and qualification of witnesses for wills
- whether witness presence must be simultaneous
- self-proving affidavit availability and practice
- whether holographic wills are recognized, and on what terms
- whether electronic wills or remote execution are authorized
- whether a financial POA requires notary, witnesses, or both
- what form / witnessing rules apply to healthcare directives
- whether transfer-on-death deeds are available for local real estate
- whether Lady Bird deeds exist in that jurisdiction

---

## Verified High-Priority State Starting Points

These are official-source starting points for the states most likely to matter in this
skill. Always re-check live before finalizing a recommendation.

For a compact matrix view, load
[HIGH-PRIORITY-STATE-VERIFICATION-MATRIX.md](HIGH-PRIORITY-STATE-VERIFICATION-MATRIX.md).

| State | Official source starting point | Notes to verify |
|-------|-------------------------------|-----------------|
| California | Probate Code §§ 6110, 6111, 4121, 4701, 5600-5698 via `leginfo.legislature.ca.gov`; Secretary of State advance-directive registry | 2-witness attested will, same-time witness rule, harmless-error cure, holographic will treatment, POA notary-or-2-witness rule, AHCD formality, revocable TOD deed regime |
| Florida | Fla. Stat. §§ 732.502, 732.503 via `flsenate.gov`; Florida electronic-wills statutes if implicated | 2-witness will execution, witnesses sign in presence of testator and each other, self-proving affidavit, current online-notarization language, e-will issues if relevant, enhanced-life-estate practice |
| Massachusetts | M.G.L. ch. 190B §§ 2-502, 2-504 via `malegislature.gov` | 2-witness will execution, self-proving mechanism, whether any harmless-error argument is even available in the actual fact pattern |
| New York | EPTL 3-2.1 and EPTL Article 3 Part 6 via `nysenate.gov`; related SCPA proof / self-proving provisions if probate mechanics matter | 2 attesting witnesses, New York-specific ceremony and acknowledgment rules, self-proving affidavit practice, current paper-will baseline, electronic-will act enacted but not effective until Dec. 12, 2027 |
| Texas | Estates Code ch. 251 via `statutes.capitol.texas.gov` | attested vs holographic wills, self-proving affidavit, age / witness rules, enhanced-life-estate / transfer-on-death interactions, POA formality |
| Washington | RCW ch. 11.12 via `app.leg.wa.gov`; related RCW on POA and health directives as needed | paper wills, electronic wills available under current law, self-proving for e-wills, qualified-custodian duties, community-property interaction |
| Oregon | ORS chapter 112 via `oregonlegislature.gov` | attested will formalities, harmless-error treatment, deed-transfer options, advance-directive and notarial mechanics |
| Illinois | Probate Act of 1975 and Illinois Electronic Wills and Remote Witnesses Act via `ilga.gov` | 2-credible-witness rule, electronic / remote witness act, self-proving / probate-proof rules |

---

## Practical Attorney-Handoff Questions

For any state-sensitive execution issue, put explicit questions in
`deliverables/attorney-engagement-brief.md`, such as:

- "Will this state accept the prior state's execution formalities for the existing will?"
- "Should we use a self-proving affidavit here, and in what form?"
- "Is a paper will preferable to an electronic will in this fact pattern?"
- "Should this parcel be transferred by trust deed, TOD deed, or left in probate?"
- "Does this POA satisfy local bank practice, not just bare statutory sufficiency?"

---

## Anti-Pattern

Do not tell the user to sign "with two witnesses and a notary" as generic national advice.

That is sometimes right, sometimes incomplete, and sometimes wrong.
