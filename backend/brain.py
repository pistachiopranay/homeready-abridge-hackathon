"""The voice agent's brain: an OpenAI-compatible /v1/chat/completions endpoint
that ElevenLabs calls as a Custom LLM. One Claude stream per turn, with the
live scan events + measurements spliced into the system prompt."""

import json
import re
import threading
import time
import uuid
from typing import Iterator

import anthropic

from config import ANTHROPIC_API_KEY, BRAIN_MODEL, FAST_MODEL
from patient import chart_context
from prompts import BRAIN_SYSTEM, CONFIRM_CLASSIFIER
from state import Run

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


def _measurements_text(run: Run) -> str:
    if not run.measurements:
        return "(no measurements yet)"
    lines = []
    for m in run.measurements:
        lines.append(f"- {m.get('label', 'measurement')}: {m.get('text', json.dumps(m))}")
    return "\n".join(lines)


def _system_prompt(run: Run) -> str:
    events = "\n".join(f"- {e}" for e in run.events) or "(none yet — walkthrough starting)"
    pending = run.pending_confirmations()
    conf = "\n".join(f"- [{c['id']}] {c['question']}" for c in pending) or "(none)"
    return BRAIN_SYSTEM.format(patient=chart_context(), events=events,
                               measurements=_measurements_text(run),
                               confirmations=conf)


def _to_anthropic_messages(oai_messages: list[dict]) -> list[dict]:
    """ElevenLabs sends OpenAI-shaped messages; keep user/assistant turns only.
    Anthropic requires alternating roles starting with user."""
    msgs = []
    for m in oai_messages:
        role = m.get("role")
        content = m.get("content") or ""
        if role not in ("user", "assistant") or not str(content).strip():
            continue
        if msgs and msgs[-1]["role"] == role:
            msgs[-1]["content"] += "\n" + str(content)
        else:
            msgs.append({"role": role, "content": str(content)})
    if not msgs or msgs[0]["role"] != "user":
        msgs.insert(0, {"role": "user", "content": "(walkthrough starting — greet briefly)"})
    return msgs


def _sse(payload: dict) -> str:
    return f"data: {json.dumps(payload)}\n\n"


def stream_completion(body: dict, run: Run) -> Iterator[str]:
    """Yield OpenAI-format SSE chunks from a Claude stream."""
    rid = "chatcmpl-" + uuid.uuid4().hex[:12]
    created = int(time.time())
    model_name = body.get("model", "walkthrough-brain")

    def chunk(delta: dict, finish: str | None = None) -> dict:
        return {"id": rid, "object": "chat.completion.chunk", "created": created,
                "model": model_name,
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}

    msgs = _to_anthropic_messages(body.get("messages", []))
    full_reply = []
    try:
        with client.messages.stream(
                model=BRAIN_MODEL, max_tokens=300,
                system=_system_prompt(run), messages=msgs) as stream:
            yield _sse(chunk({"role": "assistant", "content": ""}))
            for text in stream.text_stream:
                full_reply.append(text)
                yield _sse(chunk({"content": text}))
    except Exception as e:
        print(f"[brain] stream error: {e}")
        fallback = "Sorry, I lost my train of thought — could you say that again?"
        full_reply.append(fallback)
        yield _sse(chunk({"content": fallback}))
    yield _sse(chunk({}, finish="stop"))
    yield "data: [DONE]\n\n"

    # Log the turn for the report's "patient-reported context" section
    user_text = ""
    if msgs and msgs[-1]["role"] == "user":
        user_text = msgs[-1]["content"]
        if not user_text.startswith("("):
            run.add_turn("caregiver", user_text)
    run.add_turn("agent", "".join(full_reply))

    # Voice-resolve pending confirmations off the hot path
    if user_text and not user_text.startswith("(") and run.pending_confirmations():
        threading.Thread(target=_classify_confirmations,
                         args=(run, user_text), daemon=True).start()


def _classify_confirmations(run: Run, utterance: str) -> None:
    pending = run.pending_confirmations()
    if not pending:
        return
    listing = "\n".join(f"- id={c['id']}: {c['question']}" for c in pending)
    try:
        resp = client.messages.create(
            model=FAST_MODEL, max_tokens=200,
            messages=[{"role": "user", "content": CONFIRM_CLASSIFIER.format(
                pending=listing, utterance=utterance)}])
        text = "".join(b.text for b in resp.content if b.type == "text")
        m = re.search(r"\{.*\}", text, re.S)
        if not m:
            return
        for r in json.loads(m.group()).get("resolved", []):
            item = run.resolve_confirmation(str(r["id"]), bool(r["answer"]), by="voice")
            if item:
                verdict = "confirmed" if item["status"] == "confirmed" else "said no to"
                run.add_event(f"Caregiver {verdict} (by voice): {item['question']}")
    except Exception as e:
        print(f"[confirm] classifier error: {e}")
