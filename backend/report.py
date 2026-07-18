"""Server-rendered clinician-facing HTML report for one walkthrough run."""

import base64
import html
import json
from pathlib import Path

from fhir_writeback import dme_requests, draft_bundle, routing
from patient import patient_display
from state import Run

SEV_ORDER = {"critical": 0, "moderate": 1, "low": 2, "none": 3}
SEV_COLOR = {"critical": "#c0392b", "moderate": "#d68910", "low": "#2874a6", "none": "#1e8449"}
SEV_LABEL = {"critical": "CRITICAL", "moderate": "MODERATE", "low": "LOW", "none": "CLEAR"}

CSS = """
body{font-family:-apple-system,'Helvetica Neue',sans-serif;margin:0;background:#f4f6f7;color:#1c2833}
.wrap{max-width:900px;margin:0 auto;padding:24px}
header{background:#17202a;color:#fff;padding:20px 24px;border-radius:10px;margin-bottom:20px}
header h1{margin:0 0 4px;font-size:22px} header .sub{color:#aab7b8;font-size:14px}
.banner{display:flex;gap:24px;margin-top:12px;font-size:14px}
.banner div b{display:block;color:#85929e;font-size:11px;text-transform:uppercase}
h2{font-size:16px;text-transform:uppercase;letter-spacing:.06em;color:#566573;
   border-bottom:2px solid #d5dbdb;padding-bottom:6px;margin:28px 0 14px}
.card{background:#fff;border-radius:10px;padding:16px;margin-bottom:12px;
      box-shadow:0 1px 3px rgba(0,0,0,.08);display:flex;gap:16px}
.card img{width:180px;height:135px;object-fit:cover;border-radius:8px;flex-shrink:0}
.sev{display:inline-block;padding:2px 10px;border-radius:12px;color:#fff;
     font-size:11px;font-weight:700;letter-spacing:.05em}
.card h3{margin:6px 0 6px;font-size:15px}
.card p{margin:4px 0;font-size:13.5px;line-height:1.45}
.card .why{color:#7b241c} .card .rec{color:#145a32;font-weight:600}
.meta{color:#808b96;font-size:12px}
.measure{background:#fff;border-radius:10px;padding:14px 16px;margin-bottom:8px;
         box-shadow:0 1px 3px rgba(0,0,0,.08);font-size:14px}
.measure.fail{border-left:5px solid #c0392b}.measure.ok{border-left:5px solid #1e8449}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;
      box-shadow:0 1px 3px rgba(0,0,0,.08)}
td,th{padding:10px 14px;font-size:13.5px;text-align:left;border-bottom:1px solid #eaeded}
th{background:#fbfcfc;color:#566573;font-size:12px;text-transform:uppercase}
.qa{background:#fff;border-radius:10px;padding:4px 16px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.qa p{font-size:13.5px;line-height:1.5}.qa .q{color:#566573}
.draft{border:2px dashed #d68910;border-radius:10px;padding:14px 16px;margin-bottom:10px;
       background:#fef9e7;font-size:13.5px}
.draft b{display:block;margin-bottom:4px}
.footer{color:#808b96;font-size:12px;margin:30px 0;text-align:center}
.pill{background:#eaeded;border-radius:10px;padding:1px 8px;font-size:11px;color:#566573}
.ob{background:#fff;border-radius:10px;padding:12px 16px;margin-bottom:8px;
    box-shadow:0 1px 3px rgba(0,0,0,.08);font-size:13.5px}
.ob .quote{color:#808b96;font-style:italic;font-size:12.5px}
.ob .ev{margin-top:4px}
.esc{background:#fff;border-radius:10px;margin-bottom:12px;overflow:hidden;
     box-shadow:0 1px 3px rgba(0,0,0,.08);font-size:13.5px}
.esc .head{padding:10px 16px;color:#fff;display:flex;justify-content:space-between;
     align-items:center;font-weight:700}
.esc .body{padding:12px 16px}
.esc .body p{margin:4px 0}
.esc .k{color:#566573;font-size:11px;text-transform:uppercase;letter-spacing:.05em;
     display:inline-block;width:86px}
"""

