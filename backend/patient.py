"""Load the demo patient's FHIR record and build the chart context string
that grounds every model call (vision grading, voice brain, report)."""

import json
from functools import lru_cache

from config import DATASET, PATIENT_RECORD_PREFIX


@lru_cache(maxsize=1)
def record() -> dict:
    with open(DATASET) as f:
        for line in f:
            rec = json.loads(line)
            if rec["id"].startswith(PATIENT_RECORD_PREFIX):
                return rec
    raise RuntimeError(f"patient record {PATIENT_RECORD_PREFIX}* not found in dataset")


@lru_cache(maxsize=1)
def chart_context() -> str:
    """Compact clinical grounding: who Monica is and why falls are catastrophic
    for her specifically. Kept short — it rides along on every vision call."""
    rec = record()
    conditions = rec["patient_context"]["longitudinal_summary"].get("condition_labels", [])
    relevant = [c for c in conditions if any(
        k in c.lower() for k in ("osteoporosis", "obesity", "fracture", "gait",
                                 "fall", "pain", "isolat", "weak"))]
    return (
        "PATIENT: Monica Hilpert, 76F, discharging home alone (Somerville MA apartment) "
        "after a ~1-week hospital stay + skilled-nursing rehab for deconditioning and "
        "back pain radiating to both hips.\n"
        f"KEY CONDITIONS: {'; '.join(relevant) if relevant else 'osteoporosis; BMI 30+ obesity'}.\n"
        "MOBILITY: uses a front-wheeled walker (28in wide), fearful of standing, "
        "deconditioned, limited standing tolerance.\n"
        "SOCIAL: lives alone; only nearby support is a neighbor; socially isolated.\n"
        "WHY THIS MATTERS: with osteoporosis, a ground-level fall likely means a "
        "fragility fracture (hip/vertebral) and readmission. Grade hazards for HER: "
        "anything that catches a walker wheel, requires reaching/bending, or offers "
        "no support surface during transfers is higher severity than for a healthy adult."
    )


def patient_display() -> dict:
    rec = record()
    return {
        "name": "Monica Hilpert",
        "age": 76,
        "sex": "F",
        "record_id": rec["id"],
        "visit_title": rec["metadata"]["visit_title"],
    }
