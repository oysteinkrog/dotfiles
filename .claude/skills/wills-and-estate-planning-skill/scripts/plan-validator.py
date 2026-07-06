#!/usr/bin/env python3
"""Validate a wills-and-estate-planning project directory.

Checks for the expected intake, analyses, and deliverables produced by the
skill's documented project-directory workflow.
"""

import sys
from pathlib import Path

MIN_BYTES = 250
STARTER_TEMPLATE_MARKER = "STARTER TEMPLATE NOTE:"
WORK_INPUT_PATTERNS = [
    "current-documents/**/*",
    "financial-documents/**/*",
    "identity-documents/**/*",
    "beneficiary-information/**/*",
    "correspondence/**/*",
    "digital-vault/**/*",
]
BOOTSTRAP_WORKSPACE_FILES = {
    "digital-vault/README-CRITICAL-SECURITY.md",
}
UNSTARTED_INTAKE_MARKERS = [
    "[why now? trigger event? disclaimer presented and acknowledged?]",
    "[map spouse/partner, children, parents, siblings, dependents, fiduciaries, charities]",
    "[reference deliverables/asset-inventory.md and note unknowns]",
    "[reference deliverables/beneficiary-map.md and institution-specific gaps]",
    "[blended family, estrangement, disability, addiction, divorce, litigation, caregiver issues]",
    "[capture the user's reasoning in their own words]",
    "[financial agent, healthcare agent, living-will choices, cognitive decline concerns]",
    "[domicile, out-of-state real estate, foreign assets, state-specific issues]",
    "[tier, overlays, and why]",
]

EXPECTED_FILES = [
    ("intake/intake-record.md", True, "Intake transcript and confirmed facts"),
    ("analyses/plan-coverage-matrix.md", True, "Mode / overlay / output coverage proof"),
    ("analyses/document-quality-triage.md", True, "Document authority and legibility triage"),
    ("analyses/current-document-audit.md", False, "Current document inventory and audit"),
    ("analyses/beneficiary-form-audit.md", False, "Beneficiary designation audit"),
    ("analyses/titling-audit.md", False, "How assets are titled today"),
    ("analyses/coherence-audit.md", True, "Will/trust/title/beneficiary coherence review"),
    ("analyses/tax-exposure-analysis.md", True, "Federal and state estate / inheritance tax analysis"),
    ("analyses/liquidity-analysis.md", True, "Day-270 liquidity and forced-sale risk review"),
    ("analyses/decision-ledger.md", True, "Decision log with rationale and attorney-open items"),
    ("analyses/official-source-log.md", True, "Primary-source verification log"),
    ("analyses/red-flag-triage.md", True, "Critical/high/medium/cleanup issue routing"),
    ("analyses/document-acquisition-plan.md", True, "Missing-document retrieval queue"),
    ("analyses/evidence-confidence-map.md", True, "Evidence-quality map for key facts"),
    ("analyses/recommendation-confidence-register.md", True, "Confidence scoring by recommendation"),
    ("analyses/fiduciary-bench-scorecard.md", True, "Executor / trustee / guardian / agent comparison"),
    ("analyses/litigation-risk-memo.md", True, "Contest / capacity / undue-influence / conflict review"),
    ("analyses/stress-test-scenarios.md", True, "Scenario-based failure-mode review"),
    ("analyses/attorney-handoff-readiness.md", True, "Counsel handoff readiness scoring"),
    ("analyses/foreign-and-conflict-of-laws-review.md", False, "Cross-border and conflict-of-laws review"),
    ("deliverables/asset-inventory.md", True, "Complete asset inventory"),
    ("deliverables/beneficiary-map.md", True, "Current and intended beneficiaries for each asset"),
    ("deliverables/plan-report.md", True, "Comprehensive plan report"),
    ("deliverables/implementation-ledger.md", True, "Trust-funding and institution-update queue"),
    ("deliverables/signing-readiness-checklist.md", True, "Execution logistics and safeguards"),
    ("deliverables/funding-proof-log.md", True, "Evidence that implementation tasks were completed"),
    ("deliverables/institution-contact-matrix.md", True, "Institution-specific change matrix"),
    ("deliverables/beneficiary-change-packet.md", True, "Ordered beneficiary-form cleanup packet"),
    ("deliverables/letter-of-instruction.md", True, "Where things are and who to contact"),
    ("deliverables/digital-inventory.md", True, "Digital accounts and access instructions"),
    ("deliverables/personal-property-memorandum.md", False, "State-specific tangible personal property list"),
    ("deliverables/letter-of-wishes.md", False, "Trustee guidance for discretionary distributions"),
    ("deliverables/ethical-will.md", False, "Values, stories, and messages"),
    ("deliverables/family-meeting-agenda.md", False, "Family communication plan"),
    ("deliverables/conflict-prevention-plan.md", False, "Flashpoints and explanation / governance plan"),
    ("deliverables/if-i-die-tomorrow.md", True, "One-page emergency packet"),
    ("deliverables/disposition-of-remains.md", True, "Funeral and remains authority"),
    ("deliverables/executor-checklist.md", True, "Post-death playbook"),
    ("deliverables/business-continuity-activation.md", False, "Operating-business continuity plan"),
    ("deliverables/attorney-interview-questions.md", True, "Questions for hiring counsel"),
    ("deliverables/attorney-engagement-brief.md", True, "Attorney handoff brief"),
    ("deliverables/document-package-index.md", True, "Index of supporting source documents"),
    ("deliverables/review-schedule.md", True, "Plan update cadence and triggers"),
]

