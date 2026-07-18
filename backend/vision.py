"""Two-speed cloud perception.

Fast pass:  Haiku, one frame → one-sentence callout (or SKIP) → voice-agent event.
Deep pass:  Sonnet, batches of frames → STEADI-graded findings for the report.
            Runs in a background thread; spike lesson: retry + max_tokens 4096 +
            tolerant JSON parsing or ~1/3 of batches die on truncation.
"""

import base64
import json
import re
import threading
import time

import anthropic

from config import (ANTHROPIC_API_KEY, DEEP_BATCH_SIZE, DEEP_MAX_TOKENS,
                    DEEP_MODEL, FAST_MODEL)
from patient import chart_context
from prompts import DEEP_PASS_SYSTEM, FAST_PASS_SYSTEM
from state import Run

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


def _text_of(resp) -> str:
    """Sonnet 5 may emit thinking blocks before text — take text blocks only."""
    return "".join(b.text for b in resp.content if b.type == "text")


def _img_block(jpeg: bytes) -> dict:
    return {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                        "data": base64.standard_b64encode(jpeg).decode()}}


def is_repeat(callout: str, events: list[str], threshold: float = 0.5) -> bool:
    """Haiku rewords the same hazard across frames; word-overlap dedupe."""
    words = set(callout.lower().split())
    for e in events:
        ew = set(e.lower().split())
        if words and len(words & ew) / len(words | ew) > threshold:
            return True
    return False


def fast_pass(jpeg: bytes, recent_events: list[str]) -> str | None:
    """One-liner hazard callout, or None if nothing new. Called per uploaded frame."""
    system = FAST_PASS_SYSTEM.format(
        recent="\n".join(recent_events[-5:]) or "(none yet)",
        patient="Monica, 76F, osteoporosis, walker user, discharging home alone.")
    try:
        resp = client.messages.create(
            model=FAST_MODEL, max_tokens=100, system=system,
            messages=[{"role": "user", "content": [_img_block(jpeg)]}])
        text = _text_of(resp).strip()
        return None if (not text or text.upper().startswith("SKIP")) else text
    except Exception as e:
        print(f"[fast_pass] error: {e}")
        return None


def _parse_findings(text: str) -> list[dict]:
    """Tolerant parse: strip fences, then salvage complete objects from a possibly
    truncated JSON array."""
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.M).strip()
    try:
        data = json.loads(text)
        return data if isinstance(data, list) else [data]
    except json.JSONDecodeError:
        pass
    # Salvage: decode objects one by one out of the array body
    items, decoder, i = [], json.JSONDecoder(), text.find("[") + 1
    while i < len(text):
        while i < len(text) and text[i] in " \t\r\n,":
            i += 1
        if i >= len(text) or text[i] != "{":
            break
        try:
            obj, end = decoder.raw_decode(text, i)
            items.append(obj)
            i = end
        except json.JSONDecodeError:
            break
    return items


def deep_pass_batch(frames: list[dict]) -> list[dict]:
    """One Sonnet call over up to DEEP_BATCH_SIZE frames → graded findings."""
    content: list[dict] = []
    for f in frames:
        content.append({"type": "text",
                        "text": f"Frame {f['index']} (room: {f.get('room') or 'unknown'}):"})
        with open(f["path"], "rb") as fh:
            content.append(_img_block(fh.read()))
    content.append({"type": "text", "text": "Return the JSON array of findings now."})

    system = DEEP_PASS_SYSTEM.format(patient=chart_context())
    for attempt in range(3):
        try:
            resp = client.messages.create(
                model=DEEP_MODEL, max_tokens=DEEP_MAX_TOKENS, system=system,
                messages=[{"role": "user", "content": content}])
            found = _parse_findings(_text_of(resp))
            if found or attempt == 2:
                return found
        except Exception as e:
            print(f"[deep_pass] attempt {attempt + 1} error: {e}")
            time.sleep(1.5 * (attempt + 1))
    return []


class DeepPassWorker:
    """Drains un-graded frames in batches while the walkthrough continues."""

    def __init__(self, run: Run):
        self.run = run
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def _loop(self) -> None:
        while not self.stop.is_set():
            pending = self.run.pending_deep_frames()
            batch_ready = len(pending) >= DEEP_BATCH_SIZE
            stale = pending and (time.time() - pending[0]["ts"]) > 15
            if batch_ready or stale:
                self._process(pending[:DEEP_BATCH_SIZE])
            else:
                time.sleep(1.0)
        # Final drain after stop requested
        pending = self.run.pending_deep_frames()
        while pending:
            self._process(pending[:DEEP_BATCH_SIZE])
            pending = self.run.pending_deep_frames()

    def _process(self, batch: list[dict]) -> None:
        findings = deep_pass_batch(batch)
        for f in batch:
            f["deep_done"] = True
        if findings:
            self.run.add_findings(findings)
            print(f"[deep_pass] +{len(findings)} findings "
                  f"(frames {batch[0]['index']}–{batch[-1]['index']})")

    def finish(self, timeout: float = 90.0) -> None:
        """Signal end of walkthrough and wait for the final drain."""
        self.stop.set()
        self.thread.join(timeout=timeout)
