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
        # LiDAR result mid-replay: 27in bathroom door + full geometry so the
        # demo report includes a floor plan with the failing door in red
        {"at_frame": 21,
         "roomplan": {
             "room": "bathroom",
             "doors": [{"x": 0.8, "z": 0, "dx": 1, "dz": 0,
                        "len_m": 0.686, "width_m": 0.686}],
             "floor_area_m2": 5.6,
             "geometry": {
                 "walls": [
                     {"x": 1.35, "z": 0, "dx": 1, "dz": 0, "len_m": 2.7},
                     {"x": 1.35, "z": 2.1, "dx": 1, "dz": 0, "len_m": 2.7},
                     {"x": 0, "z": 1.05, "dx": 0, "dz": 1, "len_m": 2.1},
                     {"x": 2.7, "z": 1.05, "dx": 0, "dz": 1, "len_m": 2.1}],
                 "doors": [{"x": 0.8, "z": 0, "dx": 1, "dz": 0,
                            "len_m": 0.686, "width_m": 0.686}],
                 "openings": [],
                 "windows": [{"x": 2.7, "z": 1.0, "dx": 0, "dz": 1, "len_m": 0.7}],
                 "objects": [
                     {"x": 2.15, "z": 0.55, "dx": 1, "dz": 0, "len_m": 0.75,
                      "depth_m": 0.55, "category": "toilet"},
                     {"x": 0.85, "z": 1.65, "dx": 1, "dz": 0, "len_m": 1.6,
                      "depth_m": 0.75, "category": "bathtub"},
                     {"x": 2.25, "z": 1.75, "dx": 1, "dz": 0, "len_m": 0.6,
                      "depth_m": 0.5, "category": "sink"}],
             }}},
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
