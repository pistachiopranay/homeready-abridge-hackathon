"""In-memory walkthrough state. One run at a time — hackathon scope."""

import json
import threading
import time
import uuid
from collections import deque
from pathlib import Path

from config import RUNS_DIR, EVENTS_KEEP


class Run:
    def __init__(self) -> None:
        self.id = time.strftime("%H%M%S") + "-" + uuid.uuid4().hex[:6]
        self.dir = RUNS_DIR / self.id
        (self.dir / "frames").mkdir(parents=True, exist_ok=True)
        self.started = time.time()

        self.lock = threading.Lock()
        self.events: deque[str] = deque(maxlen=EVENTS_KEEP)   # fast-pass callouts
        self.frames: list[dict] = []       # {index, path, room, ts, deep_done}
        self.findings: list[dict] = []     # deep-pass STEADI findings
        self.measurements: list[dict] = [] # roomplan geometry facts
        self.conversation: list[dict] = [] # {role, text} voice transcript
        self.confirmations: list[dict] = []  # {id, question, status, source, resolved_by}
        self.obligations: list[dict] = []    # scored care-plan obligations (at finish)
        self.escalations: list[dict] = []    # routed exceptions (at finish)
        self.floorplans: list[dict] = []     # captured room geometry per scan
        self.current_room: str = "unknown"

    def add_frame(self, jpeg: bytes, room: str | None) -> dict:
        with self.lock:
            idx = len(self.frames)
            path = self.dir / "frames" / f"{idx:04d}.jpg"
            path.write_bytes(jpeg)
            if room:
                self.current_room = room
            meta = {"index": idx, "path": str(path), "room": room or self.current_room,
                    "ts": time.time(), "deep_done": False}
            self.frames.append(meta)
            return meta

    def add_event(self, text: str) -> None:
        with self.lock:
            self.events.append(text)

    def add_findings(self, items: list[dict]) -> None:
        with self.lock:
            self.findings.extend(items)

    def add_measurement(self, item: dict) -> None:
        with self.lock:
            self.measurements.append(item)

    def add_turn(self, role: str, text: str) -> None:
        with self.lock:
            self.conversation.append({"role": role, "text": text})

    def add_confirmation(self, question: str, source: str) -> dict:
        with self.lock:
            # Don't stack near-duplicate questions
            for c in self.confirmations:
                if c["status"] == "pending" and c["question"] == question:
                    return c
            item = {"id": uuid.uuid4().hex[:8], "question": question,
                    "status": "pending", "source": source,
                    "resolved_by": None, "ts": time.time()}
            self.confirmations.append(item)
            return item

    def resolve_confirmation(self, cid: str, answer: bool, by: str) -> dict | None:
        with self.lock:
            for c in self.confirmations:
                if c["id"] == cid and c["status"] == "pending":
                    c["status"] = "confirmed" if answer else "denied"
                    c["resolved_by"] = by
                    return c
        return None

    def pending_confirmations(self) -> list[dict]:
        with self.lock:
            return [dict(c) for c in self.confirmations if c["status"] == "pending"]

    def pending_deep_frames(self) -> list[dict]:
        with self.lock:
            return [f for f in self.frames if not f["deep_done"]]

    def snapshot(self) -> dict:
        with self.lock:
            return {
                "run_id": self.id,
                "n_frames": len(self.frames),
                "events": list(self.events),
                "n_findings": len(self.findings),
                "measurements": list(self.measurements),
                "conversation_turns": len(self.conversation),
                "current_room": self.current_room,
            }

    def save(self) -> None:
        with self.lock:
            (self.dir / "run.json").write_text(json.dumps({
                "run_id": self.id,
                "findings": self.findings,
                "measurements": self.measurements,
                "conversation": self.conversation,
                "confirmations": self.confirmations,
                "obligations": self.obligations,
                "escalations": self.escalations,
                "floorplans": self.floorplans,
                "events": list(self.events),
                "frames": [{k: v for k, v in f.items()} for f in self.frames],
            }, indent=2))


_current: Run | None = None
_lock = threading.Lock()


def current() -> Run:
    global _current
    with _lock:
        if _current is None:
            _current = Run()
        return _current


def new_run() -> Run:
    global _current
    with _lock:
        _current = Run()
        return _current


def load_run(run_id: str) -> Run | None:
    """Rehydrate a saved run (for report iteration after a walkthrough)."""
    path = Path(RUNS_DIR) / run_id / "run.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    run = Run.__new__(Run)
    run.id = data["run_id"]
    run.dir = RUNS_DIR / run.id
    run.started = 0
    run.lock = threading.Lock()
    run.events = deque(data.get("events", []), maxlen=EVENTS_KEEP)
    run.frames = data.get("frames", [])
    run.findings = data.get("findings", [])
    run.measurements = data.get("measurements", [])
    run.conversation = data.get("conversation", [])
    run.confirmations = data.get("confirmations", [])
    run.obligations = data.get("obligations", [])
    run.escalations = data.get("escalations", [])
    run.floorplans = data.get("floorplans", [])
    run.current_room = "unknown"
    return run