STARTER_TEMPLATE_ENFORCED_FILES = {
    rel_path for rel_path, required, _description in EXPECTED_FILES if required
}

OPTIONAL_TRIGGER_RULES = {
    "analyses/current-document-audit.md": {
        "patterns": [
            "current-documents/**/*",
        ],
        "escalate_to_issue": True,
    },
    "analyses/beneficiary-form-audit.md": {
        "patterns": [
            "current-documents/beneficiary-forms/**/*",
        ],
        "escalate_to_issue": True,
    },
    "analyses/titling-audit.md": {
        "patterns": [
            "financial-documents/deeds/**/*",
            "financial-documents/mortgage-documents/**/*",
        ],
        "escalate_to_issue": True,
    },
}


def is_starter_template_text(text: str) -> bool:
    return STARTER_TEMPLATE_MARKER.lower() in text.lower()


def classify_file(
    project_dir: Path,
    rel_path: str,
    required: bool,
    description: str,
    fresh_scaffold: bool = False,
    enforce_starter_marker: bool = False,
):
    path = project_dir / rel_path
    if not path.exists():
        level = "issue" if required else "warning"
        return level, f"MISSING ({'required' if required else 'optional'}): {rel_path} — {description}"

    size = path.stat().st_size
    if size < MIN_BYTES:
        level = "issue" if required else "warning"
        return level, f"TRIVIAL ({'required' if required else 'optional'}, {size} bytes): {rel_path} — needs content"

    text = read_text(project_dir, rel_path)
    enforce_marker_for_file = rel_path in STARTER_TEMPLATE_ENFORCED_FILES or enforce_starter_marker
    if text and is_starter_template_text(text) and enforce_marker_for_file:
        level = "issue" if required else "warning"
        message = (
            f"STARTER TEMPLATE ({'required' if required else 'optional'}): {rel_path} — "
            "still contains the starter-template note; replace placeholders/sample rows with client-specific content and delete the note"
        )
        if fresh_scaffold:
            return "deferred", message
        return level, message

    return None, None


def read_text(project_dir: Path, rel_path: str) -> str:
    path = project_dir / rel_path
    if not path.exists():
        return ""
    return path.read_text(errors="ignore")


def any_matching_files(project_dir: Path, patterns) -> bool:
    for pattern in patterns:
        if any(path.is_file() for path in project_dir.glob(pattern)):
            return True
    return False


def any_meaningful_input_files(project_dir: Path) -> bool:
    for pattern in WORK_INPUT_PATTERNS:
        for path in project_dir.glob(pattern):
            if not path.is_file():
                continue
            rel_path = path.relative_to(project_dir).as_posix()
            if rel_path in BOOTSTRAP_WORKSPACE_FILES:
                continue
            return True
    return False


def intake_is_unstarted(project_dir: Path) -> bool:
    text = read_text(project_dir, "intake/intake-record.md")
    if not text:
        return True
    lowered = text.lower()
    hits = sum(1 for marker in UNSTARTED_INTAKE_MARKERS if marker in lowered)
    return hits >= 3


def is_fresh_scaffold(project_dir: Path) -> bool:
    return intake_is_unstarted(project_dir) and not any_meaningful_input_files(project_dir)


