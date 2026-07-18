# Steady — post-discharge home-safety walkthrough agent

**Abridge Hackathon 2026.** Falls after hospital discharge are a leading driver of
readmissions: patients leave rehab deconditioned, into homes full of hazards nobody
has assessed. Home-safety evaluations exist (CDC STEADI, HSSAT) — but they require
a clinician home visit that usually never happens.

**Steady** turns any caregiver with an iPad into a clinical-grade home-safety
assessment, conducted *by an agent*:

1. A caregiver walks the home with an iPad Pro. **RoomPlan (LiDAR)** measures rooms
   and doorways; camera frames stream to the backend.
2. **Three-speed perception**: on-device spatial scanning at 0 ms; a Claude Haiku
   fast-pass per frame (~1.3 s) turns hazards into instant voice callouts; a Claude
   Sonnet deep-pass batches frames into STEADI/HSSAT-graded findings.
3. A **full-duplex voice agent** (ElevenLabs, custom-LLM → this backend) guides the
   route, reacts to what the camera sees, and asks chart-aware follow-ups the
   camera can't answer — grounded in the patient's FHIR record.
4. Output: a **clinician report** — graded findings with photos, LiDAR measurements
   ("bathroom door is 27 in; her walker is 28 in"), patient-reported context, drafted
   DME orders with HCPCS codes + Medicare coverage flags, care-team routing, and a
   draft FHIR bundle (Observations + ServiceRequests). Drafted, never auto-sent.

Demo patient: **Monica Hilpert, 76F** (synthetic, from the Abridge
`synthetic-ambient-fhir-25` dataset) — osteoporosis, deconditioned after a week in
hospital + SNF rehab, lives alone, going home Friday. For her, a fall is a fracture.
Every severity grade in the report is argued *for her specifically*.

## Architecture

```
iPad Pro (dumb client)                     Mac backend (all intelligence)
┌─────────────────────────┐               ┌──────────────────────────────────┐
│ RoomPlan scan (LiDAR)   │─ doors/area ─▶│ /roomplan  walker-clearance math │
│ ARSession frames (2.5s) │─ JPEG 512px ─▶│ /frame     Haiku fast-pass ──┐   │
│ ElevenLabs voice SDK    │               │            Sonnet deep-pass  │   │
└───────────┬─────────────┘               │ events + measurements ◀──────┘   │
            │ WebRTC                      │      ▼                           │
   ElevenLabs cloud ── custom LLM ──────▶ │ /v1/chat/completions (SSE brain) │
            (via ngrok)                   │ /report    STEADI HTML + FHIR    │
                                          └──────────────────────────────────┘
```

- **Detection** by Claude vision · **grading** by CDC STEADI/HSSAT · **measurements**
  by LiDAR — no fabricated risk scores anywhere.
- The voice agent's LLM *is* the backend: one brain sees the conversation, the
  camera events, and the chart.

## Run it

```bash
# backend (Mac)
python3 -m venv .venv && .venv/bin/pip install -r backend/requirements.txt
cp .env.example .env   # add ANTHROPIC_API_KEY (+ ELEVENLABS_API_KEY for voice)
cd backend && ../.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000

# voice plumbing (optional): ngrok http 8000, then point an ElevenLabs
# conversational agent's custom-LLM URL at https://<ngrok>/v1

# iPad app
cd ipad && xcodegen generate && open Walkthrough.xcodeproj  # build to iPad Pro w/ LiDAR
```

Open `http://<mac>:8000/report` for the live report; `/report/fhir` for the bundle.

## Built with

FastAPI · Claude (Haiku 4.5 fast-pass, Sonnet 5 deep-pass + brain) · Apple RoomPlan ·
ElevenLabs Conversational AI · FHIR R4 · Abridge synthetic-ambient-fhir-25 dataset.

Built solo during the hackathon, July 18, 2026. Synthetic data only — not a medical device.
