"""Draft (never auto-sent) FHIR R4 resources from walkthrough findings:
Observations for hazards, ServiceRequests for DME + referrals."""

import uuid

from patient import record
from state import Run

# DME recommendation → (HCPCS code, display, Medicare note)
DME_CATALOG = {
    "grab bar": ("E0241", "Bathtub wall rail / grab bar",
                 "Not covered by Original Medicare (comfort/convenience); often covered "
                 "by Medicare Advantage supplemental or state waiver — flag for social work."),
    "shower chair": ("E0240", "Bath/shower chair",
                     "Not covered by Original Medicare; low-cost self-pay, MA plans often cover."),
    "raised toilet seat": ("E0244", "Raised toilet seat",
                           "Not covered by Original Medicare; MA supplemental often covers."),
    # NB: keys are matched as substrings of the recommendation text. Monica already
    # owns a walker, and nearly every rec mentions it — so "walker" alone must NOT
    # be a trigger; only an explicit replacement recommendation is.
    "replacement walker": ("E0143", "Folding wheeled walker",
                           "Covered by Medicare Part B as DME with physician order."),
    "commode": ("E0163", "Bedside commode",
                "Covered by Medicare Part B when patient is room-confined."),
    "night light": (None, "Night lights / motion-sensor lighting",
                    "Not DME — home modification; flag for OT/social work resources."),
}


def _patient_ref() -> dict:
    return {"reference": f"Patient/{record()['patient_context']['patient']['id']}",
            "display": "Monica Hilpert"}


def hazard_observation(finding: dict) -> dict:
    sev = finding.get("severity", "low")
    return {
        "resourceType": "Observation",
        "id": str(uuid.uuid4()),
        "status": "preliminary",
        "category": [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/observation-category",
            "code": "survey", "display": "Survey"}]}],
        "code": {"coding": [{"system": "http://loinc.org", "code": "93025-5",
                             "display": "Home environment hazard assessment"}],
                 "text": f"Home fall hazard — {finding.get('category', 'general')}"},
        "subject": _patient_ref(),
        "valueString": finding.get("finding", ""),
        "interpretation": [{"text": f"severity: {sev}"}],
        "note": [{"text": f"{finding.get('rationale_for_patient', '')} "
                          f"Recommendation: {finding.get('recommendation', '')} "
                          f"(STEADI/HSSAT: {finding.get('steadi_item', 'n/a')})"}],
    }


def dme_requests(findings: list[dict]) -> list[dict]:
    """One draft ServiceRequest per distinct DME item mentioned in recommendations."""
    seen: dict[str, dict] = {}
    for f in findings:
        rec_text = (f.get("recommendation") or "").lower()
        for key, (code, display, coverage) in DME_CATALOG.items():
            if key in rec_text and key not in seen:
                seen[key] = {
                    "resourceType": "ServiceRequest",
                    "id": str(uuid.uuid4()),
                    "status": "draft",
                    "intent": "proposal",
                    "priority": "urgent" if f.get("severity") == "critical" else "routine",
                    "code": {"coding": ([{"system":
                                          "https://www.cms.gov/medicare-coverage-database",
                                          "code": code, "display": display}] if code else []),
                             "text": display},
                    "subject": _patient_ref(),
                    "reasonCode": [{"text": f.get("finding", "")}],
                    "note": [{"text": f"Coverage: {coverage}"}],
                }
    return list(seen.values())


def routing(findings: list[dict], conversation: list[dict]) -> list[dict]:
    """Who on the care team should act. Simple deterministic triage."""
    out = []
    crit = [f for f in findings if f.get("severity") == "critical"]
    if crit:
        out.append({"to": "MD / discharging provider",
                    "why": f"{len(crit)} critical hazard(s) before Friday discharge",
                    "priority": "before discharge"})
    if any("bathroom" in (f.get("room") or "") for f in crit):
        out.append({"to": "Home-health PT/OT",
                    "why": "Bathroom transfer safety evaluation + equipment fitting",
                    "priority": "within 48h of discharge"})
    out.append({"to": "Social work",
                "why": "Lives alone, isolated; DME coverage gaps need community resources",
                "priority": "routine"})
    return out


def draft_bundle(run: Run) -> dict:
    from escalations import escalation_tasks
    hazards = [f for f in run.findings if f.get("hazard")]
    entries = (
        [hazard_observation(f) for f in hazards]
        + dme_requests(hazards)
        + escalation_tasks(getattr(run, "escalations", []), _patient_ref())
    )
    if getattr(run, "discharge_state", "") == "cleared":
        entries.append({
            "resourceType": "Observation",
            "id": str(uuid.uuid4()),
            "status": "final",
            "code": {"text": "Home-readiness verification complete"},
            "subject": _patient_ref(),
            "valueString": "Identified barriers remediated and verified; "
                           "cleared for discharge per care-team approval.",
        })
    return {
        "resourceType": "Bundle",
        "type": "collection",
        "meta": {"tag": [{"code": "DRAFT", "display":
                          "Drafted by walkthrough agent — requires clinician review"}]},
        "entry": [{"resource": r} for r in entries],
    }
