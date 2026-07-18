"""Env + constants for the walkthrough backend."""

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNS_DIR = ROOT / "runs"
DATASET = ROOT / "synthetic-ambient-fhir-25" / "synthetic-ambient-fhir-25.jsonl"

# Demo patient: Monica Hilpert, 76F, SNF discharge → home
PATIENT_RECORD_PREFIX = "b504cdf2"

# Monica's walker width in inches — the number the doorway check compares against.
# Standard adult folding walker is 26–28in; hers is the wide model.
WALKER_WIDTH_IN = 28.0

FAST_MODEL = "claude-haiku-4-5"   # ~1.1–1.5s/frame measured
DEEP_MODEL = "claude-sonnet-5"    # ~2.2–2.6s, used in background batches
BRAIN_MODEL = "claude-sonnet-5"   # voice agent brain

DEEP_BATCH_SIZE = 6               # frames per deep-pass call (spike-proven)
DEEP_MAX_TOKENS = 4096            # spike lesson: truncation below this
EVENTS_KEEP = 10                  # recent fast-pass events spliced into brain prompt


def _load_env() -> None:
    env_file = ROOT / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


_load_env()

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
FAL_KEY = os.environ.get("FAL_KEY", "")