OB_STATUS = {
    "verified":   ("#1e8449", "VERIFIED"),
    "at_risk":    ("#d68910", "AT RISK"),
    "blocked":    ("#c0392b", "BLOCKED"),
    "unverified": ("#808b96", "UNVERIFIED"),
}
ESC_COLOR = {"clinical": "#c0392b", "operational": "#d68910",
             "social": "#7d3c98", "routine": "#2874a6"}


def _img_tag(frame_path: str) -> str:
    p = Path(frame_path)
    if not p.exists():
        return ""
    b64 = base64.standard_b64encode(p.read_bytes()).decode()
    return f'<img src="data:image/jpeg;base64,{b64}" alt="frame">'


def _finding_card(f: dict, run: Run) -> str:
    sev = f.get("severity", "low")
    idx = f.get("frame_index")
    img = ""
    if isinstance(idx, int) and 0 <= idx < len(run.frames):
        img = _img_tag(run.frames[idx]["path"])
    return f"""<div class="card">{img}<div>
      <span class="sev" style="background:{SEV_COLOR.get(sev, '#666')}">{SEV_LABEL.get(sev, sev)}</span>
      <span class="pill">{html.escape(f.get('room', '') or '')}</span>
      <span class="pill">{html.escape(f.get('steadi_item', '') or '')}</span>
      <h3>{html.escape(f.get('finding', ''))}</h3>
      <p class="why">{html.escape(f.get('rationale_for_patient', ''))}</p>
      <p class="rec">→ {html.escape(f.get('recommendation', ''))}</p>
    </div></div>"""


