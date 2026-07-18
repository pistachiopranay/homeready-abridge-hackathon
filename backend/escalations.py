"""Escalation pathways: every unresolved barrier becomes a routed message with an
owner, evidence, and a deadline — the agent's output, not a dashboard.

Levels (deterministic rules, per product spec):
  clinical    — plan physically cannot work as written → pause, send upstream
  operational — fixable before discharge with coordination
  social      — affordability / support gaps → social work
  routine     — worth doing, standard channel
"""

from fhir_writeback import DME_CATALOG
from state import Run

DISCHARGE_DAY = "Friday (discharge)"


def build_escalations(run: Run, scored_obligations: list[dict]) -> list[dict]:
    esc: list[dict] = []
    with run.lock:
        findings = list(run.findings)
        measurements = list(run.measurements)

    # 1. Clinical exception: equipment physically incompatible (the doorway case)
    for m in measurements:
        if m.get("kind") in ("door", "opening") and m.get("walker_clears") is False:
            esc.append({
                "level": "clinical",
                "owner": "OT + discharging MD",
                "deadline": "before " + DISCHARGE_DAY,
                "expected": "Prescribed 28in front-wheeled walker usable throughout the home",
                "observed": f"LiDAR: {m['label']} measured {m['width_in']}in — walker "
                            f"does not fit",
                "why": "Monica cannot reach this room with her prescribed mobility "
                       "device; with osteoporosis, unsupported ambulation risks a "
                       "fragility fracture. The discharge plan as written will not work.",
                "attempted": "Measurement verified during walkthrough; caregiver shown "
                             "the reading on-screen",
                "next_action": "Reassess equipment (narrow-frame walker / hemi-walker), "
                               "home modification, or discharge destination before Friday",
            })

    # 2. Blocked/at-risk obligations not already covered by a clinical exception
    for ob in scored_obligations:
        if ob["status"] == "blocked" and "walker" not in ob["obligation"].lower():
            esc.append({
                "level": "clinical",
                "owner": "Discharging MD",
                "deadline": "before " + DISCHARGE_DAY,
                "expected": ob["obligation"],
                "observed": ob["evidence"],
                "why": "Care-plan obligation cannot be met as documented.",
                "attempted": "Assessed during agent-led walkthrough",
                "next_action": "Revise this element of the plan before discharge",
            })

    # 3. Operational: critical hazards that are fixable pre-discharge
    crit = [f for f in findings
            if f.get("hazard") and f.get("severity") == "critical"]
    if crit:
        rooms = sorted({f.get("room") or "home" for f in crit})
        esc.append({
            "level": "operational",
            "owner": "Discharge coordinator + family",
            "deadline": "before " + DISCHARGE_DAY,
            "expected": "Clear, supported walking path through " + ", ".join(rooms),
            "observed": f"{len(crit)} critical hazards documented with photos "
                        f"({'; '.join((f.get('finding') or '')[:60] for f in crit[:3])}…)",
            "why": "Each is an immediate fall mechanism for a deconditioned walker "
                   "user with osteoporosis.",
            "attempted": "Caregiver was walked through each hazard during the "
                         "session and given fix-in-place recommendations",
            "next_action": "Confirm hazards cleared (photo re-check) before Friday",
        })

    # 4. Social: recommended DME that Original Medicare won't cover
    uncovered = []
    for f in findings:
        rec = (f.get("recommendation") or "").lower()
        for key, (code, display, coverage) in DME_CATALOG.items():
            if key in rec and "not covered" in coverage.lower():
                uncovered.append(display)
    if uncovered:
        esc.append({
            "level": "social",
            "owner": "Social work / care manager",
            "deadline": "within 48h of discharge",
            "expected": "Recommended safety equipment in place and affordable",
            "observed": "Needed items not covered by Original Medicare: "
                        + ", ".join(sorted(set(uncovered))),
            "why": "Monica lives alone on Medicare; uncovered equipment is a real "
                   "affordability barrier, and she has no one to install it.",
            "attempted": "Coverage checked against CMS DME rules; draft orders prepared "
                         "for the covered pathway where one exists",
            "next_action": "Check MA supplemental / community grant programs; arrange "
                           "installation help",
        })

    # 5. Routine: PT/OT follow-through at home
    esc.append({
        "level": "routine",
        "owner": "Home-health PT/OT",
        "deadline": "first home visit",
        "expected": "Home exercise + transfer plan adapted to the actual home",
        "observed": "Full graded walkthrough report with photos and measurements "
                    "attached",
        "why": "Layout-specific transfer training beats generic instructions.",
        "attempted": "—",
        "next_action": "Use report findings to target the first PT/OT home session",
    })

    order = {"clinical": 0, "operational": 1, "social": 2, "routine": 3}
    esc.sort(key=lambda e: order.get(e["level"], 9))
    return esc


def escalation_tasks(escalations: list[dict], patient_ref: dict) -> list[dict]:
    """Escalations as draft FHIR Task resources for write-back."""
    priority = {"clinical": "urgent", "operational": "asap",
                "social": "routine", "routine": "routine"}
    tasks = []
    for i, e in enumerate(escalations):
        tasks.append({
            "resourceType": "Task",
            "id": f"relay-escalation-{i}",
            "status": "requested",
            "intent": "proposal",
            "priority": priority.get(e["level"], "routine"),
            "code": {"text": f"Relay escalation — {e['level']} exception"},
            "description": f"{e['expected']} | OBSERVED: {e['observed']} | "
                           f"NEXT: {e['next_action']}",
            "for": patient_ref,
            "owner": {"display": e["owner"]},
            "restriction": {"period": {"end": e["deadline"]}},
            "note": [{"text": e["why"]}],
        })
    return tasks
