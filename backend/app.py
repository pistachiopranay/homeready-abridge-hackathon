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
    for m in measurements:
        run.add_measurement(m)
        if m.get("kind") not in ("door", "opening"):
            continue
        run.add_event(f"Measured: {m['label']} is {m['text']}")
        # Only a FAILING door is worth the caregiver's attention — clearing
        # doors would stack noise cards (RoomPlan finds many openings per room)
        if m.get("walker_clears") is False:
            run.add_confirmation(
                f"This {m['kind']} measured {m['width_in']}in — too narrow for "
                f"Monica's 28in walker. Does she need to get through it "
                f"day-to-day?", source="lidar")
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
    global _worker
    run = state.current()
    if _worker is not None:
        _worker.finish()
        with _worker_lock:
            _worker = None
    # Close the loop: score care-plan obligations against evidence, route exceptions
    from escalations import build_escalations
    from obligations import score_obligations
    try:
        run.obligations = score_obligations(run)
        run.escalations = build_escalations(run, run.obligations)
    except Exception as e:
        print(f"[finish] obligation scoring failed (report still renders): {e}")
    run.save()
    return {"run_id": run.id, "n_findings": len(run.findings),
            "n_escalations": len(run.escalations),
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
def report(run: str | None = None):
    from report import render_report
    r = state.load_run(run) if run else state.current()
    if r is None:
        return HTMLResponse("<h1>run not found</h1>", status_code=404)
    return render_report(r)


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
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>Relay — runs</title>
<style>body{{font-family:-apple-system,sans-serif;max-width:760px;margin:40px auto;color:#1c2833}}
h1{{font-size:22px}} table{{width:100%;border-collapse:collapse}}
td,th{{padding:8px 12px;border-bottom:1px solid #eaeded;font-size:14px;text-align:left}}
a{{color:#2874a6}} .live{{background:#eafaf1;padding:10px 14px;border-radius:8px}}</style>
</head><body>
<h1>Relay · walkthrough runs</h1>
<p class="live">Live session: <b>{live.id}</b> — {len(live.frames)} frames,
{len(live.findings)} findings so far · <a href="/report">view live report</a></p>
<table><tr><th>run</th><th>frames</th><th>findings</th><th>escalations</th><th></th></tr>
{rows or '<tr><td colspan=5>no finished runs yet</td></tr>'}</table>
</body></html>"""


@app.get("/healthz")
def healthz():
    return {"ok": True}