def render_report(run: Run) -> str:
    pt = patient_display()
    findings = sorted(run.findings, key=lambda f: SEV_ORDER.get(f.get("severity"), 9))
    hazards = [f for f in findings if f.get("hazard")]
    n_crit = sum(1 for f in hazards if f.get("severity") == "critical")

    cards = "\n".join(_finding_card(f, run) for f in findings)

    measures = ""
    for m in run.measurements:
        cls = "measure"
        if m.get("kind") in ("door", "opening"):
            cls += " ok" if m.get("walker_clears") else " fail"
        measures += f'<div class="{cls}"><b>{html.escape(m.get("label", ""))}</b>: ' \
                    f'{html.escape(m.get("text", ""))}</div>\n'

    confirms = ""
    for c in getattr(run, "confirmations", []):
        if c["status"] == "pending":
            continue
        mark, color = ("✓", "#1e8449") if c["status"] == "confirmed" else ("✗", "#c0392b")
        confirms += (f'<div class="measure" style="border-left:5px solid {color}">'
                     f'<b style="color:{color}">{mark} caregiver '
                     f'{c["status"]} ({c["resolved_by"]})</b> — '
                     f'{html.escape(c["question"])}</div>\n')

    qa = ""
    for turn in run.conversation:
        who = "Agent" if turn["role"] == "agent" else "Caregiver"
        cls = "q" if turn["role"] == "agent" else ""
        qa += f'<p class="{cls}"><b>{who}:</b> {html.escape(turn["text"])}</p>\n'

    dme = ""
    for sr in dme_requests(hazards):
        code = (sr["code"]["coding"][0]["code"] if sr["code"]["coding"] else "—")
        dme += f"""<div class="draft"><b>DRAFT ORDER — {html.escape(sr['code']['text'])}
        (HCPCS {code}) · priority: {sr['priority']}</b>
        Reason: {html.escape(sr['reasonCode'][0]['text'])}<br>
        {html.escape(sr['note'][0]['text'])}</div>"""

    routes = "".join(
        f"<tr><td><b>{html.escape(r['to'])}</b></td><td>{html.escape(r['why'])}</td>"
        f"<td>{html.escape(r['priority'])}</td></tr>"
        for r in routing(hazards, run.conversation))

    obligations_html = ""
    for ob in getattr(run, "obligations", []):
        color, label = OB_STATUS.get(ob.get("status", "unverified"),
                                     OB_STATUS["unverified"])
        obligations_html += f"""<div class="ob" style="border-left:5px solid {color}">
          <span class="sev" style="background:{color}">{label}</span>
          <b>{html.escape(ob.get('obligation', ''))}</b>
          <div class="quote">note: “{html.escape(ob.get('source_quote', ''))}”</div>
          <div class="ev">→ {html.escape(ob.get('evidence', ''))}</div></div>"""

    esc_html = ""
    for e in getattr(run, "escalations", []):
        color = ESC_COLOR.get(e["level"], "#566573")
        esc_html += f"""<div class="esc">
          <div class="head" style="background:{color}">
            <span>{e['level'].upper()} EXCEPTION → {html.escape(e['owner'])}</span>
            <span style="font-weight:400;font-size:12px">due: {html.escape(e['deadline'])}</span>
          </div>
          <div class="body">
            <p><span class="k">Expected</span> {html.escape(e['expected'])}</p>
            <p><span class="k">Observed</span> {html.escape(e['observed'])}</p>
            <p><span class="k">Why</span> {html.escape(e['why'])}</p>
            <p><span class="k">Attempted</span> {html.escape(e['attempted'])}</p>
            <p><span class="k">Next</span> <b>{html.escape(e['next_action'])}</b></p>
          </div></div>"""

    bundle = draft_bundle(run)
    n_blocked = sum(1 for ob in getattr(run, "obligations", [])
                    if ob.get("status") == "blocked")

    return f"""<!doctype html><html><head><meta charset="utf-8">
<title>Relay — Home-Readiness Report — {pt['name']}</title><style>{CSS}</style></head><body>
<div class="wrap">
<header>
  <h1>Relay · Home-Readiness Report</h1>
  <div class="sub">Care does not end at the encounter — agent-conducted, STEADI-aligned
  · run {run.id}</div>
  <div class="banner">
    <div><b>Patient</b>{pt['name']}, {pt['age']}{pt['sex']}</div>
    <div><b>Context</b>{html.escape(pt['visit_title'])} → home Friday</div>
    <div><b>Findings</b>{len(hazards)} hazards ({n_crit} critical)</div>
    <div><b>Plan status</b>{n_blocked} obligation(s) blocked</div>
    <div><b>Frames analyzed</b>{len(run.frames)}</div>
  </div>
</header>

<h2>1 · Care-plan obligations — derived from the encounter documentation</h2>
<p class="meta">Relay read the SNF note + after-visit summary (Abridge-style artifacts)
and derived what must be true at home for this plan to work, then scored each against
walkthrough evidence.</p>
{obligations_html or '<p class="meta">Obligation scoring runs when the walkthrough finishes.</p>'}

<h2>2 · Escalations — routed to owners with evidence and deadlines</h2>
{esc_html or '<p class="meta">No exceptions raised yet.</p>'}

<h2>3 · Graded findings</h2>
{cards or '<p class="meta">No findings yet — walkthrough in progress.</p>'}

<h2>4 · Measurements (LiDAR)</h2>
{measures or '<p class="meta">No room scans captured.</p>'}

<h2>5 · Patient-reported context (voice walkthrough)</h2>
{confirms}
<div class="qa">{qa or '<p class="meta">No conversation captured.</p>'}</div>

<h2>6 · Drafted actions — not sent, clinician review required</h2>
{dme or '<p class="meta">No DME indicated by findings.</p>'}
<table><tr><th>Route to</th><th>Why</th><th>Priority</th></tr>{routes}</table>

<h2>7 · FHIR write-back (draft)</h2>
<p class="meta">{len(bundle['entry'])} draft resources (Observations, ServiceRequests,
escalation Tasks) — <a href="/report/fhir?run={run.id}">view JSON bundle</a></p>

<div class="footer"><b>Abridge captures the encounter. Relay carries the care forward.</b><br>
detection: Claude vision · grading: CDC STEADI / HSSAT · measurements: LiDAR ·
all orders and escalations are drafts pending clinician review ·
synthetic patient (Synthea) — demo only</div>
</div></body></html>"""
