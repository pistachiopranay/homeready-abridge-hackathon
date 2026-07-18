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
from vision import DeepPassWorker, fast_pass

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
    if callout:
        run.add_event(callout)
    return {"frame_index": meta["index"], "callout": callout}


@app.post("/roomplan")
async def roomplan(req: Request):
    body = await req.json()
    run = state.current()
    measurements = ingest_roomplan(body)
    for m in measurements:
        run.add_measurement(m)
        if m.get("kind") in ("door", "opening"):
            run.add_event(f"Measured: {m['label']} is {m['text']}")
    return {"added": len(measurements), "measurements": measurements}


@app.post("/event")
async def event(req: Request):
    body = await req.json()
    state.current().add_event(str(body.get("text", "")))
    return {"ok": True}


@app.post("/walkthrough/finish")
def walkthrough_finish():
    global _worker
    run = state.current()
    if _worker is not None:
        _worker.finish()
        with _worker_lock:
            _worker = None
    run.save()
    return {"run_id": run.id, "n_findings": len(run.findings),
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


@app.get("/healthz")
def healthz():
    return {"ok": True}
