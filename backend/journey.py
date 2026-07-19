"""The demo journey around the walkthrough: clinician handoff → patient message
→ (walkthrough) → approval queue → remediation → cleared for discharge."""

import json
import uuid

from config import RUNS_DIR
from patient import record
from state import Run, load_run

HANDOFF_MESSAGE = (
    "Hi Monica — this is Riley with your care team at the rehab facility. "
    "Before you come home Friday, your care team would like a quick walk-through "
    "of your apartment to make sure everything is ready for you. Anyone at your "
    "home can do it with any compatible device — it takes about ten minutes and "
    "I'll guide them the whole way. Or, if you prefer, we can schedule an "
    "in-person home visit from a partner service."
)

# The documented plan, as it appears in the encounter note (rendered in the
# clinician portal above the handoff button)
PLAN_ITEMS = [
    "PT for safe transfers, standing tolerance, gait, and strengthening",
    "OT for dressing, bathing safety, and daily activities",
    "Pain management with monitoring for sedation, confusion, and unsteadiness",
    "Dietitian support for soft, protein- and calcium-forward meals",
    "Social work to arrange home support before discharge",
    "Formal pre-discharge assessment: mobility, medication management, "
    "meal management, home setup",
    "Discharge home once safe",
]


# The pre-processed sample: a completed walkthrough with pending approvals so
# the full care-team flow can be demoed instantly, no live wait
SAMPLE_RUN_ID = "113216-766172"
SAMPLE_PATIENT_PREFIX = "1be66dc9"   # Latoyia Wilkinson, 82F — SNF after hosp.


def _record_for(prefix: str) -> dict:
    from config import DATASET
    with open(DATASET) as f:
        for line in f:
            rec = json.loads(line)
            if rec["id"].startswith(prefix):
                return rec
    raise KeyError(prefix)


def _relay_status(run: Run | None) -> dict | None:
    if run is None:
        return None
    hazards = [f for f in run.findings if f.get("hazard")]
    return {
        "run_id": run.id,
        "discharge_state": run.discharge_state,
        "n_findings": len(hazards),
        "n_critical": sum(1 for f in hazards
                          if f.get("severity") == "critical"),
        "n_blocked": sum(1 for o in run.obligations
                         if o.get("status") == "blocked"),
        "has_floorplan": bool(run.floorplans),
    }


def patients() -> list[dict]:
    return [
        {"id": "monica", "name": "Hilpert, Monica",
         "detail": "76F · SNF rehab · DC Friday", "live": True},
        {"id": "sample", "name": "Wilkinson, Latoyia",
         "detail": "82F · SNF after hospitalization · processed",
         "live": False},
        {"id": "other", "name": "Okafor, James",
         "detail": "61M · post-op wound check", "live": False,
         "disabled": True},
    ]


def patient_chart(which: str = "monica") -> dict:
    if which == "sample":
        rec = _record_for(SAMPLE_PATIENT_PREFIX)
        nm = rec["patient_context"]["patient"]["name"][0]
        chart = {
            "name": f"{nm['given'][0]} {nm['family']}",
            "age": 82, "sex": "F",
            "visit_title": rec["metadata"]["visit_title"],
            "note": rec["note"],
            "plan_items": [],
            "handoff_message": "",
            "sample": True,
            "relay_status": _relay_status(load_run(SAMPLE_RUN_ID)),
        }
        return chart

    rec = record()
    chart = {
        "name": "Monica Hilpert",
        "age": 76,
        "sex": "F",
        "visit_title": rec["metadata"]["visit_title"],
        "note": rec["note"],
        "after_visit_summary": rec["after_visit_summary"],
        "plan_items": PLAN_ITEMS,
        "handoff_message": HANDOFF_MESSAGE,
    }
    # Monica's card reflects HER latest walkthrough. While a live run hasn't
    # saved yet, surface a processing state instead of stale sample data.
    import state as state_mod
    live = state_mod.current()
    finished_ids = {d.name for d in RUNS_DIR.iterdir() if (d / "run.json").exists()}
    if live.frames and live.id not in finished_ids:
        chart["relay_status"] = {"processing": True, "run_id": live.id,
                                 "n_findings": len(live.findings)}
    else:
        candidates = sorted(
            fid for fid in finished_ids
            if fid != SAMPLE_RUN_ID and fid > state_mod.chart_cutoff)
        if candidates:
            chart["relay_status"] = _relay_status(load_run(candidates[-1]))
    return chart


def latest_finished_run() -> Run | None:
    for d in sorted(RUNS_DIR.iterdir(), reverse=True):
        if (d / "run.json").exists():
            run = load_run(d.name)
            if run is not None:
                return run
    return None


def build_approvals(run: Run) -> list[dict]:
    """Clinician approval queue from the run's drafted actions + escalations."""
    from fhir_writeback import dme_requests

    approvals = []
    with run.lock:
        hazards = [f for f in run.findings if f.get("hazard")]
        escalations = list(run.escalations)

    for e in escalations:
        if e["level"] in ("clinical", "operational"):
            approvals.append({
                "id": uuid.uuid4().hex[:8], "kind": e["level"],
                "title": e["next_action"],
                "detail": f"{e['observed']} → route to {e['owner']}, "
                          f"due {e['deadline']}",
                "status": "pending",
            })
    for sr in dme_requests(hazards):
        code = sr["code"]["coding"][0]["code"] if sr["code"]["coding"] else "—"
        approvals.append({
            "id": uuid.uuid4().hex[:8], "kind": "dme",
            "title": f"Order: {sr['code']['text']} (HCPCS {code})",
            "detail": f"Reason: {sr['reasonCode'][0]['text']}. "
                      f"{sr['note'][0]['text']}",
            "status": "pending",
        })
    return approvals


def approve(run: Run, approval_id: str) -> dict | None:
    with run.lock:
        hit = None
        for a in run.approvals:
            if a["id"] == approval_id and a["status"] == "pending":
                a["status"] = "approved"
                hit = dict(a)
        if hit and all(a["status"] == "approved" for a in run.approvals):
            run.discharge_state = "approved"
    if hit:
        run.save()
    return hit


def clear_for_discharge(run: Run) -> dict:
    """Remediations confirmed → chart updates → cleared."""
    with run.lock:
        run.discharge_state = "cleared"
    run.save()
    return {"discharge_state": "cleared"}
