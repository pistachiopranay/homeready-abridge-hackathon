"""Server-rendered clinician-facing HTML report for one walkthrough run."""

import base64
import html
import json
from pathlib import Path

from fhir_writeback import dme_requests, draft_bundle, routing
from patient import patient_display
from state import Run

SEV_ORDER = {"critical": 0, "moderate": 1, "low": 2, "none": 3}
SEV_COLOR = {"critical": "#B42318", "moderate": "#B54708", "low": "#3E6DB5", "none": "#1E7A46"}
SEV_LABEL = {"critical": "CRITICAL", "moderate": "MODERATE", "low": "LOW", "none": "CLEAR"}

# Design baseline: Abridge — warm paper surfaces, warm ink, red-orange brand
# accent, taupe hairlines. Severity colors stay semantic (deeper, calmer reds)
# so "critical" never reads as brand decoration.
INK = "#141312"
INK2 = "#6D645A"
PAPER = "#FBF9F6"
PAPER2 = "#F7F2ED"
HAIR = "rgba(167,152,138,.35)"
BRAND = "#EA2C00"
BLUE = "#76A8F4"

CSS = f"""
body{{font-family:'Avantt','Inter',-apple-system,'Helvetica Neue',sans-serif;margin:0;
     background:{PAPER};color:{INK}}}
.wrap{{max-width:920px;margin:0 auto;padding:28px 24px}}
header{{background:{INK};color:#fff;padding:22px 26px;border-radius:16px;margin-bottom:24px}}
header h1{{margin:0 0 4px;font-size:23px;letter-spacing:-.01em}}
header h1 .dot{{color:{BRAND}}}
header .sub{{color:rgba(255,255,255,.55);font-size:13.5px}}
.banner{{display:flex;gap:28px;margin-top:14px;font-size:14px;flex-wrap:wrap}}
.banner div b{{display:block;color:rgba(255,255,255,.45);font-size:10.5px;
    text-transform:uppercase;letter-spacing:.08em;margin-bottom:2px}}
h2{{font-size:13.5px;text-transform:uppercase;letter-spacing:.1em;color:{INK2};
   border-bottom:1px solid {HAIR};padding-bottom:8px;margin:34px 0 16px}}
.card{{background:#fff;border-radius:14px;padding:16px;margin-bottom:12px;
      border:1px solid {HAIR};display:flex;gap:16px}}
.card img{{width:180px;height:135px;object-fit:cover;border-radius:10px;flex-shrink:0}}
.sev{{display:inline-block;padding:2px 10px;border-radius:12px;color:#fff;
     font-size:10.5px;font-weight:700;letter-spacing:.06em}}
.card h3{{margin:6px 0 6px;font-size:15.5px;letter-spacing:-.01em}}
.card p{{margin:4px 0;font-size:13.5px;line-height:1.5}}
.card .why{{color:#7A1F00}} .card .rec{{color:#1E7A46;font-weight:600}}
.meta{{color:{INK2};font-size:12.5px}}
.measure{{background:#fff;border-radius:12px;padding:14px 16px;margin-bottom:8px;
         border:1px solid {HAIR};font-size:14px}}
.measure.fail{{border-left:4px solid {BRAND}}}.measure.ok{{border-left:4px solid #1E7A46}}
table{{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;
      border:1px solid {HAIR}}}
td,th{{padding:10px 14px;font-size:13.5px;text-align:left;border-bottom:1px solid {HAIR}}}
th{{background:{PAPER2};color:{INK2};font-size:11px;text-transform:uppercase;
    letter-spacing:.08em}}
.qa{{background:#fff;border-radius:12px;padding:4px 16px;border:1px solid {HAIR}}}
.qa p{{font-size:13.5px;line-height:1.55}}.qa .q{{color:{INK2}}}
.draft{{border:1.5px dashed #B54708;border-radius:12px;padding:14px 16px;margin-bottom:10px;
       background:#FDF6EC;font-size:13.5px}}
.draft b{{display:block;margin-bottom:4px}}
.footer{{color:{INK2};font-size:12px;margin:34px 0 10px;text-align:center;line-height:1.7}}
.pill{{background:{PAPER2};border:1px solid {HAIR};border-radius:10px;padding:1px 9px;
      font-size:11px;color:{INK2}}}
.ob{{background:#fff;border-radius:12px;padding:12px 16px;margin-bottom:8px;
    border:1px solid {HAIR};font-size:13.5px}}
.ob .quote{{color:{INK2};font-style:italic;font-size:12.5px}}
.ob .ev{{margin-top:4px}}
.esc{{background:#fff;border-radius:14px;margin-bottom:12px;overflow:hidden;
     border:1px solid {HAIR};font-size:13.5px}}
.esc .head{{padding:10px 16px;color:#fff;display:flex;justify-content:space-between;
     align-items:center;font-weight:700}}
.esc .body{{padding:12px 16px}}
.esc .body p{{margin:4px 0}}
.esc .k{{color:{INK2};font-size:10.5px;text-transform:uppercase;letter-spacing:.07em;
     display:inline-block;width:86px}}
.embed header,.embed .footer{{display:none}}
.embed .wrap{{padding:6px 18px}}
"""

