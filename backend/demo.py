"""Demo mode: replay a pre-recorded walkthrough through the REAL pipeline.

Frames from demo_assets/frames/ are posted to our own /frame endpoint at
walkthrough cadence (so fast-pass callouts, dedupe, deep-pass batching, and
Riley's event feed all behave exactly as live), and scripted LiDAR results are
injected at the right moment. The iPad streams demo_assets/walkthrough.mp4 and
runs voice as normal. Swap the recording with backend/prepare_demo.py — no app
rebuild needed.
"""

import base64
import json
import threading
import time

import httpx

from config import ROOT

ASSETS = ROOT / "demo_assets"
FRAMES = ASSETS / "frames"
VIDEO = ASSETS / "walkthrough.mp4"
SCRIPT = ASSETS / "script.json"

BASE = "http://127.0.0.1:8000"


class DemoPlayer:
    def __init__(self) -> None:
        self.thread: threading.Thread | None = None
        self.stop = threading.Event()
        self.frame_i = -1
        self.total = 0

    @property
    def running(self) -> bool:
        return self.thread is not None and self.thread.is_alive()

    def start(self) -> bool:
        if self.running:
            return False
        self.stop.clear()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        return True

    def halt(self) -> None:
        self.stop.set()

    def _run(self) -> None:
        script = json.loads(SCRIPT.read_text()) if SCRIPT.exists() else {}
        rooms = script.get("rooms", [])
        inject = {i["at_frame"]: i for i in script.get("inject", [])}
        interval = float(script.get("interval", 2.5))

        frames = sorted(FRAMES.glob("*.jpg"))
        self.total = len(frames)
        httpx.post(f"{BASE}/walkthrough/start", timeout=10)

        for i, path in enumerate(frames):
            if self.stop.is_set():
                return
            self.frame_i = i
            room = "entry"
            for r in rooms:
                if i >= r.get("from", 0):
                    room = r.get("room", room)
            payload = {"image_b64": base64.b64encode(path.read_bytes()).decode(),
                       "room": room}
            # Fire-and-forget so model latency never desyncs us from the video
            threading.Thread(target=self._post, args=("/frame", payload),
                             daemon=True).start()
            if i in inject and "roomplan" in inject[i]:
                threading.Thread(target=self._post,
                                 args=("/roomplan", inject[i]["roomplan"]),
                                 daemon=True).start()
            time.sleep(interval)

    @staticmethod
    def _post(path: str, payload: dict) -> None:
        try:
            httpx.post(BASE + path, json=payload, timeout=60)
        except Exception as e:
            print(f"[demo] {path} failed: {e}")


player = DemoPlayer()
