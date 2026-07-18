"""The Abridge → Relay bridge.

Abridge captures the encounter (transcript → note → after-visit summary).
Relay reads that documentation and derives the post-encounter OBLIGATIONS —
the things that must be true in Monica's real world for the plan to work —
then, after the walkthrough, scores each obligation against the evidence
(findings, measurements, caregiver answers).
"""

import json
import re

import anthropic

from config import ANTHROPIC_API_KEY, DEEP_MODEL, ROOT
from patient import record
from state import Run

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

CACHE = ROOT / "runs" / "obligations.json"

EXTRACT_PROMPT = """Below is the clinical note and after-visit summary from a skilled \
nursing facility encounter for Monica Hilpert (76F, osteoporosis, deconditioned, uses a \
28in front-wheeled walker, discharging home alone on Friday).

Derive the POST-ENCOUNTER OBLIGATIONS: concrete things that must be true or must happen \
in her real world after discharge for this care plan to succeed. Only include obligations \
grounded in the documentation; quote the supporting text. Focus on ones a home walkthrough \
or caregiver conversation could verify (mobility, equipment, home environment, support, \
pain/activity plan, follow-up).

Return ONLY a JSON array:
[{{"id": "short-slug", "obligation": "<one sentence, imperative>",
   "source_quote": "<verbatim supporting phrase from the note/AVS>",
   "verify_how": "<what evidence the walkthrough can gather>",
   "category": "<mobility|equipment|environment|support|clinical|follow-up>"}}]

NOTE:
{note}

AFTER-VISIT SUMMARY:
{avs}"""

SCORE_PROMPT = """You are scoring whether a discharge care plan is physically possible, \
using evidence from an agent-led home walkthrough.

OBLIGATIONS (from the encounter documentation):
{obligations}

WALKTHROUGH EVIDENCE:
Findings: {findings}
Measurements: {measurements}
Caregiver-confirmed items: {confirmations}
Caregiver statements: {statements}

For EACH obligation, judge its status from evidence only:
- "verified"   — evidence shows it is satisfied
- "at_risk"    — evidence shows a modifiable barrier
- "blocked"    — evidence shows the plan as written cannot work (e.g. equipment
                 physically incompatible with the home)
- "unverified" — walkthrough produced no relevant evidence

Return ONLY a JSON array:
[{{"id": "<obligation id>", "status": "<verified|at_risk|blocked|unverified>",
   "evidence": "<one sentence citing the specific finding/measurement/statement, or
                'not assessed during walkthrough'>"}}]"""


def _parse_json_array(text: str) -> list[dict]:
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.M).strip()
    m = re.search(r"\[.*\]", text, re.S)
    if not m:
        return []
    try:
        return json.loads(m.group())
    except json.JSONDecodeError:
        return []


def _text_of(resp) -> str:
    return "".join(b.text for b in resp.content if b.type == "text")


def extract_obligations(force: bool = False) -> list[dict]:
    """One-time derivation from the encounter documentation; cached on disk."""
    if CACHE.exists() and not force:
        return json.loads(CACHE.read_text())
    rec = record()
    resp = client.messages.create(
        model=DEEP_MODEL, max_tokens=3000,
        messages=[{"role": "user", "content": EXTRACT_PROMPT.format(
            note=rec["note"], avs=rec["after_visit_summary"])}])
    items = _parse_json_array(_text_of(resp))
    if items:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(items, indent=2))
    return items


def score_obligations(run: Run) -> list[dict]:
    """Merge obligations with walkthrough evidence → status per obligation."""
    obligations = extract_obligations()
    if not obligations:
        return []
    with run.lock:
        findings = [
            {"finding": f.get("finding"), "severity": f.get("severity"),
             "room": f.get("room")} for f in run.findings if f.get("hazard")]
        measurements = [m.get("text") for m in run.measurements]
        confirmations = [f"{c['question']} → {c['status']}"
                         for c in run.confirmations if c["status"] != "pending"]
        statements = [t["text"] for t in run.conversation if t["role"] == "caregiver"]

    resp = client.messages.create(
        model=DEEP_MODEL, max_tokens=2500,
        messages=[{"role": "user", "content": SCORE_PROMPT.format(
            obligations=json.dumps(obligations, indent=1),
            findings=json.dumps(findings, indent=1) or "[]",
            measurements=json.dumps(measurements) or "[]",
            confirmations=json.dumps(confirmations) or "[]",
            statements=json.dumps(statements) or "[]")}])
    statuses = {s.get("id"): s for s in _parse_json_array(_text_of(resp))}

    out = []
    for ob in obligations:
        s = statuses.get(ob["id"], {})
        out.append({**ob, "status": s.get("status", "unverified"),
                    "evidence": s.get("evidence", "not assessed during walkthrough")})
    return out