OB_STATUS = {
    "verified":   ("#1E7A46", "VERIFIED"),
    "at_risk":    ("#B54708", "AT RISK"),
    "blocked":    ("#B42318", "BLOCKED"),
    "unverified": ("#8A8078", "UNVERIFIED"),
}
ESC_COLOR = {"clinical": "#B42318", "operational": "#B54708",
             "social": "#6941C6", "routine": "#3E6DB5"}


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


def render_report(run: Run, embed: bool = False) -> str:
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
<title>HomeReady — Report — {pt['name']}</title><style>{CSS}</style></head>
<body class="{'embed' if embed else ''}">
<div class="wrap">
<header>
  <h1>HomeReady<span class="dot">.</span> Home-Readiness Report</h1>
  <div class="sub">Verify the home before discharge — agent-conducted, STEADI-aligned
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
<p class="meta">HomeReady read the SNF note + after-visit summary (Abridge-style artifacts)
and derived what must be true at home for this plan to work, then scored each against
walkthrough evidence.</p>
{obligations_html or '<p class="meta">Obligation scoring runs when the walkthrough finishes.</p>'}

<h2>2 · Escalations — routed to owners with evidence and deadlines</h2>
{esc_html or '<p class="meta">No exceptions raised yet.</p>'}

<h2>3 · Graded findings</h2>
{cards or '<p class="meta">No findings yet — walkthrough in progress.</p>'}

<h2>4 · Measurements &amp; floor plans (LiDAR)</h2>
{measures or '<p class="meta">No room scans captured.</p>'}
{f'<img src="/floorplan?run={run.id}" style="max-width:100%;background:#fff;border-radius:10px;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:8px">' if getattr(run, "floorplans", []) else ''}

<h2>5 · Patient-reported context (voice walkthrough)</h2>
{confirms}
<div class="qa">{qa or '<p class="meta">No conversation captured.</p>'}</div>

<h2>6 · Drafted actions — not sent, clinician review required</h2>
{dme or '<p class="meta">No DME indicated by findings.</p>'}
<table><tr><th>Route to</th><th>Why</th><th>Priority</th></tr>{routes}</table>

<h2>7 · FHIR write-back (draft)</h2>
<p class="meta">{len(bundle['entry'])} draft resources (Observations, ServiceRequests,
escalation Tasks) — <a href="/report/fhir?run={run.id}">view JSON bundle</a></p>

<div class="footer"><b>Abridge captures the encounter. HomeReady verifies the home.</b><br>
detection: Claude vision · grading: CDC STEADI / HSSAT · measurements: LiDAR ·
all orders and escalations are drafts pending clinician review ·
synthetic patient (Synthea) — demo only</div>
</div></body></html>"""