def check_contains(project_dir: Path, rel_path: str, patterns, description: str, required: bool = True):
    path = project_dir / rel_path
    if not path.exists() or path.stat().st_size < MIN_BYTES:
        return None, None
    text = read_text(project_dir, rel_path)
    if not text or is_starter_template_text(text):
        return None, None
    lowered = text.lower()
    missing = [p for p in patterns if p.lower() not in lowered]
    if not missing:
        return None, None
    level = "issue" if required else "warning"
    return level, f"CONTENT GAP ({rel_path}): missing {description}: {', '.join(missing)}"


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <project-dir>")
        sys.exit(1)

    project_dir = Path(sys.argv[1])
    if not project_dir.is_dir():
        print(f"Error: {project_dir} is not a directory")
        sys.exit(1)

    issues = []
    warnings = []
    fresh_scaffold = is_fresh_scaffold(project_dir)
    suppressed_starter_templates = []

    for rel_path, required, description in EXPECTED_FILES:
        level, message = classify_file(project_dir, rel_path, required, description, fresh_scaffold=fresh_scaffold)
        if level == "deferred":
            suppressed_starter_templates.append(message)
            continue
        if not required and level == "warning":
            trigger_rule = OPTIONAL_TRIGGER_RULES.get(rel_path)
            if trigger_rule:
                if not any_matching_files(project_dir, trigger_rule["patterns"]):
                    continue
                if trigger_rule.get("escalate_to_issue"):
                    issues.append(message.replace("(optional", "(required by detected inputs"))
                    continue
        if level == "issue":
            issues.append(message)
        elif level == "warning":
            warnings.append(message)

    if suppressed_starter_templates:
        issues.append(
            "FRESH SCAFFOLD: intake and evidence folders still look largely unstarted, so "
            f"{len(suppressed_starter_templates)} untouched starter templates were detected but suppressed for brevity. "
            "Once real intake/work product begins, remove starter-template notes from completed files and rerun validation."
        )

    content_checks = [
        ("analyses/plan-coverage-matrix.md", ["primary mode", "coverage table"], "mode / coverage scaffolding", True),
        ("analyses/recommendation-confidence-register.md", ["overall", "what would increase confidence"], "confidence-register structure", True),
        ("analyses/fiduciary-bench-scorecard.md", ["recommended primaries", "recommended backups"], "fiduciary decision sections", True),
        ("analyses/litigation-risk-memo.md", ["capacity", "undue influence", "execution", "fiduciary conflict"], "litigation-defense sections", True),
        ("analyses/attorney-handoff-readiness.md", ["total score", "biggest blockers"], "handoff-readiness sections", True),
        ("deliverables/signing-readiness-checklist.md", ["pre-signing", "ceremony", "immediately after signing"], "signing-readiness sections", True),
        ("deliverables/institution-contact-matrix.md", ["institution", "current control", "intended control"], "institution-matrix headings", True),
        ("deliverables/beneficiary-change-packet.md", ["accounts / policies to update", "priority order"], "beneficiary-change packet sections", True),
        ("deliverables/funding-proof-log.md", ["asset / account", "date submitted", "date completed"], "funding-proof log headings", True),
    ]

    for rel_path, patterns, description, required in content_checks:
        level, message = check_contains(project_dir, rel_path, patterns, description, required)
        if level == "issue":
            issues.append(message)
        elif level == "warning":
            warnings.append(message)

    asset_text = read_text(project_dir, "deliverables/asset-inventory.md")
    plan_text = read_text(project_dir, "deliverables/plan-report.md")
    asset_ready = bool(asset_text) and not is_starter_template_text(asset_text)
    plan_ready = bool(plan_text) and not is_starter_template_text(plan_text)
    asset_lower = asset_text.lower()
    plan_lower = plan_text.lower()
    business_markers = ["llc", "s-corp", "business", "practice", "company", "payroll"]
    if (asset_ready or plan_ready) and any(marker in asset_lower or marker in plan_lower for marker in business_markers):
        level, message = classify_file(
            project_dir,
            "deliverables/business-continuity-activation.md",
            False,
            "Business continuity plan for operating enterprise",
            fresh_scaffold=fresh_scaffold,
            enforce_starter_marker=True,
        )
        if level == "warning":
            warnings.append("BUSINESS CONTINUITY: business signals present but business-continuity-activation.md is missing or trivial")

    cross_border_markers = ["foreign", "non-citizen", "non citizen", "abroad", "expatriate", "france", "italy"]
    if (asset_ready or plan_ready) and any(marker in asset_lower or marker in plan_lower for marker in cross_border_markers):
        level, message = classify_file(
            project_dir,
            "analyses/foreign-and-conflict-of-laws-review.md",
            False,
            "Cross-border and conflict-of-laws review",
            fresh_scaffold=fresh_scaffold,
            enforce_starter_marker=True,
        )
        if level == "warning":
            warnings.append("CROSS-BORDER: foreign / non-citizen / expatriate signals present but foreign-and-conflict-of-laws-review.md is missing or trivial")

    print("=" * 78)
    print(f"Plan Validation: {project_dir}")
    print("=" * 78)
    print()

    if issues:
        print("❌ ISSUES (must resolve):")
        for issue in issues:
            print(f"  - {issue}")
        print()

    if warnings:
        print("⚠️  WARNINGS (recommended follow-up):")
        for warning in warnings:
            print(f"  - {warning}")
        print()

    if not issues and not warnings:
        print("✓ All expected intake, analyses, and deliverables are present, materially customized, and non-trivial.")
        print()

    print("Reminder: structural completeness is not legal sufficiency.")
    print("Always confirm current law from primary sources and route final drafting through licensed counsel.")
    print()

    sys.exit(1 if issues else 0)


if __name__ == "__main__":
    main()
