"""FastAPI backend: dumb iPad in, smart clinical assessment out.

Endpoints:
  POST /walkthrough/start     new run (also spawns deep-pass worker)
  POST /frame                 {image_b64, room?} → Haiku callout → agent event
  POST /roomplan              CapturedRoom-derived JSON → measurements
  POST /event                 raw text event from the app (e.g. scan started)
  POST /walkthrough/finish    drain deep pass, save run
  POST /v1/chat/completions   OpenAI-compatible SSE for ElevenLabs custom LLM
  GET  /state                 debug snapshot
  GET  /report[?run=ID]       clinician-facing HTML report
"""

import asyncio
import base64
import threading
import time

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse

import state
from brain import stream_completion
from geometry import ingest_roomplan
from vision import DeepPassWorker, fast_pass, is_repeat

app = FastAPI(title="walkthrough-backend")

_worker: DeepPassWorker | None = None
_worker_lock = threading.Lock()


def _ensure_worker(run: state.Run) -> None:
    global _worker
    with _worker_lock:
        if _worker is None or _worker.run is not run:
            _worker = DeepPassWorker(run)


@app.post("/walkthrough/start")
def walkthrough_start():
    run = state.new_run()
    _ensure_worker(run)
    return {"run_id": run.id}


@app.post("/frame")
async def frame(req: Request):
    body = await req.json()
    run = state.current()
    _ensure_worker(run)
    jpeg = base64.b64decode(body["image_b64"])
    meta = run.add_frame(jpeg, body.get("room"))

    # Off the event loop — a blocking 1.5s call here would stall the brain's SSE stream
    callout = await asyncio.to_thread(fast_pass, jpeg, list(run.events))
    if callout and is_repeat(callout, list(run.events)):
        callout = None  # near-duplicate of a recent callout
    if callout:
        run.add_event(callout)
    return {"frame_index": meta["index"], "callout": callout}


@app.post("/roomplan")
async def roomplan(req: Request):
    body = await req.json()
    run = state.current()
    measurements = ingest_roomplan(body)
    room = body.get("room", "room")
    geometry = body.get("geometry")
    if geometry:
        with run.lock:
            run.floorplans.append({"room": room, **geometry})
    for m in measurements:
        run.add_measurement(m)
        if m.get("kind") not in ("door", "opening"):
            continue
        run.add_event(f"Measured: {m['label']} is {m['text']}")
        # Only a FAILING door is worth a card — but phrased neutrally; the
        # walker verdict is for the care team, not the caregiver mid-scan
        if m.get("walker_clears") is False:
            run.add_confirmation(
                f"I measured this {m['kind']} at {m['width_in']}in — does Monica "
                f"pass through it day-to-day?", source="lidar")
    return {"added": len(measurements), "measurements": measurements}


@app.post("/event")
async def event(req: Request):
    body = await req.json()
    run = state.current()
    text = str(body.get("text", ""))
    run.add_event(text)
    # Room-start events double as a room-identity confirmation on the overlay
    room = body.get("room")
    if room:
        label = "Monica's front door / entry area" if room == "entry" else f"the {room}"
        run.add_confirmation(f"Just to check — is this {label}?", source="room")
    return {"ok": True}


@app.get("/confirmations")
def confirmations():
    run = state.current()
    with run.lock:
        return {"confirmations": [dict(c) for c in run.confirmations]}


@app.post("/confirmations/{cid}/resolve")
async def resolve_confirmation(cid: str, req: Request):
    body = await req.json()
    run = state.current()
    item = run.resolve_confirmation(cid, bool(body.get("answer")),
                                    by=body.get("by", "tap"))
    if item:
        verdict = "confirmed" if item["status"] == "confirmed" else "said no to"
        run.add_event(f"Caregiver {verdict}: {item['question']}")
    return {"resolved": item is not None, "confirmation": item}


