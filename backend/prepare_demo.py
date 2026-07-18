"""Turn any walkthrough recording into demo-mode assets.

  ../.venv/bin/python prepare_demo.py ~/Downloads/IMG_5156.MOV

Writes demo_assets/walkthrough.mp4 (h264, streamable), demo_assets/frames/*.jpg
(one per `interval` seconds, 512px), and a default script.json (room timeline +
LiDAR injections) that you can hand-edit for your recording.
"""

import json
import shutil
import subprocess
import sys

from demo import ASSETS, FRAMES, SCRIPT, VIDEO

INTERVAL = 2.5

DEFAULT_SCRIPT = {
    "interval": INTERVAL,
    "rooms": [
        {"from": 0, "room": "living room"},
        {"from": 9, "room": "kitchen"},
        {"from": 15, "room": "hallway"},
        {"from": 20, "room": "bathroom"},
    ],
    "inject": [
        {"at_frame": 21,
         "roomplan": {"room": "bathroom", "doors": [{"width_m": 0.686}],
                      "floor_area_m2": 5.6}},
    ],
}


def main(src: str) -> None:
    ASSETS.mkdir(exist_ok=True)
    if FRAMES.exists():
        shutil.rmtree(FRAMES)
    FRAMES.mkdir()

    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", src,
         "-c:v", "libx264", "-preset", "fast", "-crf", "23",
         "-movflags", "+faststart", "-an", str(VIDEO)], check=True)
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", src,
         "-vf", f"fps=1/{INTERVAL},scale=512:-1", "-q:v", "5",
         str(FRAMES / "f%03d.jpg")], check=True)

    n = len(list(FRAMES.glob("*.jpg")))
    if not SCRIPT.exists():
        SCRIPT.write_text(json.dumps(DEFAULT_SCRIPT, indent=2))
        print(f"wrote default {SCRIPT} — edit room timeline for your recording")
    print(f"demo assets ready: {n} frames, video at {VIDEO}")


if __name__ == "__main__":
    main(sys.argv[1])