@app.post("/walkthrough/finish")
def walkthrough_finish():
    """Returns immediately; deep-pass drain + obligation scoring + escalations
    finalize in the background (run.json appears when done, at which point the
    care-team surfaces pick this run up)."""
    global _worker
    run = state.current()
    with _worker_lock:
        worker, _worker = _worker, None

    def _finalize():
        from escalations import build_escalations
        from journey import build_approvals
        from obligations import score_obligations
        if worker is not None:
            worker.finish()
        try:
            run.obligations = score_obligations(run)
            run.escalations = build_escalations(run, run.obligations)
            run.approvals = build_approvals(run)
        except Exception as e:
            print(f"[finish] scoring failed (report still renders): {e}")
        run.save()
        print(f"[finish] run {run.id} finalized: {len(run.findings)} findings, "
              f"{len(run.escalations)} escalations")

    threading.Thread(target=_finalize, daemon=True).start()
    return {"run_id": run.id, "processing": True,
            "report_url": f"/report?run={run.id}"}


@app.post("/v1/chat/completions")
async def chat_completions(req: Request):
    body = await req.json()
    run = state.current()
    return StreamingResponse(stream_completion(body, run),
                             media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache"})


@app.get("/state")
def get_state():
    return state.current().snapshot()


@app.get("/report", response_class=HTMLResponse)
def report(run: str | None = None, embed: int = 0):
    from report import render_report
    r = state.load_run(run) if run else state.current()
    if r is None:
        return HTMLResponse("<h1>run not found</h1>", status_code=404)
    return render_report(r, embed=bool(embed))


@app.get("/frames/{run_id}/{index}.jpg")
def frame_image(run_id: str, index: int):
    from fastapi.responses import FileResponse
    from config import RUNS_DIR
    path = RUNS_DIR / run_id / "frames" / f"{index:04d}.jpg"
    if not path.exists():
        return JSONResponse({"error": "frame not found"}, status_code=404)
    return FileResponse(path, media_type="image/jpeg")


@app.get("/report/fhir")
def report_fhir(run: str | None = None):
    from fhir_writeback import draft_bundle
    r = state.load_run(run) if run else state.current()
    if r is None:
        return JSONResponse({"error": "run not found"}, status_code=404)
    return draft_bundle(r)


@app.post("/demo/start")
def demo_start():
    from demo import VIDEO, player
    if not VIDEO.exists():
        return JSONResponse({"error": "no demo assets — run prepare_demo.py"},
                            status_code=404)
    started = player.start()
    return {"started": started, "already_running": not started}


@app.post("/demo/stop")
def demo_stop():
    from demo import player
    player.halt()
    return {"ok": True}


@app.post("/demo/reset")
def demo_reset():
    """Full demo reset: fresh empty live run (clears Monica's 'processing'
    card), demo replay stopped, sample run's approvals back to pending."""
    from demo import player
    from journey import SAMPLE_RUN_ID
    player.halt()
    state.new_run()
    state.chart_cutoff = time.strftime("%H%M%S")  # hide Monica's older runs
    r = state.load_run(SAMPLE_RUN_ID)
    if r is not None:
        with r.lock:
            for a in r.approvals:
                a["status"] = "pending"
            r.discharge_state = "in_review"
        r.save()
    return {"ok": True}


@app.get("/demo/video")
def demo_video():
    from fastapi.responses import FileResponse
    from demo import VIDEO
    if not VIDEO.exists():
        return JSONResponse({"error": "no demo video"}, status_code=404)
    return FileResponse(VIDEO, media_type="video/mp4")


@app.get("/demo/status")
def demo_status():
    from demo import player
    return {"running": player.running, "frame": player.frame_i,
            "total": player.total}


@app.get("/patient/chart")
def get_patient_chart(patient: str = "monica"):
    from journey import patient_chart
    return patient_chart(patient)


@app.get("/patients")
def get_patients():
    from journey import patients
    return {"patients": patients()}


@app.get("/approvals")
def get_approvals(run: str | None = None):
    from journey import latest_finished_run
    r = state.load_run(run) if run else latest_finished_run()
    if r is None:
        return {"run_id": None, "approvals": [], "discharge_state": "in_review"}
    return {"run_id": r.id, "approvals": r.approvals,
            "discharge_state": r.discharge_state,
            "n_frames": len(r.frames),
            "n_blocked": sum(1 for o in r.obligations
                             if o.get("status") == "blocked")}


@app.post("/approvals/{aid}/approve")
async def post_approve(aid: str, req: Request):
    from journey import approve, latest_finished_run
    body = await req.json() if int(req.headers.get("content-length") or 0) else {}
    r = state.load_run(body.get("run")) if body.get("run") else latest_finished_run()
    if r is None:
        return JSONResponse({"error": "no finished run"}, status_code=404)
    item = approve(r, aid)
    return {"approved": item is not None, "discharge_state": r.discharge_state}


@app.post("/discharge/clear")
async def post_discharge_clear(req: Request):
    from journey import clear_for_discharge, latest_finished_run
    body = await req.json() if int(req.headers.get("content-length") or 0) else {}
    r = state.load_run(body.get("run")) if body.get("run") else latest_finished_run()
    if r is None:
        return JSONResponse({"error": "no finished run"}, status_code=404)
    return clear_for_discharge(r)


@app.get("/floorplan")
def floorplan_png(run: str | None = None):
    from fastapi.responses import Response
    from floorplan import render_run
    r = state.load_run(run) if run else state.current()
    if r is None:
        return JSONResponse({"error": "run not found"}, status_code=404)
    return Response(render_run(getattr(r, "floorplans", [])), media_type="image/png")


@app.get("/runs")
def runs_json():
    """Machine-readable run list for the iPad's past-walkthrough browser."""
    import json as _json
    from config import RUNS_DIR
    out = []
    for d in sorted(RUNS_DIR.iterdir(), reverse=True):
        rj = d / "run.json"
        if not rj.exists():
            continue
        try:
            data = _json.loads(rj.read_text())
        except Exception:
            continue
        findings = data.get("findings", [])
        out.append({
            "run_id": d.name,
            "n_frames": len(data.get("frames", [])),
            "n_findings": len(findings),
            "n_critical": sum(1 for f in findings
                              if f.get("severity") == "critical"),
            "n_escalations": len(data.get("escalations", [])),
            "n_blocked": sum(1 for o in data.get("obligations", [])
                             if o.get("status") == "blocked"),
            "has_floorplan": bool(data.get("floorplans")),
            "rooms": sorted({fp.get("room", "?")
                             for fp in data.get("floorplans", [])}),
        })
    return {"runs": out}


@app.get("/", response_class=HTMLResponse)
def index():
    """Care-team entry point: every walkthrough run, newest first."""
    import json as _json
    from config import RUNS_DIR
    rows = ""
    for d in sorted(RUNS_DIR.iterdir(), reverse=True):
        rj = d / "run.json"
        if not rj.exists():
            continue
        try:
            data = _json.loads(rj.read_text())
        except Exception:
            continue
        findings = data.get("findings", [])
        n_crit = sum(1 for f in findings if f.get("severity") == "critical")
        n_blocked = sum(1 for o in data.get("obligations", [])
                        if o.get("status") == "blocked")
        badge = ("<span style='color:#c0392b;font-weight:700'>PLAN BLOCKED</span>"
                 if n_blocked else "")
        rows += (f"<tr><td><a href='/report?run={d.name}'>{d.name}</a></td>"
                 f"<td>{len(data.get('frames', []))}</td>"
                 f"<td>{len(findings)} ({n_crit} critical)</td>"
                 f"<td>{len(data.get('escalations', []))}</td><td>{badge}</td></tr>")
    live = state.current()
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>HomeReady — runs</title>
<style>body{{font-family:-apple-system,sans-serif;max-width:760px;margin:40px auto;color:#1c2833}}
h1{{font-size:22px}} table{{width:100%;border-collapse:collapse}}
td,th{{padding:8px 12px;border-bottom:1px solid #eaeded;font-size:14px;text-align:left}}
a{{color:#2874a6}} .live{{background:#eafaf1;padding:10px 14px;border-radius:8px}}</style>
</head><body>
<h1>HomeReady · walkthrough runs</h1>
<p class="live">Live session: <b>{live.id}</b> — {len(live.frames)} frames,
{len(live.findings)} findings so far · <a href="/report">view live report</a></p>
<table><tr><th>run</th><th>frames</th><th>findings</th><th>escalations</th><th></th></tr>
{rows or '<tr><td colspan=5>no finished runs yet</td></tr>'}</table>
</body></html>"""


@app.get("/healthz")
def healthz():
    return {"ok": True}
